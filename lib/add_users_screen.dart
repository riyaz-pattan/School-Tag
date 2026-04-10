import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AddUsersScreen extends StatefulWidget {
  final String userId;

  const AddUsersScreen({super.key, required this.userId});

  @override
  State<AddUsersScreen> createState() => _AddUsersScreenState();
}

class _AddUsersScreenState extends State<AddUsersScreen> {
  final String _selectedRole = 'admin';
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
      });
    } catch (e) {
      debugPrint('Error fetching schools: $e');
    }
  }

  Future<void> _createUser() async {
    final username = _usernameController.text.trim();
    final schoolCode = _schoolCodeController.text.trim();
    final password = _passwordController.text.trim();
    final fullName = _fullNameController.text.trim();

    if (username.isEmpty) {
      setState(() => _errorMessage = 'Admin ID is required');
      return;
    }
    if (schoolCode.isEmpty) {
      setState(() => _errorMessage = 'School code is required');
      return;
    }
    if (password.isEmpty || password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }
    if (fullName.isEmpty) {
      setState(() => _errorMessage = 'Full Name is required');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Map<String, dynamic> userData = {
        'username': username,
        'role': _selectedRole,
        'schoolCode': schoolCode,
        'password': password,
        'status': _status,
        'full_name': fullName,
      };

      _addOptionalField(userData, _mobileController.text, 'mobile_number');
      _addOptionalField(userData, _gmailController.text, 'gmail');
      _addOptionalField(userData, _alternateMobileController.text, 'alternate_mobile_number');
      _addOptionalField(userData, _schoolTelephoneController.text, 'school_telephone_number');

      final result = await _functions.httpsCallable('createUser').call({
        'userData': userData,
      });

      final response = result.data;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
               const Icon(Icons.check_circle_outline, color: Colors.white),
               const SizedBox(width: 12),
               Expanded(child: Text(response['message'] ?? 'User created successfully', style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          backgroundColor: const Color(0xFF006D36),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(20),
        ),
      );

      _clearFields();
    } catch (e) {
      String errorMessage = 'Error creating user';
      if (e is FirebaseFunctionsException) {
        errorMessage = e.message ?? 'Unknown error occurred';
      } else if (e.toString().contains('already-exists')) {
         errorMessage = 'Username already exists. Please try a different username.';
      } else if (e.toString().contains('permission-denied')) {
        errorMessage = 'Permission denied. You are not authorized to perform this action.';
      }

      setState(() => _errorMessage = errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _addOptionalField(Map<String, dynamic> data, String value, String fieldName) {
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
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFF),
      appBar: AppBar(
        title: const Text('Add Admin User', style: TextStyle(color: Color(0xFF001F2A), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF001F2A)),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            width: isDesktop ? 600 : double.infinity,
            margin: EdgeInsets.all(isDesktop ? 32 : 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF001F2A).withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(isDesktop ? 40 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F6FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.person_add_rounded, color: Color(0xFF00113A), size: 28),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Create New Admin',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF001F2A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Provision a new administrative account for a specific school branch.',
                    style: TextStyle(color: Color(0xFF757682), fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  _buildModernTextField(
                    controller: _usernameController,
                    label: 'Admin ID (Username) *',
                    icon: Icons.badge_rounded,
                  ),
                  const SizedBox(height: 16),
                  _buildModernDropdown(),
                  const SizedBox(height: 16),
                  _buildModernTextField(
                    controller: _fullNameController,
                    label: 'Full Name *',
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 16),
                  _buildModernTextField(
                    controller: _passwordController,
                    label: 'Password *',
                    icon: Icons.lock_rounded,
                    isPassword: true,
                  ),
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(color: Color(0xFFE6F6FF)),
                  ),
                  const Text(
                    'Optional Contact Information',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF757682)),
                  ),
                  const SizedBox(height: 16),

                  _buildModernTextField(
                    controller: _mobileController,
                    label: 'Mobile Number',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  _buildModernTextField(
                    controller: _gmailController,
                    label: 'Gmail Address',
                    icon: Icons.email_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  _buildModernTextField(
                    controller: _alternateMobileController,
                    label: 'Alternate Mobile',
                    icon: Icons.phone_android_rounded,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  _buildModernTextField(
                    controller: _schoolTelephoneController,
                    label: 'School Telephone',
                    icon: Icons.phone_in_talk_rounded,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  _buildStatusDropdown(),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00113A), Color(0xFF399E9D)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                           BoxShadow(
                             color: const Color(0xFF00113A).withOpacity(0.2),
                             blurRadius: 12,
                             offset: const Offset(0, 4),
                           ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _createUser,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text(
                                'Create Admin',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF001F2A)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF757682)),
        prefixIcon: Icon(icon, color: const Color(0xFF757682)),
        filled: true,
        fillColor: const Color(0xFFF4FAFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE6F6FF), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF006D36), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  Widget _buildModernDropdown() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: _schoolCodeController.text.isEmpty ? null : _schoolCodeController.text,
      icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF757682)),
      decoration: InputDecoration(
        labelText: 'School *',
        labelStyle: const TextStyle(color: Color(0xFF757682)),
        prefixIcon: const Icon(Icons.account_balance_rounded, color: Color(0xFF757682)),
        filled: true,
        fillColor: const Color(0xFFF4FAFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE6F6FF), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF006D36), width: 2),
        ),
      ),
      items: List.generate(_availableSchoolCodes.length, (index) {
        return DropdownMenuItem(
          value: _availableSchoolCodes[index],
          child: Text(
            '${_availableSchoolNames[index]} (${_availableSchoolCodes[index]})',
            style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF001F2A)),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
      }),
      onChanged: (newValue) {
        setState(() {
          _schoolCodeController.text = newValue ?? '';
        });
      },
    );
  }

  Widget _buildStatusDropdown() {
    return DropdownButtonFormField<String>(
      value: _status,
      icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF757682)),
      decoration: InputDecoration(
        labelText: 'Account Status',
        labelStyle: const TextStyle(color: Color(0xFF757682)),
        prefixIcon: Icon(
          _status == 'active' ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: _status == 'active' ? const Color(0xFF006D36) : Colors.red,
        ),
        filled: true,
        fillColor: const Color(0xFFF4FAFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE6F6FF), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF006D36), width: 2),
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'active', child: Text('Active', style: TextStyle(fontWeight: FontWeight.w600))),
        DropdownMenuItem(value: 'inactive', child: Text('Inactive', style: TextStyle(fontWeight: FontWeight.w600))),
      ],
      onChanged: (newValue) {
        setState(() {
          _status = newValue;
        });
      },
    );
  }
}
