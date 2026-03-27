// admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'timetable_management_screen.dart';
import 'class_management_screen.dart';
import 'school_settings_screen.dart';
import 'notices_and_announcements_screen.dart';
import 'student_management_screen.dart';
import 'manage_subjects_screen.dart';
import 'manage_exams_screen.dart';
import 'all_grades_screen.dart';
import 'services/fcm_service.dart';
import 'admin_add_users_screen.dart';
import 'admin_manage_users_screen.dart';
import 'school_code_screen.dart';
import 'create_exam_schedule_screen.dart';
import 'package:flutter/services.dart';
import 'messages_screen.dart';
import 'widgets/dashboard_skeleton.dart';
import 'admin_fee_structure_screen.dart';
import 'dart:async';

class AdminDashboardScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  const AdminDashboardScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  int _totalStudents = 0;
  int _totalTeachers = 0;
  int _totalClasses = 0;
  int _todayAttendanceCount = 0;
  bool _isLoading = true;
  bool _refreshing = false;
  String _adminName = '';
  // Cache variables
  Map<String, dynamic> _cachedSchoolInfo = {};
  List<QueryDocumentSnapshot> _cachedUsers = [];
  DateTime? _lastDataFetchTime;
  DateTime? _lastUsersFetchTime;
  static const Duration CACHE_DURATION = Duration(minutes: 10);
  static const Duration USERS_CACHE_DURATION = Duration(minutes: 5);
  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;
  late AnimationController _fadeController;
  late Animation<double> _fadeInAnimation;
  // Dispose protection
  bool _isDisposed = false;
  StreamSubscription<String>? _fcmSubscription;

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
    _initializeFCM();
    _loadAdminData();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _fcmSubscription?.cancel();
    print('Dashboard disposed');
    _fadeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _currentPasswordController.dispose();
    super.dispose();
  }

  // Safe setState wrapper
  void _safeSetState(VoidCallback fn) {
    if (_isDisposed || !mounted) return;
    setState(fn);
  }

  // Add this method to handle back button in web
  Future<bool> _onWillPop() async {
    // If we're not on the main dashboard screen, navigate back
    if (_currentIndex != 0) {
      _safeSetState(() {
        _currentIndex = 0;
      });
      return false; // Don't exit app
    }
    return true; // Allow exit if on main dashboard
  }

  // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  // >>>>>>>>>>>>> ALL ORIGINAL LOGIC METHODS BELOW >>>>>>>>
  // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  Future<void> _initializeCache() async {
    final prefs = await SharedPreferences.getInstance();
    _totalStudents = prefs.getInt('${widget.schoolCode}_students') ?? 0;
    _totalTeachers = prefs.getInt('${widget.schoolCode}_teachers') ?? 0;
    _totalClasses = prefs.getInt('${widget.schoolCode}_classes') ?? 0;
    _todayAttendanceCount =
        prefs.getInt('${widget.schoolCode}_attendance') ?? 0;
    final lastFetch = prefs.getString('${widget.schoolCode}_last_fetch');
    if (lastFetch != null) {
      _lastDataFetchTime = DateTime.parse(lastFetch);
    }
    final lastUsersFetch = prefs.getString(
      '${widget.schoolCode}_last_users_fetch',
    );
    if (lastUsersFetch != null) {
      _lastUsersFetchTime = DateTime.parse(lastUsersFetch);
    }
    _adminName = prefs.getString('${widget.schoolCode}_admin_name') ?? '';
  }

  Future<void> _saveToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${widget.schoolCode}_students', _totalStudents);
    await prefs.setInt('${widget.schoolCode}_teachers', _totalTeachers);
    await prefs.setInt('${widget.schoolCode}_classes', _totalClasses);
    await prefs.setInt(
      '${widget.schoolCode}_attendance',
      _todayAttendanceCount,
    );
    await prefs.setString(
      '${widget.schoolCode}_last_fetch',
      DateTime.now().toIso8601String(),
    );
    await prefs.setString('${widget.schoolCode}_admin_name', _adminName);
  }

  Future<void> _saveUsersToCache(List<QueryDocumentSnapshot> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${widget.schoolCode}_users_count', users.length);
    await prefs.setString(
      '${widget.schoolCode}_last_users_fetch',
      DateTime.now().toIso8601String(),
    );
    _cachedUsers = users;
  }

  bool get _shouldFetchData {
    if (_lastDataFetchTime == null) return true;
    return DateTime.now().difference(_lastDataFetchTime!) > CACHE_DURATION;
  }

  bool get _shouldFetchUsers {
    if (_lastUsersFetchTime == null) return true;
    return DateTime.now().difference(_lastUsersFetchTime!) >
        USERS_CACHE_DURATION;
  }

  Future<void> _initializeFCM() async {
    await FCMService.subscribeToSchool(
      widget.schoolCode,
      widget.userId,
      'admin',
    );

    // Initial check in case the app was opened via a notification tap
    if (FCMService.pendingRouteType != null) {
      _routeFromNotification(FCMService.pendingRouteType!);
      FCMService.pendingRouteType = null;
    }

    // Subscribe to runtime taps
    _fcmSubscription ??= FCMService.onNotificationTapped.listen((type) {
      _routeFromNotification(type);
    });
  }

  void _routeFromNotification(String type) {
    if (!mounted || _isDisposed) return;
    switch (type) {
      case 'fee_payment_success':
      case 'fee_refund_processed':
        _navigateToFeeManagement();
        break;
      case 'notice':
      case 'announcement':
      case 'manual':
        _navigateToNoticesAndAnnouncements();
        break;
      case 'message':
        _navigateToMessages();
        break;
      case 'teacher_approval':
      case 'student_approval':
        _navigateToAdminManageUsers();
        break;
    }
  }

  Future<void> _loadDashboardData() async {
    _safeSetState(() {
      _isLoading = true;
    });
    try {
      if (_shouldFetchData) {
        await Future.wait([
          _loadSchoolData(), // NEW: Single method for all counts
          _loadTodayAttendanceCount(),
        ]);
        await _saveToCache();
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      print('Error loading dashboard data: $e');
    } finally {
      _safeSetState(() {
        _isLoading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _loadSchoolData() async {
    if (_isDisposed || !mounted) return;
    try {
      final schoolDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .get();

      if (_isDisposed || !mounted) return;

      if (schoolDoc.exists) {
        final schoolData = schoolDoc.data()!;
        _safeSetState(() {
          _totalStudents = schoolData['student_count'] ?? 0;
          _totalTeachers = schoolData['teacher_count'] ?? 0;
          _totalClasses = schoolData['class_count'] ?? 0;
        });
      }
    } catch (e) {
      print('Error loading school data: $e');
      // Fallback to individual queries if aggregated fields don't exist
      await _loadCountsFallback();
    }
  }

  Future<void> _loadCountsFallback() async {
    await Future.wait([
      _loadStudentCount(),
      _loadTeacherCount(),
      _loadClassCount(),
    ]);
  }

  Future<void> _loadAdminData() async {
    if (_adminName.isNotEmpty) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        _safeSetState(() {
          _adminName = userData['full_name'] ?? userData['username'] ?? 'Admin';
        });
        await _saveToCache();
      }
    } catch (e) {
      print('Error loading admin  $e');
    }
  }

  Future<void> _loadStudentCount() async {
    if (_isDisposed || !mounted) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .get();
      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _totalStudents = snapshot.docs.length;
      });
    } catch (e) {
      print('Error loading student count: $e');
    }
  }

  Future<void> _loadTeacherCount() async {
    if (_isDisposed || !mounted) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'teacher')
          .get();
      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _totalTeachers = snapshot.docs.length;
      });
    } catch (e) {
      print('Error loading teacher count: $e');
    }
  }

  Future<void> _loadClassCount() async {
    if (_isDisposed || !mounted) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();
      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _totalClasses = snapshot.docs.length;
      });
    } catch (e) {
      print('Error loading class count: $e');
    }
  }

  Future<void> _loadTodayAttendanceCount() async {
    if (_isDisposed || !mounted) return;
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // Optimized query: direct attendance collection access
      final attendanceSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('attendance')
          .where('date', isEqualTo: today)
          .get();

      int totalPresent = 0;
      for (var attendanceDoc in attendanceSnapshot.docs) {
        final data = attendanceDoc.data();
        final presentCount = (data['present_count'] as num?)?.toInt() ?? 0;
        totalPresent += presentCount;
      }

      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _todayAttendanceCount = totalPresent;
      });
    } catch (e) {
      print("Error loading today's attendance: $e");
      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _todayAttendanceCount = 0;
      });
    }
  }

  Future<void> _onRefresh() async {
    _safeSetState(() {
      _refreshing = true;
    });
    _lastDataFetchTime = null;
    _lastUsersFetchTime = null;
    await _loadDashboardData();
  }

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
      FCMService.unsubscribeFromAllNonBlocking(
        widget.schoolCode,
        widget.userId,
        'admin',
      );
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

  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();

  void _showChangePasswordDialog() {
    bool _dialogLoading = false;
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
            onWillPop: () async => !_dialogLoading,
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
                      enabled: !_dialogLoading,
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
                      enabled: !_dialogLoading,
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
                      enabled: !_dialogLoading,
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
                  onPressed: _dialogLoading
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
                  onPressed: _dialogLoading
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
                            _dialogLoading = true;
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
                                _dialogLoading = false;
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
                  child: _dialogLoading
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

  Future<void> _clearSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('school_code');
      await prefs.remove('school_name');
      await prefs.remove('is_super_admin_mode');
      await prefs.remove('user_role');
      await prefs.remove('${widget.schoolCode}_students');
      await prefs.remove('${widget.schoolCode}_teachers');
      await prefs.remove('${widget.schoolCode}_classes');
      await prefs.remove('${widget.schoolCode}_attendance');
      await prefs.remove('${widget.schoolCode}_last_fetch');
      await prefs.remove('${widget.schoolCode}_admin_name');
      await prefs.remove('${widget.schoolCode}_users_count');
      await prefs.remove('${widget.schoolCode}_last_users_fetch');
    } catch (e) {
      print('Error clearing shared preferences: $e');
    }
  }

  void _navigateToClassManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClassManagementScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _navigateToSchoolSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SchoolSettingsScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _navigateToAdminAddUsers() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminAddUsersScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _navigateToAdminManageUsers() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminManageUsersScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _navigateToTimetableManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TimetableManagementScreen(
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _viewSchoolReports() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AllGradesScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _navigateToNoticesAndAnnouncements() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoticesAndAnnouncementsScreen(
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          adminId: widget.userId,
        ),
      ),
    );
  }

  void _navigateToMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MessagesScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          userRole: 'admin',
          userName: _adminName,
        ),
      ),
    );
  }

  void _navigateToStudentManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentManagementScreen(
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _navigateToManageSubjects() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageSubjectsScreen(
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _navigateToManageExams() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageExamsScreen(
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _navigateToCreateExamSchedule() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateExamScheduleScreen(
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
        ),
      ),
    );
  }

  void _navigateToFeeManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminFeeStructureScreen(
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          adminId: widget.userId,
        ),
      ),
    );
  }

  void _navigateToStatisticsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatisticsFullScreen(
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          userId: widget.userId,
          onRefresh: () async {
            // This will trigger a refresh in the parent dashboard
            await _loadDashboardData();
          },
        ),
      ),
    );
  }

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;
  int _getStatGridCrossAxisCount() => _isMobile ? 2 : 4;
  double _getStatGridChildAspectRatio() => _isMobile ? 1.1 : 1.0;
  int _getActionGridCrossAxisCount() => _isMobile ? 2 : (_isTablet ? 3 : 3);
  double _getActionGridChildAspectRatio() =>
      _isMobile ? 1.0 : (_isTablet ? 1.2 : 1.4);

  // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  // >>>>>>>>>>>>> BUILD METHOD (FIXED FOR NAVIGATION) >>>>
  // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  @override
  Widget build(BuildContext context) {
    // Always use a single scaffold structure for consistent rebuilds
    if (_isDesktop) {
      return Scaffold(body: _buildDesktopLayout());
    } else {
      return _buildMobileTabletLayout();
    }
  }

  Widget _buildMobileTabletLayout() {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isMobile ? 'Dashboard' : 'Admin Dashboard'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue[800],
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              onPressed: _logout,
              tooltip: 'Logout',
            ),
          ],
        ),
        drawer: _isMobile ? _buildMobileDrawer() : null,
        body: RefreshIndicator(
          onRefresh: _onRefresh,
          child:
              _getCurrentScreen(), // This now rebuilds when _currentIndex changes
        ),
        bottomNavigationBar: _isMobile
            ? BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  _safeSetState(() {
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
                    icon: Icon(Icons.analytics),
                    label: 'Statistics',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.school),
                    label: 'School Info',
                  ),
                ],
              )
            : null,
      ),
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
                  _adminName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Code: ${widget.schoolCode}',
                  style: TextStyle(color: Colors.blue[100]),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard, color: Colors.blue),
            title: const Text('Dashboard'),
            onTap: () {
              _safeSetState(() => _currentIndex = 0);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.analytics, color: Colors.purple),
            title: const Text('Statistics'),
            onTap: () {
              _safeSetState(() => _currentIndex = 1);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.school, color: Colors.green),
            title: const Text('School Info'),
            onTap: () {
              _safeSetState(() => _currentIndex = 2);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.purple),
            title: const Text('Settings'),
            onTap: _navigateToSchoolSettings,
          ),
          ListTile(
            leading: const Icon(Icons.notifications, color: Colors.red),
            title: const Text('Announcements'),
            onTap: _navigateToNoticesAndAnnouncements,
          ),
          ListTile(
            leading: const Icon(Icons.message, color: Colors.blueAccent),
            title: const Text('Communicaton'),
            onTap: _navigateToMessages,
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop) {
          // Handle back button
          if (_currentIndex != 0) {
            _safeSetState(() {
              _currentIndex = 0;
            });
          } else {
            // Allow pop if already on main dashboard
            Navigator.of(context).pop();
          }
        }
      },
      child: Row(
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
                      _adminName.isNotEmpty ? _adminName[0].toUpperCase() : 'A',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 22, 105, 200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _adminName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromARGB(255, 21, 100, 191),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    widget.schoolName,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                  _buildSidebarItem(Icons.analytics, 'Statistics', 1),
                  _buildSidebarItem(Icons.school, 'School Information', 2),
                  const SizedBox(height: 16),
                  _buildSidebarActionItem(
                    Icons.settings,
                    'School Settings',
                    _navigateToSchoolSettings,
                  ),
                  _buildSidebarActionItem(
                    Icons.notifications,
                    'Announcements',
                    _navigateToNoticesAndAnnouncements,
                  ),
                  _buildSidebarActionItem(
                    Icons.analytics,
                    'View Reports',
                    _viewSchoolReports,
                  ),
                  _buildSidebarActionItem(
                    Icons.message,
                    'Communication',
                    _navigateToMessages,
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
      onTap: () => _safeSetState(() => _currentIndex = index),
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
          // Add back button
          if (_currentIndex != 0)
            IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.blue),
              onPressed: () {
                _safeSetState(() {
                  _currentIndex = 0;
                });
              },
              tooltip: 'Back to Dashboard',
            ),
          SizedBox(width: 8),
          Text(
            _getCurrentTitle(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 103, 195),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  String _getCurrentTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Dashboard Overview';
      case 1:
        return 'Statistics';
      case 2:
        return 'School Information';
      default:
        return 'Dashboard';
    }
  }

  Widget _getCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return _buildDashboard();
      case 1:
        return _buildStatisticsSection();
      case 2:
        return _buildSchoolInfo();
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
                      if (!_isMobile) _buildSchoolInfoCard(),
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
            colors: [Colors.purple[800]!, Colors.deepPurple[600]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(32),
            bottomRight: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
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
                      'Welcome, $_adminName 👋',
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.admin_panel_settings,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.schoolName,
                              style: const TextStyle(
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
                      Icons.person,
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
                'Students',
                _totalStudents.toString(),
                Icons.people,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Teachers',
                _totalTeachers.toString(),
                Icons.person_pin_circle,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Classes',
                _totalClasses.toString(),
                Icons.class_,
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
              'Admin Workspace',
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
                childAspectRatio: constraints.maxWidth < 340 ? 0.7 : 0.8,
                children: [
                  _buildFlatAppIcon(
                    'Classes',
                    Icons.class_,
                    Colors.blue,
                    _navigateToClassManagement,
                  ),
                  _buildFlatAppIcon(
                    'Settings',
                    Icons.settings,
                    Colors.purple,
                    _navigateToSchoolSettings,
                  ),
                  _buildFlatAppIcon(
                    'Timetable',
                    Icons.schedule,
                    Colors.teal,
                    _navigateToTimetableManagement,
                  ),
                  _buildFlatAppIcon(
                    'Add Users',
                    Icons.person_add,
                    Colors.orange,
                    _navigateToAdminAddUsers,
                  ),
                  _buildFlatAppIcon(
                    'Manage Users',
                    Icons.people,
                    Colors.green,
                    _navigateToAdminManageUsers,
                  ),
                  _buildFlatAppIcon(
                    'Reports',
                    Icons.analytics,
                    Colors.indigo,
                    _viewSchoolReports,
                  ),
                  _buildFlatAppIcon(
                    'Notices',
                    Icons.campaign,
                    Colors.red,
                    _navigateToNoticesAndAnnouncements,
                  ),
                  _buildFlatAppIcon(
                    'Message',
                    Icons.chat_bubble_outline,
                    Colors.lightBlue,
                    _navigateToMessages,
                  ),
                  _buildFlatAppIcon(
                    'Students',
                    Icons.school,
                    Colors.deepPurple,
                    _navigateToStudentManagement,
                  ),
                  _buildFlatAppIcon(
                    'Subjects',
                    Icons.menu_book,
                    Colors.brown,
                    _navigateToManageSubjects,
                  ),
                  _buildFlatAppIcon(
                    'Manage Exams',
                    Icons.assignment_turned_in,
                    Colors.deepOrange,
                    _navigateToManageExams,
                  ),
                  _buildFlatAppIcon(
                    'Exam Schedule',
                    Icons.event_note,
                    Colors.pink,
                    _navigateToCreateExamSchedule,
                  ),
                  _buildFlatAppIcon(
                    'Fee Mgmt',
                    Icons.account_balance_wallet,
                    Colors.green,
                    _navigateToFeeManagement,
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
          colors: [Colors.purple[800]!, Colors.purple[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.3),
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
                  'Welcome back, $_adminName!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage ${widget.schoolName} efficiently',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
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
                          'Last updated: ${DateFormat('MMM dd, yyyy – hh:mm a').format(_lastDataFetchTime!)}',
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

  Widget _buildSchoolInfoCard() {
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
                  backgroundColor: Colors.purple[50],
                  child: Icon(Icons.admin_panel_settings, size: 28, color: Colors.purple[700]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _adminName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple[800],
                        ),
                      ),
                      Text(
                        widget.schoolName,
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 110,
                    child: Text('School Code:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  Text(widget.schoolCode, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text('Role:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  Text('School Admin', style: TextStyle(fontSize: 16)),
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
                      'Last updated: ${DateFormat('MMM dd, HH:mm').format(_lastDataFetchTime!)}',
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
            _buildAnimatedActionCard(
              'Manage Classes',
              'Setup classes & sections',
              Icons.class_,
              Colors.blue,
              _navigateToClassManagement,
            ),
            _buildAnimatedActionCard(
              'School Settings',
              'Configure preferences',
              Icons.settings,
              Colors.purple,
              _navigateToSchoolSettings,
            ),
            _buildAnimatedActionCard(
              'Timetable',
              'Manage schedules',
              Icons.schedule,
              Colors.teal,
              _navigateToTimetableManagement,
            ),
            _buildAnimatedActionCard(
              'Add Users',
              'Add teachers/students',
              Icons.person_add,
              Colors.orange,
              _navigateToAdminAddUsers,
            ),
            _buildAnimatedActionCard(
              'Manage Users',
              'Edit or remove users',
              Icons.people,
              Colors.green,
              _navigateToAdminManageUsers,
            ),
            _buildAnimatedActionCard(
              'View Grades',
              'Review all results',
              Icons.analytics,
              Colors.indigo,
              _viewSchoolReports,
            ),
            _buildAnimatedActionCard(
              'Announcements',
              'Send notices',
              Icons.notifications,
              Colors.red,
              _navigateToNoticesAndAnnouncements,
            ),
            _buildAnimatedActionCard(
              'Communication',
              'Send and receive messages',
              Icons.message,
              Colors.blueAccent,
              _navigateToMessages,
            ),
            _buildAnimatedActionCard(
              'Manage Students',
              'Assign to classes',
              Icons.school,
              Colors.deepPurple,
              _navigateToStudentManagement,
            ),
            _buildAnimatedActionCard(
              'Manage Subjects',
              'Add/edit subjects',
              Icons.subject,
              Colors.brown,
              _navigateToManageSubjects,
            ),
            _buildAnimatedActionCard(
              'Manage Exams',
              'Create exams',
              Icons.assignment,
              Colors.deepOrange,
              _navigateToManageExams,
            ),
            _buildAnimatedActionCard(
              'Exam Schedule',
              'Plan exam dates',
              Icons.schedule,
              Colors.purple,
              _navigateToCreateExamSchedule,
            ),
            _buildAnimatedActionCard(
              'Change Password',
              'Update security',
              Icons.lock,
              Colors.grey,
              _showChangePasswordDialog,
            ),
          ],
        ),
      ],
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

  Widget _buildStatisticsSection() {
    return StatisticsFullScreen(
      schoolCode: widget.schoolCode,
      schoolName: widget.schoolName,
      userId: widget.userId,
      onRefresh: () async {
        await _loadDashboardData();
      },
    );
  }

  Widget _buildSchoolInfo() {
    if (_cachedSchoolInfo.isEmpty) {
      _loadSchoolInfo();
    }
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 32 : 16,
        vertical: _isDesktop ? 24 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'School Information',
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
                  _buildInfoRow('School Name', widget.schoolName),
                  _buildInfoRow('School Code', widget.schoolCode),
                  if (_cachedSchoolInfo['address'] != null)
                    _buildInfoRow(
                      'School Address',
                      _cachedSchoolInfo['address'],
                    ),
                  _buildInfoRow('Admin Role', 'School Administrator'),
                  _buildInfoRow('Admin ID', widget.userId),
                  _buildInfoRow('Total Students', _totalStudents.toString()),
                  _buildInfoRow('Total Teachers', _totalTeachers.toString()),
                  _buildInfoRow('Total Classes', _totalClasses.toString()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSchoolInfo() async {
    if (_isDisposed || !mounted) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .get();
      if (snapshot.exists) {
        _safeSetState(() {
          _cachedSchoolInfo = snapshot.data() ?? {};
        });
      }
    } catch (e) {
      print('Error loading school info: $e');
    }
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
}

// Statistics Full Screen
class StatisticsFullScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String userId;
  final Future<void> Function() onRefresh;

  const StatisticsFullScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.userId,
    required this.onRefresh,
  });

  @override
  State<StatisticsFullScreen> createState() => _StatisticsFullScreenState();
}

class _StatisticsFullScreenState extends State<StatisticsFullScreen> {
  int _totalStudents = 0;
  int _totalTeachers = 0;
  int _totalClasses = 0;
  int _todayAttendanceCount = 0;
  bool _isRefreshing = false;
  bool _isLoading = true;
  bool _usingCachedData = false;
  DateTime? _lastDataFetchTime;
  // Dispose protection
  bool _isDisposed = false;

  // Cache variables
  static const Duration CACHE_DURATION = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _initializeCache();
    _loadStatisticsData();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  // Safe setState wrapper
  void _safeSetState(VoidCallback fn) {
    if (_isDisposed || !mounted) return;
    setState(fn);
  }

  Future<void> _initializeCache() async {
    final prefs = await SharedPreferences.getInstance();
    _totalStudents = prefs.getInt('${widget.schoolCode}_students') ?? 0;
    _totalTeachers = prefs.getInt('${widget.schoolCode}_teachers') ?? 0;
    _totalClasses = prefs.getInt('${widget.schoolCode}_classes') ?? 0;
    _todayAttendanceCount =
        prefs.getInt('${widget.schoolCode}_attendance') ?? 0;
    final lastFetch = prefs.getString('${widget.schoolCode}_last_fetch');
    if (lastFetch != null) {
      _lastDataFetchTime = DateTime.parse(lastFetch);
    }
    _usingCachedData = !_shouldFetchData;
  }

  bool get _shouldFetchData {
    if (_lastDataFetchTime == null) return true;
    return DateTime.now().difference(_lastDataFetchTime!) > CACHE_DURATION;
  }

  Future<void> _loadStatisticsData() async {
    _safeSetState(() {
      _isLoading = true;
    });

    try {
      if (_shouldFetchData) {
        await Future.wait([
          _loadSchoolData(), // CHANGED: This now loads all counts in 1 read
          _loadTodayAttendanceCount(),
        ]);
        await _saveToCache();
        _usingCachedData = false;
      } else {
        // Use cached data
        await Future.delayed(const Duration(milliseconds: 500));
        _usingCachedData = true;
      }
    } catch (e) {
      print('Error loading statistics data: $e');
    } finally {
      _safeSetState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _loadSchoolData() async {
    if (_isDisposed || !mounted) return;
    try {
      final schoolDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .get();

      if (_isDisposed || !mounted) return;

      if (schoolDoc.exists) {
        final schoolData = schoolDoc.data()!;
        _safeSetState(() {
          _totalStudents = schoolData['student_count'] ?? 0;
          _totalTeachers = schoolData['teacher_count'] ?? 0;
          _totalClasses = schoolData['class_count'] ?? 0;
        });
      }
    } catch (e) {
      print('Error loading school data: $e');
      // Fallback to old method if aggregated fields don't exist
      await _loadCountsFallback();
    }
  }

  // Fallback method if aggregated fields aren't available
  Future<void> _loadCountsFallback() async {
    await Future.wait([
      _loadStudentCount(),
      _loadTeacherCount(),
      _loadClassCount(),
    ]);
  }

  Future<void> _loadStudentCount() async {
    if (_isDisposed || !mounted) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .get();
      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _totalStudents = snapshot.docs.length;
      });
    } catch (e) {
      print('Error loading student count: $e');
    }
  }

  Future<void> _loadTeacherCount() async {
    if (_isDisposed || !mounted) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'teacher')
          .get();
      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _totalTeachers = snapshot.docs.length;
      });
    } catch (e) {
      print('Error loading teacher count: $e');
    }
  }

  Future<void> _loadClassCount() async {
    if (_isDisposed || !mounted) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();
      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _totalClasses = snapshot.docs.length;
      });
    } catch (e) {
      print('Error loading class count: $e');
    }
  }

  Future<void> _loadTodayAttendanceCount() async {
    if (_isDisposed || !mounted) return;
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // Optimized query: direct attendance collection access
      final attendanceSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('attendance')
          .where('date', isEqualTo: today)
          .get();

      int totalPresent = 0;
      for (var attendanceDoc in attendanceSnapshot.docs) {
        final data = attendanceDoc.data();
        final presentCount = (data['present_count'] as num?)?.toInt() ?? 0;
        totalPresent += presentCount;
      }

      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _todayAttendanceCount = totalPresent;
      });
    } catch (e) {
      print("Error loading today's attendance: $e");
      if (_isDisposed || !mounted) return;
      _safeSetState(() {
        _todayAttendanceCount = 0;
      });
    }
  }

  Future<void> _saveToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${widget.schoolCode}_students', _totalStudents);
    await prefs.setInt('${widget.schoolCode}_teachers', _totalTeachers);
    await prefs.setInt('${widget.schoolCode}_classes', _totalClasses);
    await prefs.setInt(
      '${widget.schoolCode}_attendance',
      _todayAttendanceCount,
    );
    await prefs.setString(
      '${widget.schoolCode}_last_fetch',
      DateTime.now().toIso8601String(),
    );
    _lastDataFetchTime = DateTime.now();
  }

  Future<void> _refreshData() async {
    _safeSetState(() {
      _isRefreshing = true;
      _usingCachedData = false;
    });

    // Clear cache to force fresh data fetch
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${widget.schoolCode}_last_fetch');
    _lastDataFetchTime = null;

    await _loadStatisticsData();

    // Also refresh the parent dashboard
    await widget.onRefresh();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 600;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  int _getGridCrossAxisCount() {
    if (_isMobile) return 2;
    if (_isTablet) return 2;
    return 4;
  }

  double _getGridChildAspectRatio() {
    if (_isMobile) return 0.55;
    if (_isTablet) return 1;
    return 0.65;
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(body: _buildMainContent());
    } else {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'School Statistics',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.blue[700],
          actions: [
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.refresh, color: Colors.white),
              onPressed: _isRefreshing ? null : _refreshData,
              tooltip: 'Refresh Statistics',
            ),
          ],
        ),
        body: _buildMobileContent(),
      );
    }
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        // Desktop Top Bar
        Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          color: Colors.white,
          child: Row(
            children: [
              Text(
                'School Statistics',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
              ),
              Spacer(),
              IconButton(
                icon: _isRefreshing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue,
                          ),
                        ),
                      )
                    : Icon(Icons.refresh, color: Colors.blue),
                onPressed: _isRefreshing ? null : _refreshData,
                tooltip: 'Refresh Statistics',
              ),
            ],
          ),
        ),

        // Main Content
        Expanded(child: _buildStatisticsContent()),
      ],
    );
  }

  Widget _buildMobileContent() {
    return _isLoading
        ? const DashboardSkeleton()
        : RefreshIndicator(
            onRefresh: _refreshData,
            child: _buildStatisticsContent(),
          );
  }

  Widget _buildStatisticsContent() {
    if (_isLoading) {
      return const DashboardSkeleton();
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 24,
        vertical: _isMobile ? 16 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Last updated info
          if (_lastDataFetchTime != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Last updated: ${DateFormat('MMM dd, yyyy – HH:mm').format(_lastDataFetchTime!)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // Statistics Grid
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _getGridCrossAxisCount(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: _getGridChildAspectRatio(),
            ),
            children: [
              _buildStatCard(
                'Total Students',
                _totalStudents.toString(),
                Icons.school,
                Colors.green,
                'Registered students in school',
              ),
              _buildStatCard(
                'Total Teachers',
                _totalTeachers.toString(),
                Icons.person,
                Colors.orange,
                'Teaching staff members',
              ),
              _buildStatCard(
                'Total Classes',
                _totalClasses.toString(),
                Icons.class_,
                Colors.purple,
                'Active classes and sections',
              ),
              _buildStatCard(
                "Today's Attendance",
                _todayAttendanceCount.toString(),
                Icons.check_circle,
                Colors.blue,
                'Students present today',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String count,
    IconData icon,
    Color color,
    String description,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(minHeight: 240),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: _isMobile ? 32 : 36, color: color),
            ),
            const SizedBox(height: 20),
            Text(
              count,
              style: TextStyle(
                fontSize: _isMobile ? 28 : 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            // Title with constraints
            Container(
              constraints: BoxConstraints(maxHeight: 48),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: _isMobile ? 16 : 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            // Description with constraints
            Container(
              constraints: BoxConstraints(maxHeight: 40),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: _isMobile ? 12 : 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
// >>>>>>>>>>>>> SCHOOL USERS SCREEN (UNCHANGED) >>>>>>>>
// >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
// [Keep the entire SchoolUsersScreen, UserDetailsDialog, etc. exactly as in your original file]
// Since the original file includes them, and they work, we keep them below:

class SchoolUsersScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final List<QueryDocumentSnapshot> cachedUsers;
  final bool shouldFetchUsers;
  final Function(List<QueryDocumentSnapshot>) onUsersFetched;
  const SchoolUsersScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.cachedUsers,
    required this.shouldFetchUsers,
    required this.onUsersFetched,
  });

  @override
  State<SchoolUsersScreen> createState() => _SchoolUsersScreenState();
}

class _SchoolUsersScreenState extends State<SchoolUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedRoleFilter = 'all';
  final List<String> _roleFilters = ['all', 'student', 'teacher', 'admin'];
  List<QueryDocumentSnapshot> _users = [];
  bool _isLoading = true;
  bool _usingCachedData = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void didUpdateWidget(covariant SchoolUsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cachedUsers != oldWidget.cachedUsers) {
      _loadUsers();
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      if (widget.cachedUsers.isNotEmpty && !widget.shouldFetchUsers) {
        _users = widget.cachedUsers;
        _usingCachedData = true;
      } else {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('school_code', isEqualTo: widget.schoolCode)
            .get();
        _users = snapshot.docs;
        _usingCachedData = false;
        widget.onUsersFetched(_users);
      }
    } catch (e) {
      print('Error loading users: $e');
      if (widget.cachedUsers.isNotEmpty) {
        _users = widget.cachedUsers;
        _usingCachedData = true;
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showUserDetails(Map<String, dynamic> userData) {
    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: isDesktop
            ? const EdgeInsets.symmetric(horizontal: 100, vertical: 50)
            : const EdgeInsets.all(20),
        child: UserDetailsDialog(userData: userData),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text('${widget.schoolName} - Users'),
              backgroundColor: Colors.blue[700],
              actions: [
                if (_usingCachedData)
                  IconButton(
                    icon: const Icon(Icons.cloud_off, color: Colors.orange),
                    onPressed: _loadUsers,
                    tooltip: 'Using cached data - Tap to refresh',
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadUsers,
                  tooltip: 'Refresh Users',
                ),
              ],
            ),
      body: Column(
        children: [
          if (!isDesktop) _buildMobileSearchFilter(),
          if (isDesktop) _buildDesktopSearchFilter(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildUserList(),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    final filteredUsers = _users.where((user) {
      final userData = user.data() as Map<String, dynamic>;
      final username = userData['username']?.toString().toLowerCase() ?? '';
      final role = userData['role']?.toString() ?? '';
      final fullName = userData['full_name']?.toString().toLowerCase() ?? '';
      if (_selectedRoleFilter != 'all' && role != _selectedRoleFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        return username.contains(_searchQuery.toLowerCase()) ||
            fullName.contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList();

    if (filteredUsers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No users found matching your criteria',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    return isDesktop
        ? _buildDesktopUsersList(filteredUsers)
        : _buildMobileUsersList(filteredUsers);
  }

  Widget _buildMobileSearchFilter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search users by name or username...',
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
                _searchQuery = value;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedRoleFilter,
            decoration: const InputDecoration(
              labelText: 'Filter by Role',
              border: OutlineInputBorder(),
            ),
            items: _roleFilters.map((String role) {
              return DropdownMenuItem<String>(
                value: role,
                child: Text(role == 'all' ? 'All Roles' : role.toUpperCase()),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedRoleFilter = newValue ?? 'all';
              });
            },
          ),
          if (_usingCachedData) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Using cached data',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopSearchFilter() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users by name or username...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
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
                  _searchQuery = value;
                });
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: DropdownButtonFormField<String>(
              value: _selectedRoleFilter,
              decoration: InputDecoration(
                labelText: 'Filter by Role',
                labelStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
              ),
              items: _roleFilters.map((String role) {
                return DropdownMenuItem<String>(
                  value: role,
                  child: Text(
                    role == 'all' ? 'All Roles' : role.toUpperCase(),
                    style: const TextStyle(
                      color: Color.fromARGB(255, 70, 69, 69),
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedRoleFilter = newValue ?? 'all';
                });
              },
            ),
          ),
          if (_usingCachedData) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Cached Data',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _loadUsers,
            tooltip: 'Refresh Users',
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopUsersList(List<QueryDocumentSnapshot> users) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'User Management - ${widget.schoolName}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 21, 101, 193),
                ),
              ),
              const Spacer(),
              if (_usingCachedData)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 14,
                        color: Colors.orange[700],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Cached Data',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Total Users: ${users.length}${_usingCachedData ? ' (cached)' : ''}',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) =>
                      _buildDesktopUserItem(users[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopUserItem(QueryDocumentSnapshot user) {
    final userData = user.data() as Map<String, dynamic>;
    return InkWell(
      onTap: () => _showUserDetails(userData),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _buildUserListTile(userData),
      ),
    );
  }

  Widget _buildMobileUsersList(List<QueryDocumentSnapshot> users) {
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final userData = user.data() as Map<String, dynamic>;
        return InkWell(
          onTap: () => _showUserDetails(userData),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _buildUserListTile(userData),
          ),
        );
      },
    );
  }

  Widget _buildUserListTile(Map<String, dynamic> userData) {
    final username = userData['username'] ?? 'No username';
    final role = userData['role'] ?? 'unknown';
    final fullName = userData['full_name'] ?? 'No name';
    final isFirstLogin = userData['is_first_login'] ?? false;
    final status = userData['status'] ?? 'active';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getRoleColor(role),
        child: Text(
          username[0].toUpperCase(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(
        fullName != 'No name' ? fullName : username,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Username: $username'),
          Text('Role: ${role.toUpperCase()}'),
          if (isFirstLogin)
            const Text(
              '• First login required',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getRoleColor(role).withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          role.toUpperCase(),
          style: TextStyle(
            color: _getRoleColor(role),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.purple;
      case 'teacher':
        return Colors.orange;
      case 'student':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

class UserDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> userData;
  const UserDetailsDialog({super.key, required this.userData});

  @override
  State<UserDetailsDialog> createState() => _UserDetailsDialogState();
}

class _UserDetailsDialogState extends State<UserDetailsDialog> {
  Map<String, dynamic>? _classInfo;
  bool _isLoadingClass = false;

  @override
  void initState() {
    super.initState();
    if (widget.userData['role'] == 'student' &&
        widget.userData['class_id'] != null &&
        widget.userData['class_id'].toString().isNotEmpty) {
      _loadClassInfo();
    }
  }

  Future<void> _loadClassInfo() async {
    if (widget.userData['class_id'] == null) return;
    setState(() {
      _isLoadingClass = true;
    });
    try {
      final classDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.userData['school_code'])
          .collection('classes')
          .doc(widget.userData['class_id'])
          .get();
      if (classDoc.exists) {
        setState(() {
          _classInfo = classDoc.data();
          _isLoadingClass = false;
        });
      } else {
        setState(() {
          _isLoadingClass = false;
        });
      }
    } catch (e) {
      print('Error loading class info: $e');
      setState(() {
        _isLoadingClass = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;
    final isStudent = widget.userData['role'] == 'student';
    final hasClassId =
        widget.userData['class_id'] != null &&
        widget.userData['class_id'].toString().isNotEmpty;
    return Dialog(
      insetPadding: isDesktop
          ? const EdgeInsets.symmetric(horizontal: 100, vertical: 50)
          : const EdgeInsets.all(16),
      child: Container(
        constraints: isDesktop
            ? const BoxConstraints(maxWidth: 600, maxHeight: 700)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[700],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'User Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isStudent) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Class Information',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (hasClassId) ...[
                              if (_isLoadingClass)
                                const Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Loading class information...'),
                                  ],
                                )
                              else if (_classInfo != null) ...[
                                _buildClassDetailRow(
                                  'Grade',
                                  _classInfo!['grade'] ?? 'N/A',
                                ),
                                _buildClassDetailRow(
                                  'Section',
                                  widget.userData['section'] ?? 'N/A',
                                ),
                                _buildClassDetailRow(
                                  'Class ID',
                                  widget.userData['class_id'] ?? 'N/A',
                                ),
                              ] else
                                const Text('Class information not found'),
                            ] else
                              const Text('Student not assigned to any class'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildUserDetailRow(
                      'Username',
                      widget.userData['username'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Full Name',
                      widget.userData['full_name'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Role',
                      widget.userData['role'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Status',
                      widget.userData['status'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'School Code',
                      widget.userData['school_code'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Mobile Number',
                      widget.userData['mobile_number'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Alternate Mobile',
                      widget.userData['alternate_mobile_number'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'School Telephone',
                      widget.userData['school_telephone_number'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Gmail',
                      widget.userData['gmail'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'First Login Required',
                      (widget.userData['is_first_login'] ?? false)
                          ? 'Yes'
                          : 'No',
                    ),
                    if (widget.userData['created_at'] != null)
                      _buildUserDetailRow(
                        'Created At',
                        _formatDate(widget.userData['created_at'].toDate()),
                      ),
                    if (widget.userData['created_by'] != null)
                      _buildUserDetailRow(
                        'Created By',
                        widget.userData['created_by'],
                      ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Widget _buildClassDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.blue,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
