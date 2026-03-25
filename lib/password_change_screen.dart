import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class PasswordChangeScreen extends StatefulWidget {
  final String userId;

  const PasswordChangeScreen({super.key, required this.userId});

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;
  bool _hasInternet = true;

  Future<bool> _checkInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _changePassword() async {
    if (_newPasswordController.text.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters';
      });
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
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
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email;

      if (email == null) {
        throw Exception('User email not found');
      }

      // Re-authenticate user before password change
      try {
        final credential = EmailAuthProvider.credential(
          email: email,
          password: _currentPasswordController.text,
        );
        await user!.reauthenticateWithCredential(credential);
      } catch (e) {
        throw Exception('Current password is incorrect');
      }

      // Update password in Firebase Auth
      await user.updatePassword(_newPasswordController.text);
      await user.getIdToken(true);

      // Update the is_first_login flag in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({
            //'password': _newPasswordController.text,
            'is_first_login': false,
          });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Check user role for navigation
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (snapshot.exists) {
        final userData = snapshot.data() as Map<String, dynamic>;
        final role = userData['role']?.toString().toLowerCase() ?? 'unknown';

        if (role == 'super_admin') {
          Navigator.pushReplacementNamed(
            context,
            '/super_admin',
            arguments: widget.userId,
          );
        } else {
          Navigator.pushReplacementNamed(
            context,
            '/school_code',
            arguments: widget.userId,
          );
        }
      }
    } catch (e) {
      // Improved network error detection
      if (_isNetworkError(e)) {
        setState(() {
          _hasInternet = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Error changing password: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
          'Please check your internet connection to change your password.',
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWideScreen = size.width > 600;

    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Container(
            constraints: isWideScreen
                ? const BoxConstraints(maxWidth: 500)
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _hasInternet
                  ? _buildPasswordForm()
                  : [_buildNoInternetWidget()],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPasswordForm() {
    return [
      TextField(
        controller: _currentPasswordController,
        decoration: const InputDecoration(
          labelText: 'Current Password',
          hintText: 'Enter your current password',
          border: OutlineInputBorder(),
        ),
        obscureText: true,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _newPasswordController,
        decoration: const InputDecoration(
          labelText: 'New Password',
          hintText: 'At least 6 characters',
          border: OutlineInputBorder(),
        ),
        obscureText: true,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _confirmPasswordController,
        decoration: const InputDecoration(
          labelText: 'Confirm New Password',
          border: OutlineInputBorder(),
        ),
        obscureText: true,
      ),
      const SizedBox(height: 20),
      if (_isLoading)
        const CircularProgressIndicator()
      else
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _changePassword,
            child: const Text('Change Password'),
          ),
        ),
      if (_errorMessage != null) ...[
        const SizedBox(height: 16),
        Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      ],
    ];
  }
}
