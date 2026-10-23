import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:student_app/password_change_screen.dart';
import 'package:student_app/school_code_screen.dart';
import 'package:student_app/initial_login_screen.dart';
import 'package:student_app/services/fcm_service.dart';
import 'package:student_app/admin_dashboard_screen.dart';
import 'package:student_app/teacher_dashboard_screen.dart';
import 'package:student_app/student_dashboard_screen.dart';
import 'package:student_app/super_admin_home_screen.dart';
import 'package:student_app/driver_dashboard_screen.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      print('Firebase already initialized: ${e.message}');
    } else {
      rethrow;
    }
  } catch (e) {
    print('❌ Firebase initialization failed: $e');
  }

  // Initialize FCM only on mobile (not on web) and handle errors
  if (!kIsWeb) {
    try {
      await FCMService.initialize();
      print('✅ FCM initialized successfully');
    } catch (e) {
      print('❌ FCM initialization failed: $e');
      // Continue running the app even if FCM fails
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'app',
      title: 'School Management App',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const AuthWrapper(), // Use AuthWrapper as home
      routes: {
        '/school_code': (context) => const SchoolCodeScreen(),
        '/initial_login': (context) => const InitialLoginScreen(),
        '/password_change': (context) => PasswordChangeScreen(
          userId: ModalRoute.of(context)!.settings.arguments as String,
        ),
      },
      // Fallback to handle direct navigation
      onGenerateRoute: (settings) {
        // Handle direct navigation to SchoolCodeScreen
        if (settings.name == '/school_code') {
          return MaterialPageRoute(
            builder: (context) => const SchoolCodeScreen(),
          );
        }
        // Handle direct navigation to InitialLoginScreen
        if (settings.name == '/initial_login') {
          return MaterialPageRoute(
            builder: (context) => const InitialLoginScreen(),
          );
        }
        return null;
      },
      onUnknownRoute: (settings) {
        // Fallback to school code screen for any unknown route
        return MaterialPageRoute(
          builder: (context) => const SchoolCodeScreen(),
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _hasInternet = true;
  Widget? _initialScreen;

  @override
  void initState() {
    super.initState();
    _checkInternetAndAuthStatus();
  }

  Future<void> _checkInternetAndAuthStatus() async {
    setState(() {
      _isLoading = true;
    });

    // Check internet connection first
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      setState(() {
        _hasInternet = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _hasInternet = true;
    });

    await _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      // Check if user is signed in with Firebase Auth
      final User? user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final schoolCode = prefs.getString('school_code');

      if (user != null) {
        // User is signed in with Firebase Auth, now check Firestore for user data
        await _loadUserDataAndNavigate(user.uid);
      } else if (schoolCode != null) {
        // No user signed in but school code exists - go to login screen
        setState(() {
          _initialScreen = const InitialLoginScreen();
          _isLoading = false;
        });
      } else {
        // No user signed in and no school code - go to school code screen
        setState(() {
          _initialScreen = const SchoolCodeScreen();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error checking auth status: $e');
      // If there's any error, default to school code screen
      setState(() {
        _initialScreen = const SchoolCodeScreen();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserDataAndNavigate(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!snapshot.exists) {
        // User document doesn't exist, sign out and go to login
        await FirebaseAuth.instance.signOut();
        setState(() {
          _initialScreen = const SchoolCodeScreen();
          _isLoading = false;
        });
        return;
      }

      final user = snapshot.data() as Map<String, dynamic>;
      final role = user['role']?.toString().toLowerCase() ?? 'unknown';
      final isFirstLogin = user['is_first_login'] ?? false;
      final userStatus = user['status']?.toString().toLowerCase() ?? 'active';

      // Check user status
      if (userStatus != 'active') {
        await FirebaseAuth.instance.signOut();
        setState(() {
          _initialScreen = const SchoolCodeScreen();
          _isLoading = false;
        });
        return;
      }

      // Check if first login
      if (isFirstLogin) {
        setState(() {
          _initialScreen = PasswordChangeScreen(userId: userId);
          _isLoading = false;
        });
        return;
      }

      // Get school code from SharedPreferences for school users
      final prefs = await SharedPreferences.getInstance();
      final schoolCode = prefs.getString('school_code');
      final schoolName = prefs.getString('school_name');

      // Navigate to appropriate dashboard based on role
      if (role == 'super_admin') {
        setState(() {
          _initialScreen = SuperAdminHomeScreen(userId: userId);
          _isLoading = false;
        });
      } else {
        // For school users, we need school code
        if (schoolCode != null && schoolName != null) {
          switch (role) {
            case 'admin':
              setState(() {
                _initialScreen = AdminDashboardScreen(
                  userId: userId,
                  schoolCode: schoolCode,
                  schoolName: schoolName,
                );
                _isLoading = false;
              });
              break;
            case 'teacher':
              setState(() {
                _initialScreen = TeacherDashboardScreen(
                  userId: userId,
                  schoolCode: schoolCode,
                  schoolName: schoolName,
                );
                _isLoading = false;
              });
              break;
            case 'student':
              setState(() {
                _initialScreen = StudentDashboardScreen(
                  userId: userId,
                  schoolName: schoolName,
                  schoolCode: schoolCode,
                );
                _isLoading = false;
              });
              break;
            case 'driver':
              setState(() {
                _initialScreen = DriverDashboardScreen(
                  schoolCode: schoolCode,
                );
                _isLoading = false;
              });
              break;
            default:
              // Unknown role, sign out and go to login
              await FirebaseAuth.instance.signOut();
              setState(() {
                _initialScreen = const SchoolCodeScreen();
                _isLoading = false;
              });
          }
        } else {
          // School code not found, go to school code screen
          setState(() {
            _initialScreen = SchoolCodeScreen(userId: userId);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
      // If there's any error, sign out and go to login
      await FirebaseAuth.instance.signOut();
      setState(() {
        _initialScreen = const SchoolCodeScreen();
        _isLoading = false;
      });
    }
  }

  Widget _buildNoInternetWidget() {
    final size = MediaQuery.of(context).size;
    final bool isWideScreen = size.width > 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Container(
          constraints: isWideScreen
              ? const BoxConstraints(maxWidth: 500)
              : null,
          margin: isWideScreen
              ? const EdgeInsets.all(40)
              : const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              Text(
                'No Internet Connection',
                style: TextStyle(
                  fontSize: isWideScreen ? 28 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Please check your internet connection and try again.',
                style: TextStyle(
                  fontSize: isWideScreen ? 16 : 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: isWideScreen ? 200 : double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _checkInternetAndAuthStatus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text(
                    'Retry',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasInternet) {
      return _buildNoInternetWidget();
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon/splashscreen.png',
                width: 130,
                height: 130,
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(
                color: Colors.blue,
                strokeWidth: 4,
              ),
              const SizedBox(height: 20),
              const Text(
                "Loading ON-E...",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return _initialScreen ?? const SchoolCodeScreen();
  }
}
