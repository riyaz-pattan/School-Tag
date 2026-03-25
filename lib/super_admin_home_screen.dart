// super_admin_home_screen.dart
import 'package:flutter/material.dart';
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
  Future<void> _initializeCache() async {
    final prefs = await SharedPreferences.getInstance();
    _totalSchools = prefs.getInt('super_admin_schools') ?? 0;
    _activeSchools = prefs.getInt('super_admin_active_schools') ?? 0;
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
      appBar: AppBar(
        title: Text(_isMobile ? 'Dashboard' : 'Super Admin Dashboard'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 0,
        actions: [
          if (!_isMobile)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.blue),
              onPressed: _loadDashboardData,
              tooltip: 'Refresh',
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      drawer: _isMobile ? _buildMobileDrawer() : null,
      body: RefreshIndicator(onRefresh: _onRefresh, child: _getCurrentScreen()),
      bottomNavigationBar: _isMobile
          ? BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              selectedItemColor: Colors.blue[700],
              unselectedItemColor: Colors.grey[600],
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.info),
                  label: 'System Info',
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[800]!, Colors.blue[600]!],
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('Super Admin', style: TextStyle(color: Colors.blue[100])),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard, color: Colors.blue),
            title: const Text('Dashboard'),
            onTap: () {
              setState(() => _currentIndex = 0);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.school, color: Colors.orange),
            title: const Text('School Management'),
            onTap: () {
              Navigator.pop(context);
              _navigateToSchoolManagement();
            },
          ),
          ListTile(
            leading: const Icon(Icons.info, color: Colors.green),
            title: const Text('System Info'),
            onTap: () {
              setState(() => _currentIndex = 1);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_add, color: Colors.teal),
            title: const Text('Add Users'),
            onTap: _navigateToAddUsers,
          ),
          ListTile(
            leading: const Icon(Icons.people, color: Colors.purple),
            title: const Text('Manage Users'),
            onTap: _navigateToUserManagement,
          ),
          // NEW: Users Count in drawer
          ListTile(
            leading: const Icon(Icons.analytics, color: Colors.indigo),
            title: const Text('Users Count'),
            onTap: _navigateToUsersCount,
          ),
          ListTile(
            leading: const Icon(Icons.lock, color: Colors.grey),
            title: const Text('Change Password'),
            onTap: _showChangePasswordDialog,
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout'),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          _buildDesktopSidebar(),
          // Main Content
          Expanded(
            child: Column(
              children: [
                _buildDesktopTopBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _onRefresh,
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
      width: 260,
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      _superAdminName.isNotEmpty
                          ? _superAdminName[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 22, 105, 200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _superAdminName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromARGB(255, 21, 100, 191),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Text(
                    'Super Administrator',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildSidebarItem(Icons.dashboard, 'Dashboard', 0),
                  _buildSidebarItem(Icons.school, 'School Management', 1),
                  _buildSidebarItem(Icons.info, 'System Information', 2),
                  const SizedBox(height: 16),
                  _buildSidebarActionItem(
                    Icons.person_add,
                    'Add Users',
                    _navigateToAddUsers,
                  ),
                  _buildSidebarActionItem(
                    Icons.people,
                    'Manage Users',
                    _navigateToUserManagement,
                  ),
                  // NEW: Users Count in sidebar
                  _buildSidebarActionItem(
                    Icons.analytics,
                    'Users Count',
                    _navigateToUsersCount,
                  ),
                  _buildSidebarActionItem(
                    Icons.lock,
                    'Change Password',
                    _showChangePasswordDialog,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.blue[700] : Colors.grey),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.blue[700] : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      selected: false,
      onTap: () => setState(() => _currentIndex = index),
    );
  }

  Widget _buildSidebarActionItem(
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey),
      title: Text(
        title,
        style: const TextStyle(color: Color.fromARGB(255, 96, 96, 96)),
      ),
      onTap: onTap,
    );
  }

  Widget _buildDesktopTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: Colors.white,
      child: Row(
        children: [
          if (_currentIndex != 0)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.blue),
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
              color: Color.fromARGB(255, 21, 103, 195),
            ),
          ),
          const Spacer(),
          _buildSearchBar(),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _loadDashboardData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      width: _isDesktop ? 300 : 200,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(30),
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search...',
          hintStyle: TextStyle(color: Colors.grey[600]),
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
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
        color: const Color(0xFFF7F9FC),
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (!_isMobile) SliverToBoxAdapter(child: _buildWelcomeBanner()),
              if (_isMobile) _buildModernHeader(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _isDesktop ? 32 : 16,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isMobile) _buildUserInfoCard(),
                      if (_isMobile) const SizedBox(height: 16),
                      _buildStatisticsRow(),
                      const SizedBox(height: 32),
                      _buildModernWorkspaceSection(),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.only(
          top: 60,
          left: 24,
          right: 24,
          bottom: 32,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo[800]!, Colors.deepPurple[500]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(32),
            bottomRight: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.indigo.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, $_superAdminName 👋',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.admin_panel_settings,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Super Administrator',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: const Icon(
                      Icons.shield,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Schools',
                _totalSchools.toString(),
                Icons.account_balance,
                Colors.indigo,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Active Schools',
                _activeSchools.toString(),
                Icons.check_circle_outline,
                Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color[700], size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Super Admin Workspace',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Icon(Icons.more_horiz, color: Colors.grey[400]),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
            border: Border.all(color: Colors.grey[100]!),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = _isMobile ? 3 : 6;
              if (constraints.maxWidth < 340) {
                 crossAxisCount = 3; 
              }
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 32,
                crossAxisSpacing: 16,
                childAspectRatio: 0.8,
                children: [
                  _buildFlatAppIcon(
                    'Schools',
                    Icons.account_balance,
                    Colors.indigo,
                    _navigateToSchoolManagement,
                  ),
                  _buildFlatAppIcon(
                    'Users Count',
                    Icons.people_alt,
                    Colors.teal,
                    _navigateToUsersCount,
                  ),
                  _buildFlatAppIcon(
                    'System',
                    Icons.analytics,
                    Colors.purple,
                    _showSystemOverview,
                  ),
                  _buildFlatAppIcon(
                    'Add Users',
                    Icons.person_add,
                    Colors.orange,
                    _navigateToAddUsers,
                  ),
                  _buildFlatAppIcon(
                    'Manage Users',
                    Icons.people,
                    Colors.green,
                    _navigateToUserManagement,
                  ),
                ],
              );
            }
          ),
        ),
      ],
    );
  }

  Widget _buildFlatAppIcon(
    String label,
    IconData icon,
    MaterialColor colorSwatch,
    VoidCallback onTap,
  ) {
    Color primaryColor = colorSwatch[600] ?? colorSwatch;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                color: colorSwatch[50] ?? primaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(
                child: Icon(
                  icon, 
                  color: primaryColor, 
                  size: 30,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo[800]!, Colors.indigo[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
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
                  'Welcome back, $_superAdminName!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage the entire system efficiently',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                if (_lastDataFetchTime != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.update,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Last updated: ${_formatDateTime(_lastDataFetchTime!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.admin_panel_settings,
            size: 80,
            color: Colors.white.withOpacity(0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.indigo[50],
                  child: Icon(Icons.shield, size: 28, color: Colors.indigo[700]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _superAdminName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo[800],
                        ),
                      ),
                      const Text(
                        'Full System Access',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text('Role:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  Text('Super Administrator', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
            if (_lastDataFetchTime != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.update, size: 16, color: Colors.orange[800]),
                    const SizedBox(width: 8),
                    Text(
                      'Last updated: ${_formatDateTime(_lastDataFetchTime!)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[800],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // REMOVED: _buildStatsSection() method entirely

  Widget _buildActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color.fromARGB(255, 94, 94, 94),
          ),
        ),
        const SizedBox(height: 16),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _getActionGridCrossAxisCount(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: _getActionGridChildAspectRatio(),
          ),
          children: [
            // NEW: System Overview action card
            _buildAnimatedActionCard(
              'System Overview',
              'View system statistics',
              Icons.analytics,
              Colors.purple,
              _showSystemOverview,
            ),
            _buildAnimatedActionCard(
              'Users Count',
              'View user counts by school',
              Icons.people_alt,
              Colors.indigo,
              _navigateToUsersCount,
            ),
            _buildAnimatedActionCard(
              'Manage Schools',
              'View and edit schools',
              Icons.list_alt,
              Colors.green,
              _navigateToSchoolManagement,
            ),
            _buildAnimatedActionCard(
              'Add Users',
              'Add single or bulk users',
              Icons.person_add,
              Colors.orange,
              _navigateToAddUsers,
            ),
            _buildAnimatedActionCard(
              'Manage Users',
              'View and manage all users',
              Icons.people,
              Colors.teal,
              _navigateToUserManagement,
            ),
            _buildAnimatedActionCard(
              'Change Password',
              'Update security',
              Icons.lock,
              Colors.red,
              _showChangePasswordDialog,
            ),
          ],
        ),
      ],
    );
  }

  // NEW: Show System Overview Dialog
  void _showSystemOverview() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.purple),
            SizedBox(width: 8),
            Text('System Overview'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSystemOverviewCard(
                'Total Schools',
                _totalSchools.toString(),
                Icons.school,
                Colors.green,
              ),
              const SizedBox(height: 12),
              _buildSystemOverviewCard(
                'Active Schools',
                _activeSchools.toString(),
                Icons.check_circle,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildSystemOverviewCard(
                'Last Updated',
                _lastDataFetchTime != null
                    ? _formatDateTime(_lastDataFetchTime!)
                    : 'Never',
                Icons.update,
                Colors.orange,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemOverviewCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedActionCard(
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
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.12),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: color.withOpacity(0.05)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 28, color: color),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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
        horizontal: _isDesktop ? 32 : 16,
        vertical: _isDesktop ? 24 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System Information',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 22, 102, 195),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: EdgeInsets.all(_isDesktop ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Super Admin Name', _superAdminName),
                  _buildInfoRow('User ID', widget.userId),
                  _buildInfoRow('Role', 'Super Administrator'),
                  _buildInfoRow('Total Schools', _totalSchools.toString()),
                  _buildInfoRow('Active Schools', _activeSchools.toString()),
                  if (_lastDataFetchTime != null) ...[
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      'Data Last Updated',
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _isDesktop ? 150 : 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color.fromARGB(255, 73, 73, 73)),
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
      appBar: AppBar(
        title: const Text('School Management'),
        backgroundColor: Colors.blue[700],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Add School Form Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add New School',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // School Name Field
                      TextField(
                        controller: _schoolNameController,
                        decoration: const InputDecoration(
                          labelText: 'School Name',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // School Code Field
                      TextField(
                        controller: _schoolCodeController,
                        decoration: const InputDecoration(
                          labelText: 'School Code (6 digits)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          counterText: "",
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                      ),
                      const SizedBox(height: 12),

                      // School Address Field
                      TextField(
                        controller: _schoolAddressController,
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

                      // Image Preview
                      if (_selectedImageBytes != null) ...[
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: MemoryImage(_selectedImageBytes!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Select Photo Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _pickImage(false),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Select School Photo (Max 1MB)'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Add School Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isUploading ? null : _addSchool,
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add),
                          label: Text(
                            _isUploading ? 'Uploading...' : 'Add School',
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // School List Section
              const Text(
                'School List',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // School List - Now scrollable as part of the main scroll view
              StreamBuilder(
                stream: FirebaseFirestore.instance
                    .collection('schools')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: const Center(
                        child: Text(
                          'No schools found',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  final schools = snapshot.data!.docs;
                  return Column(
                    children: schools
                        .map((school) => _buildSchoolCard(school))
                        .toList(),
                  );
                },
              ),

              // Error Message (only show error messages in the UI if they exist, success messages are now snackbars)
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                _buildMessageSection(),
              ],
              const SizedBox(
                height: 20,
              ), // Extra padding at bottom for better scrolling
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
