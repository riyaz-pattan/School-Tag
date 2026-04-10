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
      backgroundColor: const Color(0xFFF4FAFF),
      appBar: AppBar(
        title: const Text('Manage Network Admins', style: TextStyle(color: Color(0xFF001F2A), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00113A)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchFilters(),
          Expanded(child: _buildUserList()),
        ],
      ),
    );
  }

  Widget _buildSearchFilters() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF001F2A).withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero Title
          Row(
             children: [
                Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(color: const Color(0xFFE6F6FF), borderRadius: BorderRadius.circular(16)),
                   child: const Icon(Icons.shield_rounded, color: Color(0xFF00113A), size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                   child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Text('Network Administrators', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF001F2A))),
                         SizedBox(height: 4),
                         Text('Manage and configure super-level access.', style: TextStyle(fontSize: 14, color: Color(0xFF757682))),
                      ],
                   ),
                ),
             ],
          ),
          const SizedBox(height: 32),
          
          // Search & Filter Row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search administrators...',
                    hintStyle: const TextStyle(color: Color(0xFF757682)),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF757682)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear_rounded, color: Color(0xFF00113A)), onPressed: () { setState(() { _searchController.clear(); _searchQuery = ''; }); })
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF4FAFF),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF001F2A)),
                  onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedSchoolFilter,
                  icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF757682)),
                  decoration: InputDecoration(
                    labelText: 'Campus Filter',
                    labelStyle: const TextStyle(color: Color(0xFF757682)),
                    prefixIcon: const Icon(Icons.account_balance_rounded, color: Color(0xFF757682)),
                    filled: true,
                    fillColor: const Color(0xFFF4FAFF),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  items: _availableSchools.map((String schoolCode) {
                    String displayName = schoolCode == 'all' ? 'All Campuses' : '${_schoolCodeToName[schoolCode] ?? 'Unknown'}';
                    return DropdownMenuItem<String>(
                      value: schoolCode,
                      child: Text(displayName, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF001F2A))),
                    );
                  }).toList(),
                  onChanged: (String? newValue) => setState(() => _selectedSchoolFilter = newValue ?? 'all'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
           return const Center(child: CircularProgressIndicator(color: Color(0xFF00113A)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
           return const Center(child: Text('No network mapping found', style: TextStyle(color: Color(0xFF757682), fontWeight: FontWeight.bold)));
        }

        var users = snapshot.data!.docs;
        users = users.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['role']?.toString() ?? '') == 'admin';
        }).toList();

        if (_searchQuery.isNotEmpty) {
          users = users.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final username = data['username']?.toString().toLowerCase() ?? '';
            final fullName = data['full_name']?.toString().toLowerCase() ?? '';
            return username.contains(_searchQuery) || fullName.contains(_searchQuery);
          }).toList();
        }

        if (_selectedSchoolFilter != 'all') {
          users = users.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return (data['school_code']?.toString() ?? '') == _selectedSchoolFilter;
          }).toList();
        }

        if (users.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person_off_rounded, size: 64, color: Color(0xFFC5C6D2)),
                const SizedBox(height: 16),
                const Text('No admins match active filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF001F2A))),
                const SizedBox(height: 8),
                TextButton(
                   onPressed: () {
                     setState(() {
                       _searchController.clear();
                       _searchQuery = '';
                       _selectedSchoolFilter = 'all';
                     });
                   },
                   child: const Text('Clear Filters', style: TextStyle(color: Color(0xFF006D36), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          itemCount: users.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final user = users[index];
            final userData = user.data() as Map<String, dynamic>;
            final userId = user.id;
            
            final username = userData['username'] ?? 'No ID';
            final fullName = userData['full_name'] ?? 'Unknown Admin';
            final schoolCode = userData['school_code'] ?? 'N/A';
            final schoolName = userData['school_name'] ?? _schoolCodeToName[schoolCode] ?? 'Unknown Campus';
            final status = userData['status'] ?? 'inactive';
            final isActive = status == 'active';
            
            return Container(
               decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                     BoxShadow(color: const Color(0xFF001F2A).withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
                  ],
               ),
               clipBehavior: Clip.antiAlias,
               child: IntrinsicHeight(
                  child: Row(
                     crossAxisAlignment: CrossAxisAlignment.stretch,
                     children: [
                        // Status Ribbon
                        Container(
                           width: 8,
                           color: isActive ? const Color(0xFF006D36) : const Color(0xFFBA1A1A),
                        ),
                        // Card Content
                        Expanded(
                           child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                 children: [
                                    Row(
                                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                          Expanded(
                                             child: Row(
                                                children: [
                                                   CircleAvatar(
                                                      radius: 24,
                                                      backgroundColor: isActive ? const Color(0xFFE6F6FF) : const Color(0xFFF9FAFC),
                                                      child: Text(
                                                         fullName.isNotEmpty ? fullName[0].toUpperCase() : 'A',
                                                         style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isActive ? const Color(0xFF00113A) : const Color(0xFFC5C6D2)),
                                                      ),
                                                   ),
                                                   const SizedBox(width: 16),
                                                   Expanded(
                                                      child: Column(
                                                         crossAxisAlignment: CrossAxisAlignment.start,
                                                         children: [
                                                            Text(fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF001F2A)), overflow: TextOverflow.ellipsis, maxLines: 1),
                                                            const SizedBox(height: 2),
                                                            Text(username, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF757682)), overflow: TextOverflow.ellipsis, maxLines: 1),
                                                         ],
                                                      ),
                                                   ),
                                                ],
                                             ),
                                          ),
                                          Container(
                                             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                             decoration: BoxDecoration(
                                                color: isActive ? const Color(0xFF006D36).withOpacity(0.1) : const Color(0xFFBA1A1A).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(12),
                                             ),
                                             child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                   Icon(isActive ? Icons.verified_user_rounded : Icons.gpp_bad_rounded, size: 14, color: isActive ? const Color(0xFF006D36) : const Color(0xFFBA1A1A)),
                                                   const SizedBox(width: 6),
                                                   Text(isActive ? 'Active' : 'Inactive', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? const Color(0xFF006D36) : const Color(0xFFBA1A1A))),
                                                ],
                                             ),
                                          ),
                                       ],
                                    ),
                                    const SizedBox(height: 20),
                                    const Divider(color: Color(0xFFE6F6FF), height: 1),
                                    const SizedBox(height: 16),
                                    Row(
                                       children: [
                                          Icon(Icons.apartment_rounded, size: 16, color: const Color(0xFF00113A).withOpacity(0.5)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                             child: Text(
                                                '$schoolName ($schoolCode)',
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF00113A)),
                                                overflow: TextOverflow.ellipsis, maxLines: 1,
                                             ),
                                          ),
                                       ],
                                    ),
                                    const SizedBox(height: 16),
                                    // Action Buttons Row
                                    Row(
                                       mainAxisAlignment: MainAxisAlignment.end,
                                       children: [
                                          _buildActionIcon(Icons.edit_rounded, 'Edit Details', const Color(0xFF00113A), () => _editUser(userData, userId)),
                                          const SizedBox(width: 12),
                                          _buildActionIcon(Icons.lock_reset_rounded, 'Reset Password', const Color(0xFFD6602F), () => _resetUserPassword(userId, username, 'admin')),
                                          const SizedBox(width: 12),
                                          _buildActionIcon(Icons.delete_outline_rounded, 'Delete Admin', const Color(0xFFBA1A1A), () => _deleteUser(userId, username)),
                                       ],
                                    ),
                                 ],
                              ),
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

  Widget _buildActionIcon(IconData icon, String tooltip, Color color, VoidCallback onTap) {
     return Tooltip(
        message: tooltip,
        child: Material(
           color: Colors.transparent,
           child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              hoverColor: color.withOpacity(0.05),
              child: Container(
                 padding: const EdgeInsets.all(10),
                 decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE6F6FF), width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                 ),
                 child: Icon(icon, size: 20, color: color),
              ),
           ),
        ),
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

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
             BoxShadow(
               color: const Color(0xFF001F2A).withOpacity(0.1),
               blurRadius: 32,
               offset: const Offset(0, 16),
             ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             Row(
                children: [
                   Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                         color: const Color(0xFFE6F6FF),
                         shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFF00113A), size: 28),
                   ),
                   const SizedBox(width: 16),
                   const Expanded(
                      child: Text(
                         'Edit Admin Details',
                         style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF001F2A)),
                         overflow: TextOverflow.ellipsis,
                      ),
                   ),
                ],
             ),
             const SizedBox(height: 32),
             Flexible(
                child: SingleChildScrollView(
                   child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                         // Locked Username
                         _buildLockedField('Admin ID (Username)', _usernameController.text, Icons.badge_rounded),
                         const Padding(
                            padding: EdgeInsets.only(top: 8, bottom: 16, left: 4),
                            child: Text('Username cannot be modified (used for login)', style: TextStyle(fontSize: 12, color: Color(0xFF757682), fontStyle: FontStyle.italic)),
                         ),
                         // Locked School
                         _buildLockedField('School Assignment', '$currentSchoolName ($_selectedSchool)', Icons.account_balance_rounded),
                         const Padding(
                            padding: EdgeInsets.only(top: 8, bottom: 24, left: 4),
                            child: Text('School delegation is permanent for this sub-admin constraint', style: TextStyle(fontSize: 12, color: Color(0xFF757682), fontStyle: FontStyle.italic)),
                         ),
                         
                         const Divider(color: Color(0xFFE6F6FF), thickness: 1.5),
                         const SizedBox(height: 24),

                         DropdownButtonFormField<String>(
                           isExpanded: true,
                           value: _selectedStatus,
                           icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF757682)),
                           decoration: InputDecoration(
                             labelText: 'Account Status',
                             labelStyle: const TextStyle(color: Color(0xFF757682)),
                             prefixIcon: const Icon(Icons.security_rounded, color: Color(0xFF757682)),
                             filled: true,
                             fillColor: const Color(0xFFF4FAFF),
                             border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                             enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE6F6FF), width: 1.5)),
                             focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF006D36), width: 2)),
                           ),
                           items: ['active', 'inactive'].map((String status) {
                             return DropdownMenuItem<String>(
                               value: status,
                               child: Text(status[0].toUpperCase() + status.substring(1), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF001F2A)), overflow: TextOverflow.ellipsis, maxLines: 1),
                             );
                           }).toList(),
                           onChanged: (String? newValue) {
                             setState(() {
                               _selectedStatus = newValue!;
                             });
                           },
                         ),
                         const SizedBox(height: 16),
                         
                         _buildEditableField('Full Name', _fullNameController, Icons.person_rounded),
                         const SizedBox(height: 16),
                         _buildEditableField('Mobile Number', _mobileController, Icons.phone_android_rounded, keyboardType: TextInputType.phone),
                         const SizedBox(height: 16),
                         _buildEditableField('Gmail', _gmailController, Icons.email_rounded, keyboardType: TextInputType.emailAddress),
                         const SizedBox(height: 16),
                         _buildEditableField('Alternate Mobile', _alternateMobileController, Icons.phone_rounded, keyboardType: TextInputType.phone),
                         const SizedBox(height: 16),
                         _buildEditableField('School Telephone', _schoolTelephoneController, Icons.contact_phone_rounded, keyboardType: TextInputType.phone),
                         
                         if (_errorMessage != null) ...[
                           const SizedBox(height: 24),
                           Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: const Color(0xFFBA1A1A).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                 children: [
                                    const Icon(Icons.error_outline_rounded, color: Color(0xFFBA1A1A)),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFBA1A1A), fontWeight: FontWeight.bold))),
                                 ],
                              ),
                           ),
                         ],
                      ],
                   ),
                ),
             ),
             const SizedBox(height: 32),
             Row(
                children: [
                   Expanded(
                      child: SizedBox(
                         height: 56,
                         child: OutlinedButton(
                            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                               foregroundColor: const Color(0xFF00113A),
                               side: const BorderSide(color: Color(0xFFE6F6FF), width: 2),
                               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                         ),
                      ),
                   ),
                   const SizedBox(width: 16),
                   Expanded(
                      child: Container(
                         height: 56,
                         decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF00113A), Color(0xFF399E9D)]),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                               BoxShadow(color: const Color(0xFF00113A).withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4)),
                            ],
                         ),
                         child: ElevatedButton(
                            onPressed: _isLoading ? null : _updateUser,
                            style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.transparent,
                               shadowColor: Colors.transparent,
                               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                         ),
                      ),
                   ),
                ],
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedField(String label, String value, IconData icon) {
     return TextFormField(
        initialValue: value,
        decoration: InputDecoration(
           labelText: label,
           labelStyle: const TextStyle(color: Color(0xFF757682)),
           prefixIcon: Icon(icon, color: const Color(0xFF757682)),
           suffixIcon: const Icon(Icons.lock_rounded, color: Color(0xFFC5C6D2), size: 18),
           filled: true,
           fillColor: const Color(0xFFF9FAFC),
           border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
           enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
           focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
        readOnly: true,
        enabled: false,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF757682)),
     );
  }

  Widget _buildEditableField(String label, TextEditingController controller, IconData icon, {TextInputType? keyboardType}) {
     return TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF001F2A)),
        decoration: InputDecoration(
           labelText: label,
           labelStyle: const TextStyle(color: Color(0xFF757682)),
           prefixIcon: Icon(icon, color: const Color(0xFF757682)),
           filled: true,
           fillColor: const Color(0xFFF4FAFF),
           border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
           enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE6F6FF), width: 1.5)),
           focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF006D36), width: 2)),
           contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
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
