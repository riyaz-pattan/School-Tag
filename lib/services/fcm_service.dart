import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FCMService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin
  _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static final StreamController<String> _onNotificationTappedController = StreamController<String>.broadcast();
  static Stream<String> get onNotificationTapped => _onNotificationTappedController.stream;
  static String? pendingRouteType;

  // Background message handler - must be static or top-level function
  static Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    print("Handling a background message: ${message.messageId}");
    print('Message data: ${message.data}');

    // If you're going to use other Firebase services in the background, such as Firestore,
    // make sure to call `initializeApp` before using other Firebase services.
    //await Firebase.initializeApp();

    // Show notification
    await _showNotification(message);
  }

  static Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      // Set the background messaging handler early on, as a named top-level function
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Request permission
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(alert: true, badge: true, sound: true);

      print('User granted permission: ${settings.authorizationStatus}');

      // Initialize local notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          );

      const InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS,
          );

      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse:
            (NotificationResponse notificationResponse) {
              // Handle notification tap
              print('Notification tapped: ${notificationResponse.payload}');
              _handleNotificationTap(notificationResponse.payload);
            },
      );

      // Get FCM token
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        print('FCM Token: $token');
        await _saveFCMToken(token);
      }

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Got a message whilst in the foreground!');
        print('Message data: ${message.data}');

        if (message.notification != null) {
          print(
            'Message also contained a notification: ${message.notification}',
          );
          _showNotification(message);
        }
      });

      // Handle when app is in background but not terminated
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('A new onMessageOpenedApp event was published!');
        _handleMessage(message);
      });

      // Handle initial message when app is terminated
      RemoteMessage? initialMessage = await _firebaseMessaging
          .getInitialMessage();
      if (initialMessage != null) {
        _handleMessage(initialMessage);
      }

      // Token refresh
      _firebaseMessaging.onTokenRefresh.listen((String token) async {
        print('FCM Token refreshed: $token');
        await _saveFCMToken(token);
      });
    } catch (e) {
      print('Error initializing FCM: $e');
    }
  }

  static Future<void> _saveFCMToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      print('FCM token saved locally');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  static Future<String?> getFCMToken() async {
    if (kIsWeb) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('fcm_token');
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  static Future<void> _showNotification(RemoteMessage message) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'school_app_channel',
            'School App Notifications',
            channelDescription:
                'This channel is used for important school notifications.',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
          );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: DarwinNotificationDetails(),
      );

      await _flutterLocalNotificationsPlugin.show(
        message.hashCode,
        message.notification?.title ?? 'New Message',
        message.notification?.body ?? 'You have a new notification',
        platformChannelSpecifics,
        payload: message.data['type']?.toString() ?? '',
      );
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  static void _handleMessage(RemoteMessage message) {
    print('Handling message: ${message.data}');
    final type = message.data['type']?.toString();
    if (type != null && type.isNotEmpty) {
      pendingRouteType = type;
      _onNotificationTappedController.add(type);
    }
  }

  static void _handleNotificationTap(String? payload) {
    print('Notification tapped with payload: $payload');
    if (payload != null && payload.isNotEmpty) {
      pendingRouteType = payload;
      _onNotificationTappedController.add(payload);
    }
  }

  static Future<void> subscribeToSchool(
    String schoolCode,
    String userId,
    String role,
  ) async {
    if (kIsWeb) return;

    try {
      // Subscribe to role-specific topic (exclude school topic to prevent admin notifications)
      await _firebaseMessaging.subscribeToTopic('${schoolCode}_$role');

      // Subscribe to user-specific topic for personal notifications
      await _firebaseMessaging.subscribeToTopic('user_$userId');

      print('Subscribed to topics: ${schoolCode}_$role, user_$userId');

      // Save FCM token to user document in Firestore
      String? token = await getFCMToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update(
          {
            'fcm_tokens': FieldValue.arrayUnion([token]),
            'updated_at': FieldValue.serverTimestamp(),
          },
        );
      }
    } catch (e) {
      print('Error subscribing to FCM topics: $e');
    }
  }

  // NEW: Non-blocking unsubscribe that doesn't wait for completion
  static void unsubscribeFromAllNonBlocking(
    String schoolCode,
    String userId,
    String role,
  ) {
    if (kIsWeb) return;

    // Start the unsubscribe process but don't wait for it
    Future.microtask(() async {
      try {
        await _firebaseMessaging.unsubscribeFromTopic('${schoolCode}_$role');
        await _firebaseMessaging.unsubscribeFromTopic('user_$userId');
        print('Unsubscribed from all topics');
      } catch (e) {
        print('Error unsubscribing from FCM topics (non-blocking): $e');
        // Don't rethrow - this is non-blocking
      }
    });
  }
}
