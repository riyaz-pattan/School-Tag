// student_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'student_notices_screen.dart';
import 'student_assignments_screen.dart';
import 'student_attendance_screen.dart';
import 'student_grades_screen.dart';
import 'services/fcm_service.dart';
import 'school_code_screen.dart';
import 'student_view_exam_schedule_screen.dart';
import 'dart:convert';
import 'dart:async';
import 'messages_screen.dart';
import 'student_performance_screen.dart';
import 'ai_chat_screen.dart';
import 'widgets/dashboard_skeleton.dart';
import 'student_fee_screen.dart';
import 'student_apply_leave_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  final String userId;
  final String schoolName;
  final String schoolCode;
  const StudentDashboardScreen({
    super.key,
    required this.userId,
    required this.schoolName,
    required this.schoolCode,
  });

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  int _currentIndex = 0;
  Map<String, dynamic>? _studentData;
  StreamSubscription<String>? _fcmSubscription;
  bool _isLoading = true;
  String? _errorMessage;
  String _studentName = '';
  String? _studentClassId;
  String? _studentSection;
  Map<String, dynamic>? _timetable;
  bool _isRefreshing = false;
  Map<String, dynamic>? _schoolData;
  Map<String, String> _teacherNameMap = {};
  int _studentLevel = 5;

  // Cache keys
  static const String _studentDataCacheKey = 'student_data';
  static const String _timetableCacheKey = 'timetable';
  static const String _schoolDataCacheKey = 'school_data';
  static const String _lastFetchTimeKey = 'last_fetch_time';

  // Cache duration (5 minutes)
  final Duration _cacheDuration = const Duration(minutes: 5);

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // Password controllers
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();

  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      // Load cached data first for immediate display
      await _loadCachedData();
      // Then load fresh data in background
      await _loadFreshData();
      await _initializeFCM();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error in _loadInitialData: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load dashboard data. Please try again.';
        });
      }
    }
  }

  // Helper method to convert Firestore data to JSON-serializable format
  dynamic _convertToJsonSerializable(dynamic data) {
    if (data is Timestamp) {
      return {
        '_timestamp': true,
        'seconds': data.seconds,
        'nanoseconds': data.nanoseconds,
      };
    } else if (data is Map<String, dynamic>) {
      return data.map(
        (key, value) => MapEntry(key, _convertToJsonSerializable(value)),
      );
    } else if (data is List<dynamic>) {
      return data.map((item) => _convertToJsonSerializable(item)).toList();
    } else if (data is DocumentReference) {
      return {'_documentReference': true, 'path': data.path};
    } else if (data is GeoPoint) {
      return {
        '_geoPoint': true,
        'latitude': data.latitude,
        'longitude': data.longitude,
      };
    }
    return data;
  }

  // Helper method to convert JSON data back to Firestore types
  dynamic _convertFromJsonSerializable(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['_timestamp'] == true) {
        return Timestamp(data['seconds'], data['nanoseconds']);
      } else if (data['_documentReference'] == true) {
        return FirebaseFirestore.instance.doc(data['path']);
      } else if (data['_geoPoint'] == true) {
        return GeoPoint(data['latitude'], data['longitude']);
      } else {
        return data.map(
          (key, value) => MapEntry(key, _convertFromJsonSerializable(value)),
        );
      }
    } else if (data is List<dynamic>) {
      return data.map((item) => _convertFromJsonSerializable(item)).toList();
    }
    return data;
  }

  Future<void> _loadCachedData() async {
    try {
      // Load student data from cache
      final cachedStudentData = _prefs.getString(
        '${_studentDataCacheKey}_${widget.userId}',
      );
      if (cachedStudentData != null) {
        final decodedData = json.decode(cachedStudentData);
        setState(() {
          _studentData = Map<String, dynamic>.from(
            _convertFromJsonSerializable(decodedData),
          );
          _studentName =
              _studentData?['full_name'] ??
              _studentData?['username'] ??
              'Student';
          _studentClassId = _studentData?['class_id'];
          _studentSection = _studentData?['section'];
        });
      }
      // Load timetable from cache
      if (_studentClassId != null && _studentClassId!.isNotEmpty) {
        final cachedTimetable = _prefs.getString(
          '${_timetableCacheKey}_${widget.schoolCode}_$_studentClassId}',
        );
        if (cachedTimetable != null) {
          final decodedData = json.decode(cachedTimetable);
          setState(() {
            _timetable = Map<String, dynamic>.from(
              _convertFromJsonSerializable(decodedData),
            );
          });
        }
      }
      // Load school data from cache
      final cachedSchoolData = _prefs.getString(
        '${_schoolDataCacheKey}_${widget.schoolCode}',
      );
      if (cachedSchoolData != null) {
        final decodedData = json.decode(cachedSchoolData);
        setState(() {
          _schoolData = Map<String, dynamic>.from(
            _convertFromJsonSerializable(decodedData),
          );
        });
      }
    } catch (e) {
      print('Error loading cached data: $e');
    }
  }

  Future<void> _loadFreshData() async {
    final lastFetchTime = _prefs.getInt(_lastFetchTimeKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final shouldRefresh = now - lastFetchTime > _cacheDuration.inMilliseconds;

    if (!shouldRefresh && _studentData != null) {
      // Still update level even with cached data
      await _updateStudentLevel();
      return;
    }

    try {
      await _loadStudentData();
      await _updateStudentLevel(); // Always update level
      await _loadTimetable();
      await _loadSchoolData();
      await _loadTeachers();
      // Update last fetch time
      await _prefs.setInt(_lastFetchTimeKey, now);
    } catch (e) {
      print('Error loading fresh data: $e');
      if (_studentData == null) {
        setState(() {
          _errorMessage = 'Failed to load fresh data. Using cached version.';
        });
      }
    }
  }

  Future<void> _forceRefresh() async {
    if (_isRefreshing) return;
    // Clear cache for fresh data
    await _prefs.remove('${_studentDataCacheKey}_${widget.userId}');
    if (_studentClassId != null) {
      await _prefs.remove(
        '${_timetableCacheKey}_${widget.schoolCode}_$_studentClassId}',
      );
    }
    await _prefs.remove('${_schoolDataCacheKey}_${widget.schoolCode}');
    await _prefs.remove(_lastFetchTimeKey);
    setState(() {
      _isRefreshing = true;
    });
    try {
      await _loadFreshData();
    } catch (e) {
      print('Error in force refresh: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _initializeFCM() async {
    await FCMService.subscribeToSchool(
      widget.schoolCode,
      widget.userId,
      'student',
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
    if (!mounted) return;
    switch (type) {
      case 'fee_reminder':
      case 'fee_payment_success':
      case 'fee_refund_processed':
        _navigateToFees();
        break;
      case 'notice':
      case 'announcement':
      case 'manual':
        _navigateToNotices();
        break;
      case 'assignment':
        _navigateToAssignments();
        break;
      case 'message':
        _navigateToMessages();
        break;
    }
  }

  Future<void> _loadStudentData() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        setState(() {
          _studentData = data;
          _studentName = data['full_name'] ?? data['username'] ?? 'Student';
          _studentClassId = data['class_id'];
          _studentSection = data['section'];
          _studentLevel = data['level'] ?? 5;
        });
        // Cache the data
        await _prefs.setString(
          '${_studentDataCacheKey}_${widget.userId}',
          json.encode(_convertToJsonSerializable(data)),
        );
      } else {
        setState(() {
          _errorMessage = 'Student data not found';
        });
      }
    } catch (e) {
      print('Error loading student data: $e');
      setState(() {
        _errorMessage = 'Error loading student data: $e';
      });
    }
  }

  Future<void> _loadTimetable() async {
    if (_studentClassId == null || _studentClassId!.isEmpty) {
      return;
    }
    try {
      final timetableDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .doc(_studentClassId)
          .get();
      if (timetableDoc.exists) {
        final data = timetableDoc.data()!;
        setState(() {
          _timetable = data;
        });
        // Cache the timetable
        await _prefs.setString(
          '${_timetableCacheKey}_${widget.schoolCode}_$_studentClassId}',
          json.encode(_convertToJsonSerializable(data)),
        );
      }
    } catch (e) {
      print('Error loading timetable: $e');
    }
  }

  Future<void> _loadSchoolData() async {
    try {
      final schoolDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .get();
      if (schoolDoc.exists) {
        final data = schoolDoc.data()!;
        setState(() {
          _schoolData = data;
        });
        // Cache the school data
        await _prefs.setString(
          '${_schoolDataCacheKey}_${widget.schoolCode}',
          json.encode(_convertToJsonSerializable(data)),
        );
      }
    } catch (e) {
      print('Error loading school data: $e');
    }
  }

  Future<void> _loadTeachers() async {
    try {
      final teachersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'teacher')
          .get();

      final teacherMap = <String, String>{};
      for (var doc in teachersSnapshot.docs) {
        final data = doc.data();
        final teacherId = doc.id;
        final fullName = data['full_name']?.toString();
        final username = data['username']?.toString() ?? 'Unknown';

        // Use full_name if available, otherwise fall back to username
        teacherMap[teacherId] =
            (fullName != null && fullName.isNotEmpty && fullName != 'No Name')
            ? fullName
            : username;
      }

      setState(() {
        _teacherNameMap = teacherMap;
      });
    } catch (e) {
      print('Error loading teachers: $e');
    }
  }

  String _getTeacherName(String? teacherId) {
    if (teacherId == null) return 'Unassigned';
    return _teacherNameMap[teacherId] ?? 'Unknown Teacher';
  }

  // Responsive layout methods
  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  void dispose() {
    _fcmSubscription?.cancel();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _currentPasswordController.dispose();
    super.dispose();
  }

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
                          // Validation
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
                            // Re-authenticate user before password change
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
                            // Update password in Firebase Auth
                            await user.updatePassword(newPassword);
                            await user.getIdToken(true);
                            // Update the is_first_login flag in Firestore
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(widget.userId)
                                .update({
                                  'password': newPassword,
                                  'is_first_login': false,
                                });
                            // Close dialog first
                            _dialogOpen = false;
                            if (mounted) Navigator.pop(context);
                            // Clear controllers
                            _currentPasswordController.clear();
                            _newPasswordController.clear();
                            _confirmPasswordController.clear();
                            // Show success message
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
                            } else if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Error changing password: $message',
                                  ),
                                ),
                              );
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

  Future<void> _updateStudentLevel() async {
    try {
      // Calculate average marks from all exams
      final gradesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('grades')
          .where('student_id', isEqualTo: widget.userId)
          .get();

      if (gradesSnapshot.docs.isEmpty) {
        // No grades yet, keep the current level
        return;
      }

      double totalWeightedPercentage = 0;
      int totalWeight = 0;
      Map<String, Map<String, dynamic>> examData = {};

      // First, group grades by exam
      for (var gradeDoc in gradesSnapshot.docs) {
        final grade = gradeDoc.data();
        final examId = grade['exam_id'] as String?;
        final marksObtained = grade['marks_obtained'] as int? ?? 0;
        final maxMarks = grade['max_marks'] as int? ?? 100;
        final isAbsent = grade['is_absent'] == true;

        if (examId == null || maxMarks <= 0) continue;

        if (!examData.containsKey(examId)) {
          examData[examId] = {
            'total_marks': 0,
            'max_total_marks': 0,
            'subject_count': 0,
            'graded_subject_count': 0,
          };
        }

        final exam = examData[examId]!;
        exam['subject_count'] = (exam['subject_count'] as int) + 1;

        if (!isAbsent) {
          exam['max_total_marks'] = (exam['max_total_marks'] as int) + maxMarks;
          exam['total_marks'] = (exam['total_marks'] as int) + marksObtained;
          exam['graded_subject_count'] =
              (exam['graded_subject_count'] as int) + 1;
        }
      }

      // Calculate weighted average across all exams
      for (var exam in examData.values) {
        final totalMarks = exam['total_marks'] as int;
        final maxTotalMarks = exam['max_total_marks'] as int;
        final gradedSubjectCount = exam['graded_subject_count'] as int;

        // Only include exams where at least some subjects are graded
        if (gradedSubjectCount > 0 && maxTotalMarks > 0) {
          // Calculate exam percentage
          final examPercentage = (totalMarks / maxTotalMarks) * 100;

          // Weight by number of graded subjects
          totalWeightedPercentage += examPercentage * gradedSubjectCount;
          totalWeight += gradedSubjectCount;
        }
      }

      if (totalWeight > 0) {
        final overallPercentage = totalWeightedPercentage / totalWeight;

        // Calculate level based on percentage (1-10 scale)
        int newLevel;
        if (overallPercentage <= 20)
          newLevel = 1;
        else if (overallPercentage <= 30)
          newLevel = 2;
        else if (overallPercentage <= 40)
          newLevel = 3;
        else if (overallPercentage <= 50)
          newLevel = 4;
        else if (overallPercentage <= 60)
          newLevel = 5;
        else if (overallPercentage <= 70)
          newLevel = 6;
        else if (overallPercentage <= 75)
          newLevel = 7;
        else if (overallPercentage <= 80)
          newLevel = 8;
        else if (overallPercentage <= 90)
          newLevel = 9;
        else
          newLevel = 10;

        // Update level in database
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .update({'level': newLevel});

        // Update local state
        if (mounted) {
          setState(() {
            _studentLevel = newLevel;
            _studentData?['level'] = newLevel;
          });
        }

        // Force refresh to update UI
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }
      }
    } catch (e) {
      print('Error updating student level: $e');
      // Keep current level on error, do nothing
    }
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
        'student',
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

  Future<void> _clearSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('school_code');
      await prefs.remove('school_name');
      await prefs.remove('is_super_admin_mode');
      await prefs.remove('user_role');
      // Clear our cache keys
      await prefs.remove('${_studentDataCacheKey}_${widget.userId}');
      if (_studentClassId != null) {
        await prefs.remove(
          '${_timetableCacheKey}_${widget.schoolCode}_$_studentClassId}',
        );
      }
      await prefs.remove('${_schoolDataCacheKey}_${widget.schoolCode}');
      await prefs.remove(_lastFetchTimeKey);
    } catch (e) {
      print('Error clearing shared preferences: $e');
    }
  }

  void _navigateToNotices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentNoticesScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          studentId: widget.userId,
          studentName: _studentName,
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
          userRole: 'student',
          userName: _studentName,
        ),
      ),
    );
  }

  void _navigateToAssignments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentAssignmentsScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          studentId: widget.userId,
          studentName: _studentName,
        ),
      ),
    );
  }

  // In the _navigateToPerformance() method in student_dashboard_screen.dart, change:

  void _navigateToPerformance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentPerformanceScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          studentId: widget.userId,
          studentName: _studentName,
          currentLevel:
              _studentLevel, // Use _studentLevel, not widget.currentLevel
        ),
      ),
    );
  }

  void _navigateToAIChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AiChatScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          studentName: _studentName,
          studentClassId: _studentClassId,
          studentLevel: _studentLevel,
        ),
      ),
    );
  }

  void _navigateToFees() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentFeeScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          studentName: _studentName,
        ),
      ),
    );
  }

  void _navigateToApplyLeave() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentApplyLeaveScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          studentName: _studentName,
          classId: _studentClassId,
          section: _studentSection,
        ),
      ),
    );
  }

  void _navigateToExamSchedules() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentViewExamScheduleScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          studentId: widget.userId,
          classId: _studentClassId,
        ),
      ),
    );
  }

  void _navigateToAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentAttendanceScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          studentId: widget.userId,
          studentName: _studentName,
          classId: _studentClassId,
          section: _studentSection,
        ),
      ),
    );
  }

  void _navigateToGrades() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentGradesScreen(
          schoolCode: widget.schoolCode,
          userId: widget.userId,
          schoolName: widget.schoolName,
          studentId: widget.userId,
          studentName: _studentName,
        ),
      ),
    );
  }

  void _viewFullTimetable() {
    if (_studentClassId == null || _studentClassId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are not assigned to any class')),
      );
      return;
    }
    if (_timetable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timetable not available for your class')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: _isDesktop
            ? const EdgeInsets.symmetric(horizontal: 100, vertical: 50)
            : const EdgeInsets.all(16),
        child: Container(
          constraints: _isDesktop
              ? const BoxConstraints(maxWidth: 700, maxHeight: 500)
              : null,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
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
                      'Weekly Timetable',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: _buildFullTimetable(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfileDialog() {
    if (_studentData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student data not available')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => StudentProfileDialog(
        studentData: _studentData!,
        schoolName: widget.schoolName,
        schoolCode: widget.schoolCode,
        schoolData: _schoolData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: DashboardSkeleton());
    }

    if (_isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            _buildDesktopSidebar(),
            Expanded(
              child: Column(
                children: [
                  _buildDesktopTopBar(),
                  Expanded(child: _getCurrentScreen()),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return _buildMobileTabletLayout();
    }
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isMobile ? 'Student Dashboard' : 'Student Dashboard'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 0,
        actions: [
          if (!_isMobile)
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue,
                      ),
                    )
                  : const Icon(Icons.refresh, color: Colors.blue),
              onPressed: _isRefreshing ? null : _forceRefresh,
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
      body: RefreshIndicator(
        onRefresh: _forceRefresh,
        child: _getCurrentScreen(),
      ),
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
                  icon: Icon(Icons.person),
                  label: 'Profile',
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
                  _studentName,
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
              setState(() => _currentIndex = 0);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.green),
            title: const Text('Profile'),
            onTap: () {
              setState(() => _currentIndex = 1);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications, color: Colors.orange),
            title: const Text('Notices'),
            onTap: _navigateToNotices,
          ),
          ListTile(
            leading: const Icon(Icons.message, color: Colors.blueAccent),
            title: const Text('Communication'),
            onTap: _navigateToMessages,
          ),
          ListTile(
            leading: const Icon(Icons.assignment, color: Colors.green),
            title: const Text('Assignments'),
            onTap: _navigateToAssignments,
          ),
          ListTile(
            leading: const Icon(Icons.grade, color: Colors.purple),
            title: const Text('Grades'),
            onTap: _navigateToGrades,
          ),
          ListTile(
            leading: const Icon(Icons.schedule, color: Colors.teal),
            title: const Text('View Timetable'),
            onTap: _viewFullTimetable,
          ),
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text('Attendance'),
            onTap: _navigateToAttendance,
          ),
          ListTile(
            leading: const Icon(Icons.event_busy, color: Colors.deepOrange),
            title: const Text('Apply Leave'),
            onTap: _navigateToApplyLeave,
          ),
          ListTile(
            leading: const Icon(Icons.event_note, color: Colors.pink),
            title: const Text('Exam Schedules'),
            onTap: _navigateToExamSchedules,
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
                      _studentName.isNotEmpty
                          ? _studentName[0].toUpperCase()
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
                    _studentName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromARGB(255, 21, 104, 198),
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
                  _buildSidebarItem(Icons.person, 'Profile', 1),
                  const SizedBox(height: 16),
                  _buildSidebarActionItem(
                    Icons.notifications,
                    'Notices',
                    _navigateToNotices,
                  ),
                  _buildSidebarActionItem(
                    Icons.message,
                    'Communication',
                    _navigateToMessages,
                  ),
                  _buildSidebarActionItem(
                    Icons.assignment,
                    'Assignments',
                    _navigateToAssignments,
                  ),
                  _buildSidebarActionItem(
                    Icons.grade,
                    'Grades',
                    _navigateToGrades,
                  ),
                  _buildSidebarActionItem(
                    Icons.schedule,
                    'View Timetable',
                    _viewFullTimetable,
                  ),
                  _buildSidebarActionItem(
                    Icons.check_circle,
                    'Attendance',
                    _navigateToAttendance,
                  ),
                  _buildSidebarActionItem(
                    Icons.event_busy,
                    'Apply Leave',
                    _navigateToApplyLeave,
                  ),
                  _buildSidebarActionItem(
                    Icons.event_note,
                    'Exam Schedules',
                    _navigateToExamSchedules,
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
      selected: isSelected,
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
        style: const TextStyle(color: Color.fromARGB(255, 94, 94, 94)),
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
          Text(
            _getCurrentTitle(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 22, 103, 197),
            ),
          ),
          const Spacer(),
          if (_studentClassId != null && _studentClassId!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Class: ${_studentData?['class_name'] ?? _studentClassId}',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(width: 12),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _isRefreshing ? null : _forceRefresh,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
    );
  }

  String _getCurrentTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Student Dashboard';
      case 1:
        return 'Student Profile';
      default:
        return 'Student Dashboard';
    }
  }

  Widget _getCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return _buildDashboard();
      case 1:
        return _buildProfileSection();
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    return Container(
      color: const Color(0xFFF7F9FC),
      child: RefreshIndicator(
        onRefresh: _forceRefresh,
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
                    if (!_isMobile) _buildStudentInfoCard(),
                    const SizedBox(height: 16),
                    _buildWorkspaceSection(),
                    const SizedBox(height: 32),
                    _buildTimetableCarousel(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.only(
          top: 30,
          left: 24,
          right: 24,
          bottom: 32,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[800]!, Colors.indigo[600]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(32),
            bottomRight: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
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
                      '${_getGreeting()},',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hi, $_studentName 👋',
                      style: const TextStyle(
                        fontSize: 28,
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
                          Icon(
                            Icons.school,
                            color: _getLevelColor(_studentLevel),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Level $_studentLevel',
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
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: const Icon(
                      Icons.person,
                      size: 36,
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

  Widget _buildProfileSection() {
    return RefreshIndicator(
      onRefresh: _forceRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: _isMobile ? 16 : 24,
          vertical: _isMobile ? 12 : 20,
        ),
        child: Column(
          children: [
            // Profile Header
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.blue[100],
                      child: Text(
                        _studentName.isNotEmpty
                            ? _studentName[0].toUpperCase()
                            : 'S',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 22, 105, 200),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _studentName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 22, 105, 200),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Student',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    if (_studentData?['class_name'] != null)
                      Text(
                        '${_studentData!['class_name']}${_studentSection != null ? ' • $_studentSection' : ''}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Personal Information
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personal Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 22, 105, 200),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildProfileInfoItem(
                      'Full Name',
                      _studentData?['full_name'] ?? 'N/A',
                    ),
                    _buildProfileInfoItem(
                      'Username',
                      _studentData?['username'] ?? 'N/A',
                    ),
                    _buildProfileInfoItem('Student ID', widget.userId),
                    _buildProfileInfoItem(
                      'Email',
                      _studentData?['gmail'] ?? 'N/A',
                    ),
                    _buildProfileInfoItem(
                      'Mobile Number',
                      _studentData?['mobile_number'] ?? 'N/A',
                    ),
                    _buildProfileInfoItem(
                      'Alternate Mobile',
                      _studentData?['alternate_mobile_number'] ?? 'N/A',
                    ),
                    if (_studentData?['roll_number'] != null)
                      _buildProfileInfoItem(
                        'Roll Number',
                        _studentData!['roll_number'],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // School Information
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'School Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 22, 105, 200),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildProfileInfoItem('School Name', widget.schoolName),
                    _buildProfileInfoItem('School Code', widget.schoolCode),
                    if (_schoolData?['address'] != null)
                      _buildProfileInfoItem(
                        'School Address',
                        _schoolData!['address'],
                      ),
                    if (_studentData?['class_name'] != null)
                      _buildProfileInfoItem(
                        'Class',
                        _studentData!['class_name'],
                      ),
                    if (_studentSection != null && _studentSection!.isNotEmpty)
                      _buildProfileInfoItem('Section', _studentSection!),
                    if (_studentData?['class_id'] != null)
                      _buildProfileInfoItem(
                        'Class ID',
                        _studentData!['class_id'],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[800]!, Colors.blue[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
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
                  '${_getGreeting()}, $_studentName!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Access your school resources efficiently',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                if (_studentData?['class_name'] != null)
                  Text(
                    'Class: ${_studentData!['class_name']}${_studentSection != null ? ' • Section: $_studentSection' : ''}',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                const SizedBox(height: 12),
                // ADD THIS LEVEL BADGE
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_graph,
                        size: 16,
                        color: _getLevelColor(_studentLevel),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Level $_studentLevel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.school, size: 80, color: Colors.white.withOpacity(0.2)),
        ],
      ),
    );
  }

  // Helper method to get level color
  Color _getLevelColor(int level) {
    if (level <= 3) return Colors.red[400]!;
    if (level <= 5) return Colors.orange[400]!;
    if (level <= 7) return Colors.yellow[700]!;
    return Colors.green[500]!;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  Widget _buildStudentInfoCard() {
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
                  radius: 24,
                  backgroundColor: Colors.blue[50],
                  child: Icon(Icons.person, color: Colors.blue[600]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _studentName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      Text(
                        widget.schoolName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 24),
            if (_studentData?['class_name'] != null)
              _buildProfileItem('Class', _studentData!['class_name']),
            if (_studentData?['roll_number'] != null)
              _buildProfileItem('Roll Number', _studentData!['roll_number']),
            if (_studentSection != null && _studentSection!.isNotEmpty)
              _buildProfileItem('Section', _studentSection!),
            // ADD THIS FOR LEVEL
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Performance Level',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getLevelColor(_studentLevel).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Level $_studentLevel',
                    style: TextStyle(
                      color: _getLevelColor(_studentLevel),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Level progress indicator
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _studentLevel / 10,
                backgroundColor: Colors.grey[100],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getLevelColor(_studentLevel),
                ),
                minHeight: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetableCarousel() {
    final currentDay = DateFormat('EEEE').format(DateTime.now()).toLowerCase();
    final timetableData =
        _timetable?['timetable'] as Map<String, dynamic>? ?? {};
    final todayPeriods = timetableData[currentDay] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Today's Schedule",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              DateFormat('MMM d, yyyy').format(DateTime.now()),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (todayPeriods.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.event_busy,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No classes today',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enjoy your free time or review past subjects.',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 230,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              itemCount: todayPeriods.length,
              itemBuilder: (context, index) {
                final period = todayPeriods[index];
                final isBreak = period['type'] == 'break';

                final List<Color> gradientColors = isBreak
                    ? [Colors.orange[400]!, Colors.deepOrange[400]!]
                    : [Colors.blue[600]!, Colors.indigo[500]!];

                return Container(
                  width: 250,
                  margin: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: gradientColors[0].withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -20,
                        bottom: -20,
                        child: Icon(
                          isBreak ? Icons.free_breakfast : Icons.auto_stories,
                          size: 140,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                  child: Text(
                                    isBreak
                                        ? 'Break'
                                        : 'Period ${period['number']}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              isBreak
                                  ? 'Break Time'
                                  : (period['subject'] ?? 'No Subject'),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            if (!isBreak && period['teacher_id'] != null)
                              Text(
                                'With ${_getTeacherName(period['teacher_id'])}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${period['start_time']} - ${period['end_time']}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
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
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildWorkspaceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My Workspace',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
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
                mainAxisSpacing: 5,
                crossAxisSpacing: 16,
                childAspectRatio: constraints.maxWidth < 340 ? 0.7 : 0.8,
                children: [
                  _buildPremiumAppIcon(
                    'Timetable',
                    'calendar',
                    _viewFullTimetable,
                  ),
                  _buildPremiumAppIcon(
                    'Attendance',
                    'checked-user-male',
                    _navigateToAttendance,
                  ),
                  _buildPremiumAppIcon(
                    'Assignments',
                    'book-stack',
                    _navigateToAssignments,
                  ),
                  _buildPremiumAppIcon(
                    'Notices',
                    'megaphone',
                    _navigateToNotices,
                  ),
                  _buildPremiumAppIcon(
                    'Messages',
                    'speech-bubble-with-dots',
                    _navigateToMessages,
                  ),
                  _buildPremiumAppIcon('Grades', 'medal', _navigateToGrades),
                  _buildPremiumAppIcon(
                    'Performance',
                    'combo-chart',
                    _navigateToPerformance,
                  ),
                  _buildPremiumAppIcon(
                    'Exams',
                    'exam',
                    _navigateToExamSchedules,
                  ),
                  if (!_isMobile)
                    _buildPremiumAppIcon(
                      'Profile',
                      'user-male-circle',
                      _showProfileDialog,
                    ),
                  _buildPremiumAppIcon('AI Tutor', 'bot', _navigateToAIChat),
                  _buildPremiumAppIcon('Fees', 'cash-in-hand', _navigateToFees),
                  _buildPremiumAppIcon(
                    'Apply Leave',
                    'exit',
                    _navigateToApplyLeave,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumAppIcon(
    String label,
    String iconName,
    VoidCallback onTap,
  ) {
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: 'https://img.icons8.com/fluency/96/000000/$iconName.png',
                  width: 44,
                  height: 44,
                  errorWidget: (context, url, error) =>
                      const Icon(Icons.apps, color: Colors.grey),
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

  Widget _buildNoticesSection() {
    return StudentNoticesScreen(
      userId: widget.userId,
      schoolCode: widget.schoolCode,
      schoolName: widget.schoolName,
      studentId: widget.userId,
      studentName: _studentName,
    );
  }

  Widget _buildAssignmentsSection() {
    return StudentAssignmentsScreen(
      userId: widget.userId,
      schoolCode: widget.schoolCode,
      schoolName: widget.schoolName,
      studentId: widget.userId,
      studentName: _studentName,
    );
  }

  Widget _buildGradesSection() {
    return StudentGradesScreen(
      userId: widget.userId,
      schoolCode: widget.schoolCode,
      schoolName: widget.schoolName,
      studentId: widget.userId,
      studentName: _studentName,
    );
  }

  Widget _buildProfileItem(String label, String value) {
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

  Widget _buildFullTimetable() {
    final timetableData =
        _timetable?['timetable'] as Map<String, dynamic>? ?? {};
    final days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
    ];
    return SingleChildScrollView(
      child: _isDesktop
          ? _buildDesktopTimetable(timetableData, days)
          : _buildMobileTimetable(timetableData, days),
    );
  }

  Widget _buildDesktopTimetable(
    Map<String, dynamic> timetableData,
    List<String> days,
  ) {
    return Table(
      border: TableBorder.all(color: Colors.grey[300]!),
      columnWidths: const {
        0: FixedColumnWidth(80),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
        4: FlexColumnWidth(),
        5: FlexColumnWidth(),
        6: FlexColumnWidth(),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.blue[50]),
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Period',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            ...days.map(
              (day) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  day[0].toUpperCase() + day.substring(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
        ..._generateTimetableRows(timetableData, days),
      ],
    );
  }

  Widget _buildMobileTimetable(
    Map<String, dynamic> timetableData,
    List<String> days,
  ) {
    return Column(
      children: days.map((day) {
        final dayPeriods = timetableData[day] as List<dynamic>? ?? [];
        if (dayPeriods.isEmpty) return const SizedBox();
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day[0].toUpperCase() + day.substring(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                ...dayPeriods.map((period) {
                  final isBreak = period['type'] == 'break';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isBreak ? Colors.orange[50] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isBreak ? Colors.orange : Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              period['number'].toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                period['subject'] ?? 'No Subject',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                              if (!isBreak && period['teacher_id'] != null)
                                Text(
                                  'Teacher: ${_getTeacherName(period['teacher_id'])}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '${period['start_time']} - ${period['end_time']}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  List<TableRow> _generateTimetableRows(
    Map<String, dynamic> timetableData,
    List<String> days,
  ) {
    int maxPeriods = 0;
    for (var day in days) {
      final dayPeriods = timetableData[day] as List<dynamic>? ?? [];
      if (dayPeriods.length > maxPeriods) maxPeriods = dayPeriods.length;
    }
    List<TableRow> rows = [];
    for (int i = 0; i < maxPeriods; i++) {
      List<Widget> rowCells = [
        Padding(
          padding: const EdgeInsets.all(6.0),
          child: Text('Period ${i + 1}', style: const TextStyle(fontSize: 11)),
        ),
      ];
      for (var day in days) {
        final dayPeriods = timetableData[day] as List<dynamic>? ?? [];
        final period = i < dayPeriods.length ? dayPeriods[i] : null;
        rowCells.add(
          Padding(
            padding: const EdgeInsets.all(6.0),
            child: period != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        period['subject'] ?? 'No Subject',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      if (period['type'] != 'break' &&
                          period['teacher_id'] != null)
                        Text(
                          _getTeacherName(period['teacher_id']),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 2),
                      Text(
                        '${period['start_time']} - ${period['end_time']}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                      if (period['type'] == 'break')
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Break',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  )
                : const Text(
                    '-',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
          ),
        );
      }
      rows.add(TableRow(children: rowCells));
    }
    return rows;
  }
}

// Student Profile Dialog
class StudentProfileDialog extends StatelessWidget {
  final Map<String, dynamic> studentData;
  final String schoolName;
  final String schoolCode;
  final Map<String, dynamic>? schoolData;

  const StudentProfileDialog({
    super.key,
    required this.studentData,
    required this.schoolName,
    required this.schoolCode,
    this.schoolData,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;
    return Dialog(
      insetPadding: isDesktop
          ? const EdgeInsets.symmetric(horizontal: 100, vertical: 50)
          : const EdgeInsets.all(16),
      child: Container(
        constraints: isDesktop
            ? const BoxConstraints(maxWidth: 500, maxHeight: 600)
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
                    'Student Profile',
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
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.blue[100],
                            child: Text(
                              (studentData['username']?[0] ?? 'S')
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            studentData['username'] ?? 'Student',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Student ID: ${studentData['user_id'] ?? 'N/A'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Personal Information'),
                    _buildProfileItem(
                      'Full Name',
                      studentData['full_name'] ?? 'N/A',
                    ),
                    _buildProfileItem('Email', studentData['gmail'] ?? 'N/A'),
                    _buildProfileItem(
                      'Mobile Number',
                      studentData['mobile_number'] ?? 'N/A',
                    ),
                    _buildProfileItem(
                      'Alternate Mobile',
                      studentData['alternate_mobile_number'] ?? 'N/A',
                    ),
                    const SizedBox(height: 16),
                    _buildSectionTitle('School Information'),
                    _buildProfileItem('School Name', schoolName),
                    _buildProfileItem('School Code', schoolCode),
                    if (schoolData?['address'] != null)
                      _buildProfileItem(
                        'School Address',
                        schoolData!['address'],
                      ),
                    _buildProfileItem(
                      'Class',
                      studentData['class_name'] ?? 'N/A',
                    ),
                    _buildProfileItem(
                      'Section',
                      studentData['section'] ?? 'N/A',
                    ),
                    _buildProfileItem(
                      'Roll Number',
                      studentData['roll_number'] ?? 'N/A',
                    ),
                    _buildProfileItem(
                      'Class ID',
                      studentData['class_id'] ?? 'N/A',
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildProfileItem(String label, String value) {
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
}
