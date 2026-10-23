import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'teacher_dashboard_screen.dart';
import 'student_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';
import 'driver_dashboard_screen.dart';
import 'initial_login_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SchoolCodeScreen extends StatefulWidget {
  final String? userId;

  const SchoolCodeScreen({super.key, this.userId});

  @override
  State<SchoolCodeScreen> createState() => _SchoolCodeScreenState();
}

class _SchoolCodeScreenState extends State<SchoolCodeScreen> {
  final _schoolCodeController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;
  bool _isCheckingSchool = false;
  bool _hasInternet = true;

  bool get _isPreLoginMode => widget.userId == null;

  Future<bool> _checkInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<bool> _validateSchoolCode(String schoolCode) async {
    if (schoolCode.length != 6) {
      return false;
    }

    setState(() {
      _isCheckingSchool = true;
    });

    try {
      final schoolSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolCode)
          .get();

      // Check if document exists and has required fields
      if (schoolSnapshot.exists) {
        final schoolData = schoolSnapshot.data()!;
        final schoolStatus =
            schoolData['status']?.toString().toLowerCase() ?? 'active';
        final schoolName = schoolData['name'] ?? '';

        return schoolStatus == 'active' && schoolName.isNotEmpty;
      }
      return false;
    } catch (e) {
      print('Error validating school code: $e');

      // Improved network error detection
      if (_isNetworkError(e)) {
        setState(() {
          _hasInternet = false;
        });
        throw Exception(
          'No internet connection. Please check your network and try again.',
        );
      }

      // Provide specific error message based on error type
      if (e.toString().contains('PERMISSION_DENIED')) {
        throw Exception(
          'Firestore permission denied. Please check your security rules.',
        );
      } else if (e.toString().contains('UNAVAILABLE')) {
        throw Exception(
          'Network error. Please check your internet connection.',
        );
      } else {
        throw Exception('Failed to validate school code: $e');
      }
    } finally {
      setState(() {
        _isCheckingSchool = false;
      });
    }
  }

  Future<void> _submitSchoolCode() async {
    final enteredCode = _schoolCodeController.text.trim();

    if (enteredCode.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a school code';
      });
      return;
    }

    if (enteredCode.length != 6) {
      setState(() {
        _errorMessage = 'School code must be 6 digits';
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
      // Validate school code
      final isValidSchool = await _validateSchoolCode(enteredCode);

      if (!isValidSchool) {
        setState(() {
          _errorMessage = 'Invalid school code or school is inactive';
        });
        return;
      }

      // Get school details
      final schoolSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(enteredCode)
          .get();

      final schoolName = schoolSnapshot.data()?['name'] ?? 'Unknown School';

      if (_isPreLoginMode) {
        // Pre-login mode: Store school code and redirect to login
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('school_code', enteredCode);
        await prefs.setString('school_name', schoolName);

        print('✅ School code stored: $enteredCode - $schoolName');

        // Navigate to login screen using direct navigation instead of named route
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const InitialLoginScreen()),
          (route) => false,
        );
      } else {
        // Post-login mode: Original logic for existing users
        await _handlePostLoginSchoolCode(enteredCode, schoolName);
      }
    } catch (e) {
      print('School code submission error: $e');

      // Improved network error detection
      if (_isNetworkError(e)) {
        setState(() {
          _hasInternet = false;
        });
      } else {
        setState(() {
          _errorMessage = e.toString();
        });
      }

      // Show detailed error in snackbar only for non-network errors
      if (!_isNetworkError(e)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Helper method to detect network errors
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

  Future<void> _handlePostLoginSchoolCode(
    String enteredCode,
    String schoolName,
  ) async {
    try {
      // Fetch user document
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId!)
          .get();

      if (!userSnapshot.exists) {
        setState(() {
          _errorMessage = 'User data not found';
        });
        return;
      }

      final userData = userSnapshot.data()!;
      final storedCode = userData['school_code'] as String?;
      final role = userData['role']?.toString().toLowerCase() ?? 'unknown';

      // Check user status (default to 'active' if missing)
      final userStatus =
          userData['status']?.toString().toLowerCase() ?? 'active';
      if (userStatus != 'active') {
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

      // Validate school code assignment
      if (storedCode == null) {
        // If no stored code, update with entered code
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId!)
            .update({'school_code': enteredCode, 'school_name': schoolName});
      } else if (storedCode != enteredCode) {
        setState(() {
          _errorMessage =
              'Incorrect school code. Please contact your school administrator.';
        });
        return;
      }

      // Proceed to appropriate dashboard
      _navigateToDashboard(role, enteredCode, schoolName);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    }
  }

  void _navigateToDashboard(String role, String schoolCode, String schoolName) {
    Widget destinationScreen;

    switch (role) {
      case 'teacher':
        destinationScreen = TeacherDashboardScreen(
          userId: widget.userId!,
          schoolName: schoolName,
          schoolCode: schoolCode,
        );
        break;
      case 'admin':
        destinationScreen = AdminDashboardScreen(
          userId: widget.userId!,
          schoolCode: schoolCode,
          schoolName: schoolName,
        );
        break;
      case 'student':
        destinationScreen = StudentDashboardScreen(
          userId: widget.userId!,
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
        setState(() {
          _errorMessage = 'Unknown user role: $role';
        });
        return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => destinationScreen),
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
          color: Colors.grey[400],
        ),
        const SizedBox(height: 20),
        Text(
          'No Internet Connection',
          style: TextStyle(
            fontSize: isWideScreen ? 24 : 20,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Please check your internet connection to validate school code.',
          style: TextStyle(
            fontSize: isWideScreen ? 16 : 14,
            color: Colors.grey[600],
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

  // Responsive layout helper
  bool get _isMobile => MediaQuery.of(context).size.width < 600;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 600;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWideScreen = size.width > 600;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: isWideScreen ? _buildDesktopLayout() : _buildMobileLayout(),
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
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: _buildCommonContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoInternetLayout() {
    final size = MediaQuery.of(context).size;
    final bool isWideScreen = size.width > 600;

    return Center(
      child: Container(
        constraints: isWideScreen ? const BoxConstraints(maxWidth: 500) : null,
        margin: isWideScreen
            ? const EdgeInsets.all(40)
            : const EdgeInsets.all(24),
        child: _buildNoInternetWidget(),
      ),
    );
  }

  List<Widget> _buildCommonContent() {
    // Remove the no internet check from here since we're handling it in the parent layouts
    return [
      const Icon(Icons.school, size: 80, color: Colors.blue),
      const SizedBox(height: 20),
      Text(
        _isPreLoginMode ? 'Welcome to Student App' : 'School Access',
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _isPreLoginMode
            ? 'Please enter your school code to continue'
            : 'Enter your 6-digit school code to access your dashboard',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, color: Colors.grey),
      ),
      const SizedBox(height: 40),

      // School Code Input
      TextField(
        controller: _schoolCodeController,
        decoration: InputDecoration(
          labelText: 'School Code',
          hintText: 'Enter 6-digit code',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.code),
          suffixIcon: _isCheckingSchool
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, letterSpacing: 2),
        onChanged: (value) {
          if (_errorMessage != null) {
            setState(() {
              _errorMessage = null;
            });
          }
        },
      ),
      const SizedBox(height: 20),

      // Submit Button
      SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _submitSchoolCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
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
              : Text(
                  _isPreLoginMode ? 'Continue to Login' : 'Access Dashboard',
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
        ),
      ),

      // Error Message
      if (_errorMessage != null) ...[
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.error, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Error',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],

      // Help Text
      const SizedBox(height: 40),
      const Text(
        'Don\'t know your school code?',
        style: TextStyle(color: Colors.grey),
      ),
      TextButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please contact your school administrator for the school code.',
              ),
            ),
          );
        },
        child: const Text('Get Help'),
      ),
    ];
  }

  @override
  void dispose() {
    _schoolCodeController.dispose();
    super.dispose();
  }
}
