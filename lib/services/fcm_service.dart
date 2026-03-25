import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FCMService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin
  _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

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
        payload: message.data.toString(),
      );
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  static void _handleMessage(RemoteMessage message) {
    print('Handling message: ${message.data}');
    // Navigate to appropriate screen based on message type
    final data = message.data;
    final type = data['type'];

    switch (type) {
      case 'notice':
        print('Navigate to notices screen');
        break;
      case 'announcement':
        print('Navigate to announcements screen');
        break;
      case 'assignment':
        print('Navigate to assignments screen');
        break;
      case 'message': // ADD THIS CASE
        print('Navigate to messages screen');
        // You might want to navigate to messages screen
        // This would require a navigation service or context
        break;
      default:
        print('Unknown message type: $type');
    }
  }

  // Also update the _handleNotificationTap method:
  static void _handleNotificationTap(String? payload) {
    print('Notification tapped with payload: $payload');
    // Handle notification tap - you can navigate to specific screens here
    // Parse payload and navigate to messages screen if it's a message notification
    try {
      if (payload != null && payload.contains('type')) {
        // You would need to implement navigation logic here
        // This typically requires a global navigation key or service
      }
    } catch (e) {
      print('Error handling notification tap: $e');
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
