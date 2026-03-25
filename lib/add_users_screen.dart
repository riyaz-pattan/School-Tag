import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:io';

class AddUsersScreen extends StatefulWidget {
  final String userId;

  const AddUsersScreen({super.key, required this.userId});

  @override
  State<AddUsersScreen> createState() => _AddUsersScreenState();
}

class _AddUsersScreenState extends State<AddUsersScreen> {
  String? _selectedRole = 'admin';
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _alternateMobileController = TextEditingController();
  final _schoolTelephoneController = TextEditingController();
  final _gmailController = TextEditingController();
  final _schoolCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _status = 'active';
  String? _errorMessage;
  bool _isLoading = false;

  List<String> _availableSchoolCodes = [];
  List<String> _availableSchoolNames = [];
  Map<String, String> _schoolCodeToName = {};

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  void initState() {
    super.initState();
    _fetchSchools();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _mobileController.dispose();
    _alternateMobileController.dispose();
    _schoolTelephoneController.dispose();
    _gmailController.dispose();
    _schoolCodeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _fetchSchools() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .where('status', isEqualTo: 'active')
          .get();

      setState(() {
        _availableSchoolCodes = snapshot.docs.map((doc) => doc.id).toList();
        _availableSchoolNames = snapshot.docs
            .map((doc) => doc['name'] as String)
            .toList();
        _schoolCodeToName = {
          for (var doc in snapshot.docs) doc.id: doc['name'] as String,
        };
      });
    } catch (e) {
      print('Error fetching schools: $e');
    }
  }

  Future<void> _createUser() async {
    final username = _usernameController.text.trim();
    final schoolCode = _schoolCodeController.text.trim();
    final password = _passwordController.text.trim();
    final fullName = _fullNameController.text.trim(); // NEW: Get full name

    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Admin ID is required';
      });
      return;
    }
    if (schoolCode.isEmpty) {
      setState(() {
        _errorMessage = 'School code is required';
      });
      return;
    }
    if (password.isEmpty || password.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters';
      });
      return;
    }
    // NEW: Check if full name is provided
    if (fullName.isEmpty) {
      setState(() {
        _errorMessage = 'Full Name is required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Prepare user data for cloud function
      Map<String, dynamic> userData = {
        'username': username,
        'role': _selectedRole,
        'schoolCode': schoolCode,
        'password': password,
        'status': _status,
        'full_name':
            fullName, // NEW: Always include full name as required field
      };

      // Add optional fields (excluding full_name since it's now required and already added above)
      _addOptionalField(userData, _mobileController.text, 'mobile_number');
      _addOptionalField(userData, _gmailController.text, 'gmail');
      _addOptionalField(
        userData,
        _alternateMobileController.text,
        'alternate_mobile_number',
      );
      _addOptionalField(
        userData,
        _schoolTelephoneController.text,
        'school_telephone_number',
      );

      // Call cloud function
      final result = await _functions.httpsCallable('createUser').call({
        'userData': userData,
      });

      final response = result.data;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message']),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );

      _clearFields();
    } catch (e) {
      print('Error creating user: $e');

      // Extract the actual error message from the Firebase Functions exception
      String errorMessage = 'Error creating user';
      if (e is FirebaseFunctionsException) {
        errorMessage = e.message ?? 'Unknown error occurred';
      } else if (e.toString().contains('already-exists')) {
        errorMessage =
            'Username already exists. Please try a different username.';
      } else if (e.toString().contains('permission-denied')) {
        errorMessage =
            'Permission denied. You are not authorized to perform this action.';
      } else if (e.toString().contains('invalid-argument')) {
        errorMessage = 'Invalid input. Please check your data and try again.';
      } else {
        errorMessage = 'Error creating user: ${e.toString()}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addOptionalField(
    Map<String, dynamic> data,
    String value,
    String fieldName,
  ) {
    if (value.trim().isNotEmpty) {
      data[fieldName] = value.trim();
    }
  }

  void _clearFields() {
    _usernameController.clear();
    _fullNameController.clear();
    _mobileController.clear();
    _alternateMobileController.clear();
    _schoolTelephoneController.clear();
    _gmailController.clear();
    _schoolCodeController.clear();
    _passwordController.clear();
    setState(() {
      _status = 'active';
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Admin User'),
        backgroundColor: Colors.blue[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Admin User',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Username Field
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Admin ID (Username) *',
                hintText: 'Enter Admin ID/Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // School Selection
            DropdownButtonFormField<String>(
              value: _schoolCodeController.text.isEmpty
                  ? null
                  : _schoolCodeController.text,
              decoration: const InputDecoration(
                labelText: 'School *',
                border: OutlineInputBorder(),
              ),
              hint: const Text('Select a school'),
              items: List.generate(_availableSchoolCodes.length, (index) {
                return DropdownMenuItem<String>(
                  value: _availableSchoolCodes[index],
                  child: Text(
                    '${_availableSchoolNames[index]} (${_availableSchoolCodes[index]})',
                  ),
                );
              }),
              onChanged: (String? newValue) {
                setState(() {
                  _schoolCodeController.text = newValue ?? '';
                });
              },
            ),
            const SizedBox(height: 16),

            // Full Name Field (Now Required)
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                hintText: 'Enter full name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Password Field
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password *',
                hintText: 'Set a password (min 6 chars)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            // Optional Fields
            TextField(
              controller: _mobileController,
              decoration: const InputDecoration(
                labelText: 'Mobile Number (Optional)',
                hintText: 'Enter mobile number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _gmailController,
              decoration: const InputDecoration(
                labelText: 'Gmail (Optional)',
                hintText: 'Enter gmail address',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            // Admin Specific Fields
            TextField(
              controller: _alternateMobileController,
              decoration: const InputDecoration(
                labelText: 'Alternate Mobile Number (Optional)',
                hintText: 'Enter alternate mobile number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _schoolTelephoneController,
              decoration: const InputDecoration(
                labelText: 'School Telephone Number (Optional)',
                hintText: 'Enter school telephone number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            // Status Field
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: ['active', 'inactive'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _status = newValue;
                });
              },
            ),
            const SizedBox(height: 16),

            // Error Message
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createUser,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Create Admin',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
