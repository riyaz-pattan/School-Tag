// initial_login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'teacher_dashboard_screen.dart';
import 'student_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';
import 'driver_dashboard_screen.dart';
import 'super_admin_home_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class InitialLoginScreen extends StatefulWidget {
  const InitialLoginScreen({super.key});

  @override
  State<InitialLoginScreen> createState() => _InitialLoginScreenState();
}

class _InitialLoginScreenState extends State<InitialLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;
  String? _schoolCode;
  String? _schoolName;
  String? _schoolPhotoUrl;
  Uint8List? _localSchoolImage;
  bool _isLoadingImage = false;
  bool _hasInternet = true;

  @override
  void initState() {
    super.initState();
    _loadStoredSchoolCode();
  }

  Future<bool> _checkInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _loadStoredSchoolCode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _schoolCode = prefs.getString('school_code');
      _schoolName = prefs.getString('school_name');
    });
    print('Loaded School Code: $_schoolCode, School Name: $_schoolName');

    // Load school photo from local cache first
    if (_schoolCode != null) {
      await _loadSchoolPhotoFromCache();
    }
  }

  Future<void> _loadSchoolPhotoFromCache() async {
    try {
      setState(() {
        _isLoadingImage = true;
      });

      // Try to load from local cache first
      final cachedImage = await _getCachedSchoolImage(_schoolCode!);
      if (cachedImage != null) {
        print('✅ Loaded school photo from local cache');
        setState(() {
          _localSchoolImage = cachedImage;
          _isLoadingImage = false;
        });
        return;
      }

      // If not in cache, check internet and load from Firestore
      final hasInternet = await _checkInternetConnection();
      if (!hasInternet) {
        setState(() {
          _hasInternet = false;
          _isLoadingImage = false;
        });
        return;
      }

      await _loadAndCacheSchoolPhoto();
    } catch (e) {
      print('❌ Error loading school photo from cache: $e');
      setState(() {
        _isLoadingImage = false;
      });
    }
  }

  Future<Uint8List?> _getCachedSchoolImage(String schoolCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final imagePath = prefs.getString('school_image_$schoolCode');

      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          return await file.readAsBytes();
        } else {
          // Remove invalid cache entry
          await prefs.remove('school_image_$schoolCode');
        }
      }
      return null;
    } catch (e) {
      print('Error reading cached image: $e');
      return null;
    }
  }

  Future<void> _cacheSchoolImage(
    String schoolCode,
    Uint8List imageBytes,
  ) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imagePath = '${directory.path}/school_$schoolCode.jpg';
      final file = File(imagePath);

      await file.writeAsBytes(imageBytes);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('school_image_$schoolCode', imagePath);

      print('✅ School image cached locally: $imagePath');
    } catch (e) {
      print('❌ Error caching school image: $e');
    }
  }

  Future<void> _loadAndCacheSchoolPhoto() async {
    try {
      final schoolSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolCode)
          .get();

      if (schoolSnapshot.exists) {
        final schoolData = schoolSnapshot.data() as Map<String, dynamic>?;
        final photoUrl = schoolData?['photo_url'];

        if (photoUrl != null && photoUrl is String && photoUrl.isNotEmpty) {
          print('🔄 Downloading school photo from Firebase...');

          // Download image from Firebase Storage using http package
          final response = await http.get(Uri.parse(photoUrl));

          if (response.statusCode == 200) {
            final bytes = response.bodyBytes;

            // Cache the image locally
            await _cacheSchoolImage(_schoolCode!, bytes);

            setState(() {
              _localSchoolImage = bytes;
              _schoolPhotoUrl = photoUrl;
            });
            print('✅ School photo downloaded and cached');
          } else {
            print(
              '❌ Failed to download school photo. Status: ${response.statusCode}',
            );
          }
        } else {
          print('ℹ️ No photo URL found for school');
        }
      }
    } catch (e) {
      print('❌ Error loading school photo: $e');
    } finally {
      setState(() {
        _isLoadingImage = false;
      });
    }
  }

  Future<void> _clearSchoolImageCache(String schoolCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final imagePath = prefs.getString('school_image_$schoolCode');

      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          await file.delete();
        }
        await prefs.remove('school_image_$schoolCode');
        print('✅ Cleared cached image for school: $schoolCode');
      }
    } catch (e) {
      print('❌ Error clearing cached image: $e');
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both username and password';
      });
      return;
    }

    if (_schoolCode == null) {
      setState(() {
        _errorMessage = 'School code is required. Please go back and enter it.';
      });
      return;
    }

    // Check internet connection first
    final hasInternet = await _checkInternetConnection();
    if (!hasInternet) {
      setState(() {
        _hasInternet = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasInternet = true;
    });

    try {
      print('Attempting login with username: $username');
      await _loginWithSchoolCode(username, password);
    } catch (e) {
      print('Login error: $e');

      // Improved network error detection
      if (_isNetworkError(e)) {
        setState(() {
          _hasInternet = false;
        });
      } else {
        setState(() {
          _errorMessage = _getUserFriendlyErrorMessage(e);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage ?? 'Login failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Add this helper method to detect network errors
  bool _isNetworkError(dynamic error) {
    final errorString = error.toString();
    return errorString.contains('network') ||
        errorString.contains('SocketException') ||
        errorString.contains('UNAVAILABLE') ||
        errorString.contains('INTERNET') ||
        errorString.contains('connection') ||
        errorString.contains('unreachable') ||
        errorString.contains('Failed host lookup') ||
        errorString.contains('Network is unreachable') ||
        (error is FirebaseException &&
            (error.code == 'unavailable' ||
                error.code == 'network-request-failed'));
  }

  Future<void> _loginWithSchoolCode(String username, String password) async {
    print('Logging into school: $_schoolCode');
    final email = '${username}_$_schoolCode@studentapp.com';
    print('Attempting login with: $email');

    final userCredential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);

    await _handleSuccessfulLogin(userCredential);
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'User not found. Please check your username.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        case 'invalid-credential':
          return 'Invalid login credentials. Please check your username and password.';
        default:
          return 'Login failed: ${error.message}';
      }
    }
    return 'Login failed: $error';
  }

  Future<void> _handleSuccessfulLogin(UserCredential userCredential) async {
    final userId = userCredential.user!.uid;
    print('Login successful for userId: $userId');

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();

    if (!snapshot.exists) {
      await FirebaseAuth.instance.signOut();
      setState(() {
        _errorMessage = 'User data not found in database';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User data not found in database'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = snapshot.data() as Map<String, dynamic>;
    final role = user['role']?.toString().toLowerCase() ?? 'unknown';
    final isFirstLogin = user['is_first_login'] ?? false;

    print('User role: $role, isFirstLogin: $isFirstLogin');

    final userStatus = user['status']?.toString().toLowerCase() ?? 'active';
    if (userStatus != 'active') {
      await FirebaseAuth.instance.signOut();
      setState(() {
        _errorMessage =
            'Your account is not active. Please contact administrator.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your account is not active. Please contact administrator.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String? effectiveSchoolCode =
        _schoolCode ?? (user['school_code'] as String?);
    if (effectiveSchoolCode != null) {
      final schoolSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(effectiveSchoolCode)
          .get();

      if (!schoolSnapshot.exists) {
        await FirebaseAuth.instance.signOut();
        setState(() {
          _errorMessage = 'Associated school not found. Contact administrator.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Associated school not found. Contact administrator.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final schoolData = schoolSnapshot.data()!;
      final schoolStatus =
          schoolData['status']?.toString().toLowerCase() ?? 'active';
      if (schoolStatus != 'active') {
        await FirebaseAuth.instance.signOut();
        setState(() {
          _errorMessage = 'School is not active. Login not allowed.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('School is not active. Login not allowed.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (_schoolName == null && schoolData['name'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('school_name', schoolData['name'].toString());
        await prefs.setString('school_code', effectiveSchoolCode);
      }

      // Check if school photo has changed and update cache if needed
      final currentPhotoUrl = schoolData['photo_url'];
      if (currentPhotoUrl != null && currentPhotoUrl != _schoolPhotoUrl) {
        print('🔄 School photo updated, refreshing cache...');
        await _clearSchoolImageCache(effectiveSchoolCode);
        await _loadAndCacheSchoolPhoto();
      }
    }

    if (isFirstLogin) {
      print('Redirecting to password change screen');
      Navigator.pushReplacementNamed(
        context,
        '/password_change',
        arguments: snapshot.id,
      );
      return;
    }

    if (role == 'super_admin') {
      print('Redirecting to Super Admin dashboard');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SuperAdminHomeScreen(userId: snapshot.id),
        ),
      );
      return;
    }

    print('User is school user, proceeding to dashboard');
    _navigateToSchoolDashboard(role, snapshot.id, user);
  }

  void _navigateToSchoolDashboard(
    String role,
    String userId,
    Map<String, dynamic> userData,
  ) {
    final schoolCode = _schoolCode ?? userData['school_code'];
    final schoolName =
        _schoolName ?? userData['school_name'] ?? 'Unknown School';

    print('Navigating to $role dashboard for school: $schoolCode');

    Widget destinationScreen;

    switch (role) {
      case 'teacher':
        destinationScreen = TeacherDashboardScreen(
          userId: userId,
          schoolName: schoolName,
          schoolCode: schoolCode,
        );
        break;
      case 'admin':
        destinationScreen = AdminDashboardScreen(
          userId: userId,
          schoolCode: schoolCode,
          schoolName: schoolName,
        );
        break;
      case 'student':
        destinationScreen = StudentDashboardScreen(
          userId: userId,
          schoolName: schoolName,
          schoolCode: schoolCode,
        );
        break;
      case 'driver':
        destinationScreen = DriverDashboardScreen(
          schoolCode: schoolCode,
        );
        break;
      default:
        throw Exception('Unknown role: $role');
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => destinationScreen),
    );
  }

  void _goBackToSchoolCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('school_code');
    await prefs.remove('school_name');

    Navigator.pushReplacementNamed(context, '/school_code');
  }

  void _showForgotPasswordMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Contact your school admin for password assistance',
          textAlign: TextAlign.center,
        ),
        backgroundColor: Colors.blue[700],
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildNoInternetWidget() {
    final size = MediaQuery.of(context).size;
    final bool isWideScreen = size.width > 600;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.wifi_off,
          size: isWideScreen ? 80 : 60,
          color: Colors.white70,
        ),
        const SizedBox(height: 20),
        Text(
          'No Internet Connection',
          style: TextStyle(
            fontSize: isWideScreen ? 24 : 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Please check your internet connection to sign in.',
          style: TextStyle(
            fontSize: isWideScreen ? 16 : 14,
            color: Colors.white70,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: isWideScreen ? 200 : double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () async {
              final hasInternet = await _checkInternetConnection();
              setState(() {
                _hasInternet = hasInternet;
              });
              if (hasInternet) {
                await _loadSchoolPhotoFromCache();
              }
            },
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWideScreen = size.width > 600;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _schoolCode != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _goBackToSchoolCode,
                tooltip: 'Change School',
              )
            : null,
      ),
      body: Stack(
        children: [
          // Background Image - Using local cached image if available
          if (_localSchoolImage != null && _hasInternet)
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: MemoryImage(_localSchoolImage!),
                  fit: isWideScreen ? BoxFit.cover : BoxFit.cover,
                ),
              ),
              child: Container(color: Colors.black.withOpacity(0.4)),
            )
          else if (_isLoadingImage)
            Container(
              color: Colors.grey[900],
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            Container(
              color: Colors.grey[900],
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),

          // Content
          SafeArea(
            child: isWideScreen ? _buildDesktopLayout() : _buildMobileLayout(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    if (!_hasInternet) {
      return _buildNoInternetLayout();
    }

    return SingleChildScrollView(
      child: Container(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildCommonContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    if (!_hasInternet) {
      return _buildNoInternetLayout();
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        margin: const EdgeInsets.all(40),
        child: Card(
          elevation: 0,
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(40.0),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 20,
                  spreadRadius: 5,
                  color: Colors.black.withOpacity(0.3),
                ),
              ],
            ),
            child: BackdropFilter(
              filter: const ColorFilter.matrix([
                0.5,
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                0.5,
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                0.5,
                0.0,
                0.0,
                0.0,
                0.0,
                0.0,
                0.2,
                0.0,
              ]),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildCommonContent(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoInternetLayout() {
    return Center(child: _buildNoInternetWidget());
  }

  List<Widget> _buildCommonContent() {
    // Remove the no internet check from here since we're handling it in the parent layouts
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    return [
      const Icon(Icons.person, size: 80, color: Colors.white),
      const SizedBox(height: 20),

      // School name and code (always shown)
      Text(
        _schoolName ?? 'School Login',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        'School Code: $_schoolCode',
        style: const TextStyle(fontSize: 16, color: Colors.white70),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),

      const Text(
        'Sign in to your account',
        style: TextStyle(fontSize: 14, color: Colors.white70),
        textAlign: TextAlign.center,
      ),

      const SizedBox(height: 40),

      // Username field
      TextField(
        controller: _usernameController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: 'Username / ID',
          labelStyle: const TextStyle(color: Colors.white70),
          hintText: 'Enter your username or ID',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.person, color: Colors.white70),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white),
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
        ),
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 16),

      // Password field
      TextField(
        controller: _passwordController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: 'Password',
          labelStyle: const TextStyle(color: Colors.white70),
          hintText: 'Enter your password',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.lock, color: Colors.white70),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white),
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
        ),
        obscureText: true,
        onSubmitted: (_) => _login(),
      ),

      // Error message
      if (_errorMessage != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red),
          ),
          child: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],

      const SizedBox(height: 24),

      // Sign In button
      ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 5,
          shadowColor: Colors.blue.withOpacity(0.5),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Sign In',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),

      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Text(
          'Enter your username and password for ${_schoolName ?? "your school"}',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ),

      // Change School + Forgot Password
      if (_schoolCode != null) ...[
        const SizedBox(height: 20),
        TextButton(
          onPressed: _goBackToSchoolCode,
          child: const Text(
            'Change School',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showForgotPasswordMessage,
          child: Text(
            'Forgot password/username?',
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue[200],
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ];
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
