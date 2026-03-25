import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';

class UserManagementScreen extends StatefulWidget {
  final String userId;

  const UserManagementScreen({super.key, required this.userId});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  // Firebase Cloud Functions instance used for admin operations like deleting users
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedRoleFilter = 'admin'; // Only show admin users
  String _selectedSchoolFilter = 'all';

  List<String> _availableSchools = [];
  Map<String, String> _schoolCodeToName = {};

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;

  @override
  void initState() {
    super.initState();
    _fetchSchools();
  }

  Future<void> _fetchSchools() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .where('status', isEqualTo: 'active')
          .get();

      setState(() {
        _availableSchools =
            ['all'] + snapshot.docs.map((doc) => doc.id).toList();
        _schoolCodeToName = {
          for (var doc in snapshot.docs) doc.id: doc['name'] as String,
        };
      });
    } catch (e) {
      print('Error fetching schools: $e');
    }
  }

  // NEW: Reset Password Function for Super Admin
  Future<void> _resetUserPassword(
    String userId,
    String username,
    String role,
  ) async {
    bool confirmReset = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: Colors.orange),
            SizedBox(width: 8),
            Text('Reset Password'),
          ],
        ),
        content: Text(
          'This will generate a new temporary password for admin user "$username".\n\nThey will be forced to change it on next login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Reset Password',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );

    if (confirmReset != true) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Resetting password...'),
          ],
        ),
      ),
    );

    try {
      // Call the Cloud Function to reset password
      final result = await _functions.httpsCallable('resetUserPassword').call({
        'targetUid': userId,
        'username': username,
        'role': role,
      });

      final response = result.data;

      // Close loading dialog
      Navigator.pop(context);

      // Show success dialog with temporary password
      await showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: BoxConstraints(
              maxWidth: _isMobile
                  ? MediaQuery.of(context).size.width * 0.9
                  : 400,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Password Reset Successfully',
                        style: TextStyle(
                          fontSize: _isMobile ? 18 : 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Temporary Password Section
                Text(
                  'Temporary Password for "$username":',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: _isMobile
                      ? _buildMobilePasswordLayout(
                          response['tempPassword'],
                          context,
                        )
                      : _buildDesktopPasswordLayout(
                          response['tempPassword'],
                          context,
                        ),
                ),

                const SizedBox(height: 12),

                // Additional Info
                if (response['authEmail'] != null) ...[
                  Text(
                    'Auth Email: ${response['authEmail']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                ],

                const SizedBox(height: 8),

                // Warning
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Admin must change this temporary password on next login.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Close Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.pop(context);

      String errorMessage = 'Error resetting password';
      if (e.toString().contains('permission-denied')) {
        errorMessage = 'You do not have permission to reset passwords';
      } else if (e.toString().contains('not-found')) {
        errorMessage =
            'Admin user not found in authentication system.\n\n'
            'This admin exists in the database but not in the authentication system. '
            'Please contact support or recreate the admin account.';
      } else {
        errorMessage = 'Error: ${e.toString().replaceAll('Exception: ', '')}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Helper methods for responsive password layout
  Widget _buildMobilePasswordLayout(String tempPassword, BuildContext context) {
    return Column(
      children: [
        // Password Text - Centered and selectable
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: SelectableText(
            tempPassword,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        // Copy Button - Full width
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: tempPassword));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy Password'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopPasswordLayout(
    String tempPassword,
    BuildContext context,
  ) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: SelectableText(
              tempPassword,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Copy to clipboard',
          child: IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: tempPassword));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _deleteUser(String userId, String username) async {
    bool confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Admin User'),
        content: Text(
          'Are you sure you want to delete admin user "$username"? This action will remove the user from both database and authentication system and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Deleting admin user...'),
            ],
          ),
        ),
      );

      try {
        // Call cloud function to delete user from both Firestore and Auth
        final result = await _functions.httpsCallable('deleteUser').call({
          'userId': userId,
          'username': username,
        });

        final response = result.data;

        // Close loading dialog
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message']),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      } catch (e) {
        // Close loading dialog
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting admin user: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editUser(Map<String, dynamic> userData, String userId) {
    showDialog(
      context: context,
      builder: (context) => EditUserDialog(
        userData: userData,
        userId: userId,
        availableSchools: _availableSchools
            .where((school) => school != 'all')
            .toList(),
        schoolCodeToName: _schoolCodeToName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin User Management'),
        backgroundColor: Colors.blue[700],
      ),
      body: Column(
        children: [
          // Search and Filter Section
          _buildSearchFilters(),

          // User Statistics
          _buildUserStatistics(),

          // User List
          Expanded(child: _buildUserList()),
        ],
      ),
    );
  }

  Widget _buildSearchFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        children: [
          // Search Bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search admin users by username...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
          ),

          const SizedBox(height: 12),

          // Filters Row
          Row(
            children: [
              // School Filter
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 120),
                  child: DropdownButtonFormField<String>(
                    value: _selectedSchoolFilter,
                    decoration: const InputDecoration(
                      labelText: 'School',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    items: _availableSchools.map((String schoolCode) {
                      String displayName = schoolCode == 'all'
                          ? 'All Schools'
                          : '${_schoolCodeToName[schoolCode] ?? 'Unknown'}';

                      return DropdownMenuItem<String>(
                        value: schoolCode,
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedSchoolFilter = newValue ?? 'all';
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserStatistics() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final users = snapshot.data!.docs;

        // Calculate statistics for admin users only
        final adminUsers = users.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['role'] == 'admin';
        }).toList();

        final totalAdmins = adminUsers.length;
        final activeAdmins = adminUsers.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] == 'active';
        }).length;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard('Total Admins', totalAdmins, Colors.blue),
              _buildStatCard('Active Admins', activeAdmins, Colors.green),
              _buildRoleCard('Your Role', 'Super Admin', Colors.purple),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildRoleCard(String title, String role, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            role,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildUserList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var users = snapshot.data!.docs;

        // Filter to show only admin users
        users = users.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final role = data['role']?.toString() ?? '';
          return role == 'admin';
        }).toList();

        // Apply filters
        if (_searchQuery.isNotEmpty) {
          users = users.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final username = data['username']?.toString().toLowerCase() ?? '';
            return username.contains(_searchQuery);
          }).toList();
        }

        if (_selectedSchoolFilter != 'all') {
          users = users.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final schoolCode = data['school_code']?.toString() ?? '';
            return schoolCode == _selectedSchoolFilter;
          }).toList();
        }

        if (users.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.admin_panel_settings, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No admin users found',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final userData = user.data() as Map<String, dynamic>;
            final userId = user.id;
            final username = userData['username'] ?? 'No username';
            final role = userData['role'] ?? 'unknown';
            final schoolCode = userData['school_code'] ?? 'No school';
            final schoolName =
                userData['school_name'] ??
                _schoolCodeToName[schoolCode] ??
                'Unknown School';
            final isFirstLogin = userData['is_first_login'] ?? false;
            final createdAt = userData['created_at']?.toDate();
            final createdBy = userData['created_by'] ?? 'Unknown';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getRoleColor(role),
                  child: Text(
                    username[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  username,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Role: ${role.toUpperCase()}'),
                    Text('School: $schoolName ($schoolCode)'),
                    if (createdAt != null)
                      Text(
                        'Created: ${_formatDate(createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    Text(
                      'Created by: $createdBy',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (isFirstLogin)
                      const Text(
                        '⚠️ First login required',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _editUser(userData, userId);
                        break;
                      case 'reset_password':
                        _resetUserPassword(userId, username, role);
                        break;
                      case 'delete':
                        _deleteUser(userId, username);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Edit Admin'),
                        ],
                      ),
                    ),
                    // NEW: Reset Password menu item
                    const PopupMenuItem(
                      value: 'reset_password',
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_reset,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text('Reset Password'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Delete Admin',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getRoleColor(String role) {
    return Colors.purple; // Admin color
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// Edit User Dialog (for admin users only)
class EditUserDialog extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;
  final List<String> availableSchools;
  final Map<String, String> schoolCodeToName;

  const EditUserDialog({
    super.key,
    required this.userData,
    required this.userId,
    required this.availableSchools,
    required this.schoolCodeToName,
  });

  @override
  State<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<EditUserDialog> {
  late String _selectedSchool;
  late String _selectedStatus;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _alternateMobileController =
      TextEditingController();
  final TextEditingController _schoolTelephoneController =
      TextEditingController();
  final TextEditingController _gmailController = TextEditingController();

  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedSchool = widget.userData['school_code'] ?? '';
    _selectedStatus = widget.userData['status'] ?? 'active';

    // Initialize all controllers with existing data
    _usernameController.text = widget.userData['username'] ?? '';
    _fullNameController.text = widget.userData['full_name'] ?? '';
    _mobileController.text = widget.userData['mobile_number'] ?? '';
    _alternateMobileController.text =
        widget.userData['alternate_mobile_number'] ?? '';
    _schoolTelephoneController.text =
        widget.userData['school_telephone_number'] ?? '';
    _gmailController.text = widget.userData['gmail'] ?? '';
  }

  Future<void> _updateUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Base user data - admin fields only
      Map<String, dynamic> updateData = {
        'role': 'admin', // Always admin role
        'status': _selectedStatus,
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Add common optional fields
      final fullName = _fullNameController.text.trim();
      if (fullName.isNotEmpty) {
        updateData['full_name'] = fullName;
      }

      final mobileNumber = _mobileController.text.trim();
      if (mobileNumber.isNotEmpty) {
        updateData['mobile_number'] = mobileNumber;
      }

      final gmail = _gmailController.text.trim();
      if (gmail.isNotEmpty) {
        updateData['gmail'] = gmail;
      }

      final alternateMobile = _alternateMobileController.text.trim();
      if (alternateMobile.isNotEmpty) {
        updateData['alternate_mobile_number'] = alternateMobile;
      }

      final schoolTelephone = _schoolTelephoneController.text.trim();
      if (schoolTelephone.isNotEmpty) {
        updateData['school_telephone_number'] = schoolTelephone;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update(updateData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin user updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error updating admin user: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSchoolName =
        widget.schoolCodeToName[_selectedSchool] ?? 'Unknown School';

    return AlertDialog(
      title: const Text('Edit Admin User'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Username Field (Read-only)
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Admin ID (Username)',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color.fromARGB(255, 244, 240, 240),
                hintStyle: TextStyle(color: Color.fromARGB(255, 117, 117, 117)),
              ),
              readOnly: true,
              enabled: false,
            ),
            const SizedBox(height: 16),
            Text(
              'Username cannot be changed as it is used for login',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),

            // School Display (Locked/Read-only)
            TextField(
              decoration: InputDecoration(
                labelText: 'School (Cannot be changed)',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[100],
                prefixIcon: const Icon(Icons.lock, size: 20),
                suffixIcon: Tooltip(
                  message:
                      'School assignment cannot be modified for existing admin users',
                  child: const Icon(Icons.info_outline, size: 18),
                ),
              ),
              readOnly: true,
              controller: TextEditingController(
                text: '$currentSchoolName ($_selectedSchool)',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'School assignment is permanent and cannot be changed for security reasons',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),

            // Status Selection
            DropdownButtonFormField<String>(
              value: _selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: ['active', 'inactive'].map((String status) {
                return DropdownMenuItem<String>(
                  value: status,
                  child: Text(status[0].toUpperCase() + status.substring(1)),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedStatus = newValue!;
                });
              },
            ),
            const SizedBox(height: 16),

            // Common Fields
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                hintText: 'Enter full name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _mobileController,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                hintText: 'Enter mobile number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _gmailController,
              decoration: const InputDecoration(
                labelText: 'Gmail',
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
                labelText: 'Alternate Mobile Number',
                hintText: 'Enter alternate mobile number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _schoolTelephoneController,
              decoration: const InputDecoration(
                labelText: 'School Telephone Number',
                hintText: 'Enter school telephone number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            // Error Message
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _updateUser,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save Changes'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // Dispose all controllers
    _usernameController.dispose();
    _fullNameController.dispose();
    _mobileController.dispose();
    _alternateMobileController.dispose();
    _schoolTelephoneController.dispose();
    _gmailController.dispose();
    super.dispose();
  }
}
