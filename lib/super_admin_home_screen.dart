// super_admin_home_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'school_code_screen.dart';
import 'user_management_screen.dart';
import 'add_users_screen.dart';
import 'users_count_screen.dart'; // NEW IMPORT
import 'demo_bookings_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:typed_data';

class SuperAdminHomeScreen extends StatefulWidget {
  final String userId;

  const SuperAdminHomeScreen({super.key, required this.userId});

  @override
  State<SuperAdminHomeScreen> createState() => _SuperAdminHomeScreenState();
}

class _SuperAdminHomeScreenState extends State<SuperAdminHomeScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  int _totalSchools = 0;
  int _activeSchools = 0;
  bool _isLoading = true;
  bool _refreshing = false;
  String _superAdminName = '';

  // Cache variables
  static const Duration CACHE_DURATION = Duration(minutes: 10);
  DateTime? _lastDataFetchTime;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  late AnimationController _fadeController;
  late Animation<double> _fadeInAnimation;

  // Password change controllers
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();
    _initializeCache();
    _loadDashboardData();
    _loadSuperAdminData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _currentPasswordController.dispose();
    super.dispose();
  }

  // Cache methods
  int _getSafeInt(SharedPreferences prefs, String key) {
    final val = prefs.get(key);
    if (val is int) return val;
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  Future<void> _initializeCache() async {
    final prefs = await SharedPreferences.getInstance();
    _totalSchools = _getSafeInt(prefs, 'super_admin_schools');
    _activeSchools = _getSafeInt(prefs, 'super_admin_active_schools');
    _superAdminName = prefs.getString('super_admin_name') ?? '';
    final lastFetch = prefs.getString('super_admin_last_fetch');
    if (lastFetch != null) {
      _lastDataFetchTime = DateTime.parse(lastFetch);
    }
  }

  Future<void> _saveToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('super_admin_schools', _totalSchools);
    await prefs.setInt('super_admin_active_schools', _activeSchools);
    await prefs.setString('super_admin_name', _superAdminName);
    await prefs.setString(
      'super_admin_last_fetch',
      DateTime.now().toIso8601String(),
    );
  }

  bool get _shouldFetchData {
    if (_lastDataFetchTime == null) return true;
    return DateTime.now().difference(_lastDataFetchTime!) > CACHE_DURATION;
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      if (_shouldFetchData) {
        await _loadSchoolCounts();
        await _saveToCache();
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      print('Error loading dashboard data: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _loadSuperAdminData() async {
    if (_superAdminName.isNotEmpty) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        setState(() {
          _superAdminName =
              userData['full_name'] ?? userData['username'] ?? 'Super Admin';
        });
        await _saveToCache();
      }
    } catch (e) {
      print('Error loading super admin data: $e');
    }
  }

  Future<void> _loadSchoolCounts() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .get();

      final activeSchools = snapshot.docs
          .where((doc) => doc['status'] == 'active')
          .length;

      setState(() {
        _totalSchools = snapshot.docs.length;
        _activeSchools = activeSchools;
      });
    } catch (e) {
      print('Error loading school counts: $e');
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _refreshing = true;
    });
    _lastDataFetchTime = null;
    await _loadDashboardData();
  }

  // Navigation methods
  void _navigateToUserManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserManagementScreen(userId: widget.userId),
      ),
    );
  }

  void _navigateToSchoolManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SchoolManagementScreen(userId: widget.userId),
      ),
    );
  }

  void _navigateToAddUsers() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddUsersScreen(userId: widget.userId),
      ),
    );
  }

  // NEW: Navigate to Users Count Screen
  void _navigateToUsersCount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UsersCountScreen(userId: widget.userId),
      ),
    );
  }

  // Navigate to Demo Bookings Screen
  void _navigateToDemoBookings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DemoBookingsScreen(userId: widget.userId),
      ),
    );
  }

  // Logout method
  Future<void> _logout() async {
    bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmLogout != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _clearSharedPreferences();
      await FirebaseAuth.instance.signOut();

      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SchoolCodeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error during logout: $e')));
    }
  }

  Future<void> _clearSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('school_code');
      await prefs.remove('school_name');
      await prefs.remove('is_super_admin_mode');
      await prefs.remove('user_role');
      await prefs.remove('user_id');
      await prefs.remove('super_admin_schools');
      await prefs.remove('super_admin_active_schools');
      await prefs.remove('super_admin_name');
      await prefs.remove('super_admin_last_fetch');
    } catch (e) {
      print('Error clearing shared preferences: $e');
    }
  }

  // Password change dialog (same as admin dashboard)
  void _showChangePasswordDialog() {
    bool _isLoading = false;
    String? _errorMessage;
    bool _dialogOpen = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void safeSetDialogState(VoidCallback fn) {
            if (_dialogOpen && mounted) {
              setDialogState(fn);
            }
          }

          return WillPopScope(
            onWillPop: () async => !_isLoading,
            child: AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.lock_reset, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Change Password'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Update your password to keep your account secure',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _currentPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                        hintText: 'Enter your current password',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _newPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        hintText: 'At least 6 characters',
                        prefixIcon: Icon(Icons.lock_reset),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: Icon(Icons.verified_user),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enabled: !_isLoading,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          _dialogOpen = false;
                          _currentPasswordController.clear();
                          _newPasswordController.clear();
                          _confirmPasswordController.clear();
                          Navigator.pop(context);
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          final newPassword = _newPasswordController.text
                              .trim();
                          final confirmPassword = _confirmPasswordController
                              .text
                              .trim();
                          final currentPassword = _currentPasswordController
                              .text
                              .trim();

                          if (currentPassword.isEmpty) {
                            safeSetDialogState(
                              () => _errorMessage =
                                  'Please enter your current password',
                            );
                            return;
                          }

                          if (newPassword.isEmpty) {
                            safeSetDialogState(
                              () =>
                                  _errorMessage = 'Please enter a new password',
                            );
                            return;
                          }

                          if (newPassword.length < 6) {
                            safeSetDialogState(
                              () => _errorMessage =
                                  'Password must be at least 6 characters',
                            );
                            return;
                          }

                          if (newPassword != confirmPassword) {
                            safeSetDialogState(
                              () => _errorMessage = 'Passwords do not match',
                            );
                            return;
                          }

                          safeSetDialogState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });

                          try {
                            final user = FirebaseAuth.instance.currentUser;
                            final email = user?.email;

                            if (email == null || user == null) {
                              throw Exception('User email not found');
                            }

                            try {
                              final credential = EmailAuthProvider.credential(
                                email: email,
                                password: currentPassword,
                              );
                              await user.reauthenticateWithCredential(
                                credential,
                              );
                            } catch (e) {
                              throw Exception('Current password is incorrect');
                            }

                            await user.updatePassword(newPassword);
                            await user.getIdToken(true);

                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(widget.userId)
                                .update({
                                  'password': newPassword,
                                  'is_first_login': false,
                                });

                            _dialogOpen = false;
                            if (mounted) Navigator.pop(context);

                            _currentPasswordController.clear();
                            _newPasswordController.clear();
                            _confirmPasswordController.clear();

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Password changed successfully!',
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          } catch (e) {
                            final message = e.toString().replaceAll(
                              'Exception: ',
                              '',
                            );
                            if (_dialogOpen && mounted) {
                              safeSetDialogState(() {
                                _isLoading = false;
                                _errorMessage =
                                    'Error changing password: $message';
                              });
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Error changing password: $message',
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Change Password',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Responsive layout methods
  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  int _getStatGridCrossAxisCount() => _isMobile ? 2 : 3;
  double _getStatGridChildAspectRatio() => _isMobile ? 1.1 : 1.0;
  int _getActionGridCrossAxisCount() => _isMobile ? 2 : (_isTablet ? 3 : 4);
  double _getActionGridChildAspectRatio() =>
      _isMobile ? 1.0 : (_isTablet ? 1.2 : 1.4);

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(body: _buildDesktopLayout());
    } else {
      return _buildMobileTabletLayout();
    }
  }

    Widget _buildMobileTabletLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFF),
      appBar: _isMobile
          ? null // Use custom modern header instead of standard Appbar
          : AppBar(
              title: const Text('Super Admin Dashboard', style: TextStyle(color: Color(0xFF001F2A), fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFFFFFFFF),
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF00113A)),
                  onPressed: _loadDashboardData,
                  tooltip: 'Refresh',
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  onPressed: _logout,
                  tooltip: 'Logout',
                ),
              ],
            ),
      drawer: _isMobile ? _buildMobileDrawer() : null,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: const Color(0xFF00113A),
        backgroundColor: Colors.white,
        child: _getCurrentScreen(),
      ),
      bottomNavigationBar: _isMobile ? _buildModernBottomNav() : null,
    );
  }

  Widget _buildModernBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF001F2A).withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomNavItem(Icons.dashboard_rounded, 'Dashboard', 0),
              _buildBottomNavItem(Icons.school_rounded, 'Schools', 1),
              _buildBottomNavItem(Icons.info_outline_rounded, 'System Info', 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE6F6FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF00113A) : const Color(0xFF757682),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00113A) : const Color(0xFF757682),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFFF4FAFF),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00113A), Color(0xFF399E9D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _superAdminName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Super Admin', style: TextStyle(color: Color(0xFFB3C5FF))),
              ],
            ),
          ),
          _buildDrawerItem(Icons.dashboard_rounded, 'Dashboard', () {
            setState(() => _currentIndex = 0);
            Navigator.pop(context);
          }, isSelected: _currentIndex == 0),
          _buildDrawerItem(Icons.school_rounded, 'School Management', () {
            Navigator.pop(context);
            _navigateToSchoolManagement();
          }),
          _buildDrawerItem(Icons.info_outline_rounded, 'System Info', () {
            setState(() => _currentIndex = 2);
            Navigator.pop(context);
          }, isSelected: _currentIndex == 2),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(color: Color(0xFFC5C6D2)),
          ),
          _buildDrawerItem(Icons.person_add_rounded, 'Add Users', _navigateToAddUsers),
          _buildDrawerItem(Icons.people_alt_rounded, 'Manage Users', _navigateToUserManagement),
          _buildDrawerItem(Icons.analytics_rounded, 'Users Count', _navigateToUsersCount),
          _buildDrawerItem(Icons.event_available_rounded, 'Demo Bookings', _navigateToDemoBookings),
          _buildDrawerItem(Icons.lock_reset_rounded, 'Change Password', _showChangePasswordDialog),
          _buildDrawerItem(Icons.logout_rounded, 'Logout', _logout, isDestructive: true),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {bool isSelected = false, bool isDestructive = false}) {
    final color = isDestructive ? Colors.redAccent : (isSelected ? const Color(0xFF00113A) : const Color(0xFF001F2A));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE6F6FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFF),
      body: Row(
        children: [
          _buildDesktopSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildDesktopTopBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: const Color(0xFF00113A),
                    child: _getCurrentScreen(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF001F2A).withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00113A), Color(0xFF399E9D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00113A).withOpacity(0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _superAdminName.isNotEmpty ? _superAdminName[0].toUpperCase() : 'S',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _superAdminName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Color(0xFF001F2A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Super Administrator',
                    style: TextStyle(color: Color(0xFF757682), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(color: Color(0xFFE6F6FF)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                children: [
                  _buildSidebarItem(Icons.dashboard_rounded, 'Dashboard', 0),
                  _buildSidebarItem(Icons.school_rounded, 'School Management', 1),
                  _buildSidebarItem(Icons.info_outline_rounded, 'System Info', 2),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.only(left: 12, bottom: 8),
                    child: Text(
                      'QUICK ACTIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Color(0xFF757682),
                      ),
                    ),
                  ),
                  _buildSidebarActionItem(Icons.person_add_rounded, 'Add Users', _navigateToAddUsers),
                  _buildSidebarActionItem(Icons.people_alt_rounded, 'Manage Users', _navigateToUserManagement),
                  _buildSidebarActionItem(Icons.analytics_rounded, 'Users Count', _navigateToUsersCount),
                  _buildSidebarActionItem(Icons.event_available_rounded, 'Demo Bookings', _navigateToDemoBookings),
                  _buildSidebarActionItem(Icons.lock_reset_rounded, 'Change Password', _showChangePasswordDialog),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                label: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: Colors.red[50], // Subtle red background
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, int index) {
    final isSelected = _currentIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF00113A) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? Colors.white : const Color(0xFF757682)),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF001F2A),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        selected: isSelected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () {
          if (index == 1) {
             _navigateToSchoolManagement();
          } else {
             setState(() => _currentIndex = index);
          }
        },
      ),
    );
  }

  Widget _buildSidebarActionItem(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF757682)),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF444650),
            fontWeight: FontWeight.w500,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        hoverColor: const Color(0xFFE6F6FF),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDesktopTopBar() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE6F6FF), width: 1)),
      ),
      child: Row(
        children: [
          if (_currentIndex != 0)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF00113A)),
              onPressed: () {
                setState(() {
                  _currentIndex = 0;
                });
              },
              tooltip: 'Back to Dashboard',
            ),
          const SizedBox(width: 8),
          Text(
            _getCurrentTitle(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00113A),
            ),
          ),
          const Spacer(),
          _buildSearchBar(),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00113A)),
            onPressed: _loadDashboardData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      width: _isDesktop ? 320 : 220,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FAFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6F6FF)),
      ),
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Search...',
          hintStyle: TextStyle(color: Color(0xFF757682)),
          border:InputBorder.none,
          prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF757682)),
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (value) {
          // Optional: integrate search later
        },
      ),
    );
  }

  String _getCurrentTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Dashboard Overview';
      case 1:
        return 'School Management';
      case 2:
        return 'System Information';
      default:
        return 'Dashboard';
    }
  }

  Widget _getCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return _buildDashboard();
      case 1:
        return _buildSchoolManagement();
      case 2:
        return _buildSystemInfo();
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    return FadeTransition(
      opacity: _fadeInAnimation,
      child: Container(
        color: const Color(0xFFF4FAFF),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_isMobile) _buildModernMobileHeader(),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _isDesktop ? 40 : 20,
                  vertical: _isDesktop ? 32 : 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isMobile) _buildDesktopWelcomeBanner(),
                    const SizedBox(height: 32),
                    _buildStatisticsRow(),
                    const SizedBox(height: 48),
                    _buildModernWorkspaceSection(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernMobileHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00113A), Color(0xFF399E9D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00113A).withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_getGreeting()},',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _superAdminName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Executive Console',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2),
                  border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                ),
                child: const Icon(Icons.menu_rounded, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopWelcomeBanner() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00113A), Color(0xFF399E9D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00113A).withOpacity(0.15),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_getGreeting()}, $_superAdminName',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Command center for institutional legacy and management.',
                  style: TextStyle(fontSize: 16, color: Color(0xFFE6F6FF)),
                ),
                if (_lastDataFetchTime != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.update_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Synced: ${_formatDateTime(_lastDataFetchTime!)}',
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.account_balance_rounded,
            size: 120,
            color: Colors.white.withOpacity(0.15),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF001F2A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildPremiumStatCard(
                'Total Schools',
                _totalSchools.toString(),
                Icons.account_balance_rounded,
                const Color(0xFF00113A),
                const Color(0xFFE6F6FF),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildPremiumStatCard(
                'Active Schools',
                _activeSchools.toString(),
                Icons.verified_rounded,
                const Color(0xFF006D36),
                const Color(0xFFE8F8EE),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPremiumStatCard(
    String title,
    String value,
    IconData icon,
    Color primaryColor,
    Color surfaceColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: primaryColor, size: 28),
          ),
          const SizedBox(height: 24),
          Text(
            value,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: primaryColor,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF757682),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernWorkspaceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Executive Toolkit',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF001F2A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _isMobile ? 2 : (_isTablet ? 3 : 4),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: _isMobile ? 1.0 : 1.2,
          ),
          children: [
            _buildActionCard(
               'School Management',
               'Manage institutional data',
               Icons.domain_add_rounded,
               const Color(0xFF00113A),
               _navigateToSchoolManagement,
            ),
            _buildActionCard(
               'User Analytics',
               'View demographic counts',
               Icons.analytics_rounded,
               const Color(0xFF006D36),
               _navigateToUsersCount,
            ),
            _buildActionCard(
               'Add Users',
               'Provision new accounts',
               Icons.person_add_rounded,
               const Color(0xFF399E9D),
               _navigateToAddUsers,
            ),
            _buildActionCard(
               'Manage Users',
               'Access control & roles',
               Icons.manage_accounts_rounded,
               const Color(0xFF607D8B),
               _navigateToUserManagement,
            ),
            _buildActionCard(
               'Demo Bookings',
               'Review scheduled demos',
               Icons.event_available_rounded,
               const Color(0xFF2A4386),
               _navigateToDemoBookings,
            ),
            _buildActionCard(
               'System Overview',
               'Check platform health',
               Icons.medical_information_rounded,
               const Color(0xFF50C878),
               _showSystemOverview,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF001F2A).withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001F2A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF757682)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolManagement() {
    return SchoolManagementScreen(userId: widget.userId);
  }

  Widget _buildSystemInfo() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 40 : 20,
        vertical: _isDesktop ? 32 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System Information',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00113A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF001F2A).withOpacity(0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(_isDesktop ? 32 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPremiumInfoRow('Platform Name', 'Executive Scholar'),
                  _buildPremiumInfoRow('Super Admin Name', _superAdminName),
                  _buildPremiumInfoRow('User ID', widget.userId),
                  _buildPremiumInfoRow('Access Level', 'Executive / Super Administrator'),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(color: Color(0xFFE6F6FF)),
                  ),
                  _buildPremiumInfoRow('Total Enrolled Schools', _totalSchools.toString()),
                  _buildPremiumInfoRow('Active Schools', _activeSchools.toString()),
                  if (_lastDataFetchTime != null) ...[
                    const SizedBox(height: 8),
                    _buildPremiumInfoRow(
                      'Data Last Synced',
                      _formatDateTime(_lastDataFetchTime!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _isDesktop ? 200 : 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF757682),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF001F2A),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }


  void _showSystemOverview() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 400,
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
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F6FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.analytics_rounded, color: Color(0xFF00113A), size: 32),
              ),
              const SizedBox(height: 24),
              const Text(
                 'System Overview',
                 style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF001F2A)),
              ),
              const SizedBox(height: 32),
              _buildSystemOverviewCard(
                'Total Network Schools',
                _totalSchools.toString(),
                Icons.account_balance_rounded,
                const Color(0xFF00113A),
              ),
              const SizedBox(height: 16),
              _buildSystemOverviewCard(
                'Active Deployments',
                _activeSchools.toString(),
                Icons.check_circle_rounded,
                const Color(0xFF006D36),
              ),
              const SizedBox(height: 16),
              _buildSystemOverviewCard(
                'Last Data Sync',
                _lastDataFetchTime != null ? _formatDateTime(_lastDataFetchTime!) : 'Never',
                Icons.sync_rounded,
                const Color(0xFF399E9D),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                   onPressed: () => Navigator.pop(context),
                   style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF4FAFF),
                      foregroundColor: const Color(0xFF00113A),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                   ),
                   child: const Text('Close Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemOverviewCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FAFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF757682), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF001F2A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${_formatDate(date)} – ${_formatTime(date)}';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return '${hour == 0 ? 12 : hour}:$minute $period';
  }
}

class SchoolManagementScreen extends StatefulWidget {
  final String userId;

  const SchoolManagementScreen({super.key, required this.userId});

  @override
  State<SchoolManagementScreen> createState() => _SchoolManagementScreenState();
}

class _SchoolManagementScreenState extends State<SchoolManagementScreen> {
  final _schoolNameController = TextEditingController();
  final _schoolCodeController = TextEditingController();
  final _schoolAddressController = TextEditingController();
  final _editSchoolNameController = TextEditingController();
  final _editSchoolAddressController = TextEditingController();
  final _deletePasswordController =
      TextEditingController(); // NEW: Password controller for delete confirmation

  String? _errorMessage;
  String? _successMessage;
  bool _isUploading = false;

  // Image handling variables
  Uint8List? _selectedImageBytes;
  Uint8List? _editSelectedImageBytes;
  String? _selectedImageName;
  String? _editImageName;

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _schoolNameController.dispose();
    _schoolCodeController.dispose();
    _schoolAddressController.dispose();
    _editSchoolNameController.dispose();
    _editSchoolAddressController.dispose();
    _deletePasswordController.dispose(); // NEW: Dispose password controller
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isEdit) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        allowCompression: true,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        PlatformFile file = result.files.first;

        // Check file size (1MB limit)
        if (file.size > 1024 * 1024) {
          setState(() {
            _errorMessage =
                'Image size must be less than 1MB. Current size: ${(file.size / 1024 / 1024).toStringAsFixed(2)}MB';
            _successMessage = null;
          });
          return;
        }

        // Store file bytes and name
        setState(() {
          if (isEdit) {
            _editSelectedImageBytes = file.bytes;
            _editImageName = file.name;
          } else {
            _selectedImageBytes = file.bytes;
            _selectedImageName = file.name;
          }
          _errorMessage = null;
          _successMessage = 'Image selected successfully';
        });
      }
    } catch (e) {
      print('File picker error: $e');
      setState(() {
        _errorMessage = 'Failed to pick image: ${e.toString()}';
        _successMessage = null;
      });
    }
  }

  Future<String?> _uploadImage(
    Uint8List? imageBytes,
    String fileName,
    String schoolCode,
  ) async {
    if (imageBytes == null) return null;

    try {
      setState(() {
        _isUploading = true;
      });

      final String uniqueFileName =
          'school_${schoolCode}_${DateTime.now().millisecondsSinceEpoch}${path.extension(fileName)}';
      final Reference ref = _storage
          .ref()
          .child('school_photos')
          .child(uniqueFileName);

      final UploadTask uploadTask = ref.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _addSchool() async {
    if (_schoolNameController.text.isEmpty ||
        _schoolCodeController.text.length != 6) {
      setState(() {
        _errorMessage = 'Please enter a school name and 6-digit code';
        _successMessage = null;
      });
      return;
    }

    try {
      final schoolCode = _schoolCodeController.text;

      // Check if school code already exists
      final schoolSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolCode)
          .get();

      if (schoolSnapshot.exists) {
        setState(() {
          _errorMessage = 'School code $schoolCode already exists!';
          _successMessage = null;
        });
        return;
      }

      String? photoUrl;
      if (_selectedImageBytes != null && _selectedImageName != null) {
        photoUrl = await _uploadImage(
          _selectedImageBytes,
          _selectedImageName!,
          schoolCode,
        );
        if (photoUrl == null) {
          setState(() {
            _errorMessage = 'Failed to upload school photo';
            _successMessage = null;
          });
          return;
        }
      }

      final schoolData = {
        'name': _schoolNameController.text,
        'school_code': schoolCode,
        'address': _schoolAddressController.text.trim(),
        'status': 'active',
        'created_at': FieldValue.serverTimestamp(),
        // NEW: Initialize user count fields
        'admin_count': 0,
        'teacher_count': 0,
        'student_count': 0,
      };

      if (photoUrl != null) {
        schoolData['photo_url'] = photoUrl;
      }

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolCode)
          .set(schoolData);

      // Clear form
      _schoolNameController.clear();
      _schoolCodeController.clear();
      _schoolAddressController.clear();
      _selectedImageBytes = null;
      _selectedImageName = null;

      // NEW: Show floating snackbar success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('School added successfully with code: $schoolCode'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      setState(() {
        _successMessage = null; // Clear any previous success message from state
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error adding school: $e';
        _successMessage = null;
      });
    }
  }

  Future<void> _updateSchool(
    String schoolId,
    String newName,
    String newAddress,
    String newStatus,
  ) async {
    try {
      final updateData = {
        'name': newName,
        'address': newAddress,
        'status': newStatus,
      };

      // Upload new image if selected
      if (_editSelectedImageBytes != null && _editImageName != null) {
        final photoUrl = await _uploadImage(
          _editSelectedImageBytes,
          _editImageName!,
          schoolId,
        );
        if (photoUrl != null) {
          updateData['photo_url'] = photoUrl;
        }
      }

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .update(updateData);

      // NEW: Show floating snackbar success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('School updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      setState(() {
        _successMessage = null; // Clear any previous success message from state
        _errorMessage = null;
        _editSelectedImageBytes = null;
        _editImageName = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error updating school: $e';
        _successMessage = null;
      });
    }
  }

  void _showEditSchoolDialog(QueryDocumentSnapshot school) {
    final data = school.data() as Map<String, dynamic>;
    _editSchoolNameController.text = data['name'] ?? '';
    _editSchoolAddressController.text = data['address'] ?? '';
    String selectedStatus = data['status'] ?? 'active';
    String? currentPhotoUrl = data['photo_url'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Edit School',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _editSchoolNameController,
                    decoration: const InputDecoration(
                      labelText: 'School Name',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _editSchoolAddressController,
                    decoration: const InputDecoration(
                      labelText: 'School Address (Optional)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  // School Photo Section
                  const Text(
                    'School Photo (Optional)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // Current photo preview
                  if (currentPhotoUrl != null &&
                      currentPhotoUrl is String &&
                      currentPhotoUrl.isNotEmpty) ...[
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: NetworkImage(currentPhotoUrl),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Current Photo',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // New photo selection
                  if (_editSelectedImageBytes != null) ...[
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: MemoryImage(_editSelectedImageBytes!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'New Photo (Selected)',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                    const SizedBox(height: 8),
                  ],

                  ElevatedButton.icon(
                    onPressed: () => _pickImage(true),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Select School Photo (Max 1MB)'),
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                    ),
                    items: ['active', 'inactive'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setDialogState(() {
                        selectedStatus = newValue ?? 'active';
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            _editSelectedImageBytes = null;
                            _editImageName = null;
                            Navigator.pop(context);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isUploading
                              ? null
                              : () {
                                  _updateSchool(
                                    school.id,
                                    _editSchoolNameController.text,
                                    _editSchoolAddressController.text.trim(),
                                    selectedStatus,
                                  );
                                  Navigator.pop(context);
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // UPDATED: Delete school with password confirmation
  Future<void> _deleteSchool(String schoolId, String schoolName) async {
    // First, ask for confirmation
    bool confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete School'),
        content: Text(
          'Are you sure you want to delete "$schoolName"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmDelete != true) return;

    // Then, ask for super admin password
    final passwordResult = await _showPasswordConfirmationDialog();
    if (passwordResult != true) return;

    try {
      // Check if school has any users before deletion
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: schoolId)
          .limit(1)
          .get();

      if (usersSnapshot.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cannot delete "$schoolName" - it has existing users. Please delete all users first.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .delete();

      // NEW: Show floating snackbar success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('School "$schoolName" deleted successfully'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      setState(() {
        _successMessage = null; // Clear any previous success message from state
        _errorMessage = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting school: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // NEW: Password confirmation dialog for delete operation
  Future<bool?> _showPasswordConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool _isVerifying = false;
          String? _errorMessage;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.security, color: Colors.red),
                SizedBox(width: 8),
                Text('Confirm Deletion'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please enter your Super Admin password to confirm deletion:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _deletePasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Super Admin Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  enabled: !_isVerifying,
                  onChanged: (_) {
                    // Clear error message when user starts typing again
                    if (_errorMessage != null) {
                      setDialogState(() {
                        _errorMessage = null;
                      });
                    }
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: _isVerifying
                    ? null
                    : () {
                        _deletePasswordController.clear();
                        Navigator.pop(context, false);
                      },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _isVerifying
                    ? null
                    : () async {
                        final password = _deletePasswordController.text.trim();
                        if (password.isEmpty) {
                          setDialogState(() {
                            _errorMessage = 'Please enter your password';
                          });
                          return;
                        }

                        setDialogState(() {
                          _isVerifying = true;
                          _errorMessage = null;
                        });

                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            throw Exception('User not authenticated');
                          }

                          final credential = EmailAuthProvider.credential(
                            email: user.email!,
                            password: password,
                          );

                          await user.reauthenticateWithCredential(credential);

                          _deletePasswordController.clear();
                          Navigator.pop(context, true);
                        } catch (e) {
                          print('Password verification error: $e');
                          setDialogState(() {
                            _isVerifying = false;
                            _errorMessage =
                                'Incorrect password. Please try again.';
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: _isVerifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Confirm Delete',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFF),
      appBar: AppBar(
        title: const Text('School Deployments', style: TextStyle(color: Color(0xFF001F2A), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00113A)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                     BoxShadow(
                       color: const Color(0xFF001F2A).withOpacity(0.04),
                       blurRadius: 24,
                       offset: const Offset(0, 8),
                     ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F6FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.add_business_rounded, color: Color(0xFF00113A)),
                          ),
                          const SizedBox(width: 16),
                          const Text(
                            'Provision New School',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF001F2A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _schoolNameController,
                        decoration: InputDecoration(
                          labelText: 'Official School Name',
                          labelStyle: const TextStyle(color: Color(0xFF757682)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4FAFF),
                          prefixIcon: const Icon(Icons.school_rounded, color: Color(0xFF757682)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _schoolCodeController,
                        decoration: InputDecoration(
                          labelText: 'Unique 6-Digit Code',
                          labelStyle: const TextStyle(color: Color(0xFF757682)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4FAFF),
                          prefixIcon: const Icon(Icons.pin_rounded, color: Color(0xFF757682)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          counterText: "",
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _schoolAddressController,
                        decoration: InputDecoration(
                          labelText: 'Campus Address (Optional)',
                          labelStyle: const TextStyle(color: Color(0xFF757682)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4FAFF),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 24),
                            child: Icon(Icons.location_on_rounded, color: Color(0xFF757682)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Campus Identity',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF001F2A)),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedImageBytes != null) ...[
                        Container(
                          width: double.infinity,
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                              image: MemoryImage(_selectedImageBytes!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(false),
                          icon: const Icon(Icons.add_photo_alternate_rounded),
                          label: const Text('Upload Photo (Max 1MB)', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00113A),
                            side: const BorderSide(color: Color(0xFF00113A), width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
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
                            onPressed: _isUploading ? null : _addSchool,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isUploading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                  )
                                : const Row(
                                   mainAxisAlignment: MainAxisAlignment.center,
                                   children: [
                                      Icon(Icons.add_box_rounded, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('Provision System Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                   ]
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),
              Row(
                children: [
                  const Text(
                    'Active Deployments',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF001F2A)),
                  ),
                  const Spacer(),
                  Container(
                     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                     decoration: BoxDecoration(color: const Color(0xFFE6F6FF), borderRadius: BorderRadius.circular(12)),
                     child: const Text('Live', style: TextStyle(color: Color(0xFF00113A), fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              StreamBuilder(
                stream: FirebaseFirestore.instance.collection('schools').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator(color: Color(0xFF00113A))));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Center(
                        child: Column(
                           children: [
                              Icon(Icons.domain_disabled_rounded, size: 48, color: Color(0xFFC5C6D2)),
                              SizedBox(height: 16),
                              Text('No deployments found', style: TextStyle(fontSize: 16, color: Color(0xFF757682), fontWeight: FontWeight.bold)),
                           ],
                        )
                      ),
                    );
                  }
                  final schools = snapshot.data!.docs;
                  return Column(
                    children: schools.map((school) => _buildSchoolCard(school)).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolCard(QueryDocumentSnapshot school) {
    final data = school.data() as Map<String, dynamic>;
    final photoUrl = data['photo_url'];
    final address = data['address'];
    final schoolName = data['name'] ?? 'Unnamed School';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: photoUrl != null && photoUrl is String && photoUrl.isNotEmpty
            ? Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: NetworkImage(photoUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            : Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.school, color: Colors.blue[700], size: 30),
              ),
        title: Text(
          schoolName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Code: ${school.id} | Status: ${data['status'] ?? 'active'}',
              style: const TextStyle(fontSize: 14),
            ),
            if (address != null && address is String && address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  address.length > 50
                      ? '${address.substring(0, 50)}...'
                      : address,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            // NEW: Show user counts if available
            if (data['admin_count'] != null ||
                data['teacher_count'] != null ||
                data['student_count'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'Users: Admin: ${data['admin_count'] ?? 0}, Teacher: ${data['teacher_count'] ?? 0}, Student: ${data['student_count'] ?? 0}',
                  style: const TextStyle(fontSize: 11, color: Colors.blue),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.orange),
              onPressed: () => _showEditSchoolDialog(school),
              tooltip: 'Edit School',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteSchool(school.id, schoolName),
              tooltip: 'Delete School',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
