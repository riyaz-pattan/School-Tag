// teacher_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import 'attendance_screen.dart';
import 'teacher_notices_screen.dart';
import 'teacher_assignments_screen.dart';
import 'assign_grades_screen.dart';
import 'services/fcm_service.dart';
import 'school_code_screen.dart';
import 'teacher_view_exam_schedule_screen.dart';
import 'messages_screen.dart';
import 'widgets/dashboard_skeleton.dart';

class TeacherDashboardScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  const TeacherDashboardScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  int _currentIndex = 0;
  List<Map<String, dynamic>> _assignedClasses = [];
  List<Map<String, dynamic>> _allClasses = [];
  Map<String, dynamic> _schoolSettings = {};
  Map<String, dynamic> _teacherData = {};
  bool _isLoading = true;
  StreamSubscription<String>? _fcmSubscription;
  String _teacherName = '';
  String? _errorMessage;
  bool _isRefreshing = false;

  // Cache keys
  static const String _teacherDataCacheKey = 'teacher_data';
  static const String _schoolSettingsCacheKey = 'school_settings';
  static const String _allClassesCacheKey = 'all_classes';
  static const String _assignedClassesCacheKey = 'assigned_classes';
  static const String _lastFetchTimeKey = 'last_fetch_time';

  // Cache duration (5 minutes)
  final Duration _cacheDuration = const Duration(minutes: 5);
  late SharedPreferences _prefs;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // Controllers
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
  }

  @override
  void dispose() {
    _fcmSubscription?.cancel();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _currentPasswordController.dispose();
    super.dispose();
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

  Future<void> _loadCachedData() async {
    try {
      // Load teacher data from cache
      final cachedTeacherData = _prefs.getString(
        '${_teacherDataCacheKey}_${widget.userId}',
      );
      if (cachedTeacherData != null) {
        final decodedData = json.decode(cachedTeacherData);
        setState(() {
          _teacherData = Map<String, dynamic>.from(
            _convertFromJsonSerializable(decodedData),
          );
          _teacherName =
              _teacherData['full_name'] ??
              _teacherData['username'] ??
              'Teacher';
        });
      }

      // Load school settings from cache
      final cachedSettings = _prefs.getString(
        '${_schoolSettingsCacheKey}_${widget.schoolCode}',
      );
      if (cachedSettings != null) {
        final decodedData = json.decode(cachedSettings);
        setState(() {
          _schoolSettings = Map<String, dynamic>.from(
            _convertFromJsonSerializable(decodedData),
          );
        });
      }

      // Load all classes from cache
      final cachedAllClasses = _prefs.getString(
        '${_allClassesCacheKey}_${widget.schoolCode}',
      );
      if (cachedAllClasses != null) {
        final decodedData = json.decode(cachedAllClasses);
        setState(() {
          _allClasses = List<Map<String, dynamic>>.from(
            _convertFromJsonSerializable(decodedData),
          );
        });
      }

      // Load assigned classes from cache
      final cachedAssignedClasses = _prefs.getString(
        '${_assignedClassesCacheKey}_${widget.userId}_${widget.schoolCode}',
      );
      if (cachedAssignedClasses != null) {
        final decodedData = json.decode(cachedAssignedClasses);
        setState(() {
          _assignedClasses = List<Map<String, dynamic>>.from(
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
    if (!shouldRefresh &&
        _teacherData.isNotEmpty &&
        _assignedClasses.isNotEmpty) {
      return; // Use cached data if it's still fresh
    }
    try {
      await Future.wait([
        _loadTeacherData(),
        _loadSchoolSettings(),
        _loadAllClasses(),
      ]);
      // Assigned classes should be refreshed more frequently as they affect daily operations
      await _loadAssignedClasses();
      // Update last fetch time
      await _prefs.setInt(_lastFetchTimeKey, now);
    } catch (e) {
      print('Error loading fresh data: $e');
      // Don't show error if we have cached data to display
      if (_teacherData.isEmpty || _assignedClasses.isEmpty) {
        setState(() {
          _errorMessage = 'Failed to load fresh data. Using cached version.';
        });
      }
    }
  }

  Future<void> _initializeFCM() async {
    await FCMService.subscribeToSchool(
      widget.schoolCode,
      widget.userId,
      'teacher',
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

  Future<void> _loadTeacherData() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        setState(() {
          _teacherData = data;
          _teacherName = data['full_name'] ?? data['username'] ?? 'Teacher';
        });
        // Cache the data
        await _prefs.setString(
          '${_teacherDataCacheKey}_${widget.userId}',
          json.encode(_convertToJsonSerializable(data)),
        );
      }
    } catch (e) {
      print('Error loading teacher data: $e');
    }
  }

  Future<void> _loadSchoolSettings() async {
    try {
      DocumentSnapshot settingsDoc;
      // Try to get from settings collection first
      settingsDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('settings')
          .doc('config')
          .get();
      if (!settingsDoc.exists) {
        // Fallback to school document
        settingsDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .get();
      }
      if (settingsDoc.exists) {
        final data = settingsDoc.data() as Map<String, dynamic>? ?? {};
        setState(() {
          _schoolSettings = data;
        });
        // Cache the data
        await _prefs.setString(
          '${_schoolSettingsCacheKey}_${widget.schoolCode}',
          json.encode(_convertToJsonSerializable(data)),
        );
      }
    } catch (e) {
      print('Error loading school settings: $e');
    }
  }

  String _getClassName(String grade, List<dynamic> sections) {
    if (sections.isEmpty) return grade;
    return '$grade (${sections.join(', ')})';
  }

  Future<void> _loadAllClasses() async {
    try {
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();
      final classes = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'className': _getClassName(
            data['grade'] ?? 'Unknown',
            data['sections'] ?? [],
          ),
          'grade': data['grade'],
          'sections': data['sections'],
        };
      }).toList();
      setState(() {
        _allClasses = classes;
      });
      // Cache the data
      await _prefs.setString(
        '${_allClassesCacheKey}_${widget.schoolCode}',
        json.encode(_convertToJsonSerializable(classes)),
      );
    } catch (e) {
      print('Error loading all classes: $e');
    }
  }

  Future<void> _loadAssignedClasses() async {
    try {
      if (mounted) {
        setState(() {
          _isRefreshing = true;
        });
      }
      final timetablesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .get();
      List<Map<String, dynamic>> assignedClasses = [];
      // Process timetables in batches to avoid too many simultaneous requests
      for (var i = 0; i < timetablesSnapshot.docs.length; i += 5) {
        final batch = timetablesSnapshot.docs.sublist(
          i,
          i + 5 > timetablesSnapshot.docs.length
              ? timetablesSnapshot.docs.length
              : i + 5,
        );
        final batchResults = await Future.wait(
          batch.map((timetableDoc) => _processTimetableDoc(timetableDoc)),
        );
        assignedClasses.addAll(
          batchResults
              .where((result) => result != null)
              .cast<Map<String, dynamic>>(),
        );
      }
      if (mounted) {
        setState(() {
          _assignedClasses = assignedClasses;
          _isRefreshing = false;
        });
      }
      // Cache the assigned classes
      await _prefs.setString(
        '${_assignedClassesCacheKey}_${widget.userId}_${widget.schoolCode}',
        json.encode(_convertToJsonSerializable(assignedClasses)),
      );
    } catch (e) {
      print('Error loading assigned classes: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading classes: $e';
          _isRefreshing = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _processTimetableDoc(
    DocumentSnapshot timetableDoc,
  ) async {
    try {
      final timetableData = timetableDoc.data() as Map<String, dynamic>? ?? {};
      final timetable =
          timetableData['timetable'] as Map<String, dynamic>? ?? {};
      final className = timetableData['class_name'] ?? 'Unknown Class';
      final classId = timetableDoc.id;
      final classDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .doc(classId)
          .get();
      if (!classDoc.exists) return null;

      bool isAssigned = false;
      List<String> assignedSubjects = [];
      Map<String, List<String>> dayPeriods = {};
      for (var dayEntry in timetable.entries) {
        final day = dayEntry.key;
        final daySchedule = dayEntry.value as List<dynamic>;
        for (var period in daySchedule) {
          if (period is Map<String, dynamic>) {
            final periodType = period['type'];
            final teacherId = period['teacher_id'];
            final subject = period['subject'];
            final periodNumber = period['number'];
            if (periodType == 'period' && teacherId == widget.userId) {
              isAssigned = true;
              if (subject != null && !assignedSubjects.contains(subject)) {
                assignedSubjects.add(subject);
              }
              if (!dayPeriods.containsKey(day)) {
                dayPeriods[day] = [];
              }
              dayPeriods[day]!.add('Period $periodNumber - $subject');
            }
          }
        }
      }
      if (isAssigned) {
        return {
          'classId': classId,
          'className': className,
          'subjects': assignedSubjects,
          'dayPeriods': dayPeriods,
          'timetableData': timetableData,
          'isFirstPeriodTeacher': _isFirstPeriodTeacher(
            timetable,
            widget.userId,
          ),
        };
      }
    } catch (e) {
      print('Error processing timetable doc: $e');
    }
    return null;
  }

  bool _isFirstPeriodTeacher(Map<String, dynamic> timetable, String teacherId) {
    for (var dayEntry in timetable.entries) {
      final daySchedule = dayEntry.value as List<dynamic>;
      if (daySchedule.isNotEmpty) {
        final firstPeriod = daySchedule.first;
        if (firstPeriod is Map<String, dynamic> &&
            firstPeriod['type'] == 'period' &&
            firstPeriod['teacher_id'] == teacherId) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _forceRefresh() async {
    if (_isRefreshing) return;
    // Clear cache for fresh data
    await _prefs.remove(
      '${_assignedClassesCacheKey}_${widget.userId}_${widget.schoolCode}',
    );
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
        'teacher',
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
      await prefs.remove('${_teacherDataCacheKey}_${widget.userId}');
      await prefs.remove('${_schoolSettingsCacheKey}_${widget.schoolCode}');
      await prefs.remove('${_allClassesCacheKey}_${widget.schoolCode}');
      await prefs.remove(
        '${_assignedClassesCacheKey}_${widget.userId}_${widget.schoolCode}',
      );
      await prefs.remove(_lastFetchTimeKey);
    } catch (e) {
      print('Error clearing shared preferences: $e');
    }
  }

  void _navigateToAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          teacherId: widget.userId,
          teacherName: _teacherName,
          schoolSettings: _schoolSettings,
        ),
      ),
    );
  }

  void _navigateToNotices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeacherNoticesScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          teacherId: widget.userId,
          teacherName: _teacherName,
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
          userRole: 'teacher',
          userName: _teacherName,
        ),
      ),
    );
  }

  void _navigateToAssignments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeacherAssignmentsScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          teacherId: widget.userId,
          teacherName: _teacherName,
        ),
      ),
    );
  }

  void _navigateToAssignGrades() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AssignGradesScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          teacherId: widget.userId,
          teacherName: _teacherName,
        ),
      ),
    );
  }

  void _navigateToExamSchedules() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeacherViewExamScheduleScreen(
          schoolCode: widget.schoolCode,
          userId: widget.userId,
          schoolName: widget.schoolName,
          teacherId: widget.userId,
        ),
      ),
    );
  }

  void _showMyTimetable() {
    List<Map<String, dynamic>> myPeriods = [];

    // Group periods by day first
    Map<String, List<Map<String, dynamic>>> periodsByDay = {};

    for (var classData in _assignedClasses) {
      final timetableData = classData['timetableData'];
      final timetable =
          timetableData['timetable'] as Map<String, dynamic>? ?? {};
      final className = classData['className'];

      for (var dayEntry in timetable.entries) {
        final day = dayEntry.key;
        final daySchedule = dayEntry.value as List<dynamic>;

        for (var period in daySchedule) {
          if (period is Map<String, dynamic> &&
              period['type'] == 'period' &&
              period['teacher_id'] == widget.userId) {
            final periodData = {
              'class': className,
              'day': _capitalizeDay(day),
              'periodNumber': period['number'],
              'subject': period['subject'] ?? 'No Subject',
              'startTime': period['start_time'] ?? 'N/A',
              'endTime': period['end_time'] ?? 'N/A',
              'dayOrder': _getDayOrder(day),
            };

            if (!periodsByDay.containsKey(periodData['day'])) {
              periodsByDay[periodData['day']!] = [];
            }
            periodsByDay[periodData['day']]!.add(periodData);
          }
        }
      }
    }

    // Sort days and periods within each day
    final sortedDays = periodsByDay.keys.toList()
      ..sort((a, b) => _getDayOrder(a).compareTo(_getDayOrder(b)));

    for (var day in sortedDays) {
      periodsByDay[day]!.sort(
        (a, b) =>
            (a['periodNumber'] as int).compareTo(b['periodNumber'] as int),
      );
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.95,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'My Personal Timetable',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'All your assigned periods organized by day',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Summary stats
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  border: Border(bottom: BorderSide(color: Colors.blue[100]!)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildTimetableStat(
                      'Total Days',
                      sortedDays.length.toString(),
                      Icons.calendar_today,
                    ),
                    _buildTimetableStat(
                      'Total Periods',
                      periodsByDay.values
                          .fold(0, (sum, periods) => sum + periods.length)
                          .toString(),
                      Icons.schedule,
                    ),
                    _buildTimetableStat(
                      'Classes',
                      _assignedClasses.length.toString(),
                      Icons.class_,
                    ),
                  ],
                ),
              ),

              // Timetable content
              Expanded(
                child: periodsByDay.isEmpty
                    ? _buildEmptyTimetableState()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: sortedDays.map((day) {
                            final dayPeriods = periodsByDay[day]!;
                            return _buildDaySection(day, dayPeriods);
                          }).toList(),
                        ),
                      ),
              ),

              // Close button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Close Timetable'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to build day sections
  Widget _buildDaySection(String day, List<Map<String, dynamic>> periods) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Day header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  day,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1976D2),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${periods.length} period${periods.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Periods list
          ...periods.map((period) {
            return Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: ListTile(
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'P${period['periodNumber']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1976D2),
                      ),
                    ),
                  ),
                ),
                title: Text(
                  period['subject'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Class: ${period['class']}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      'Time: ${period['startTime']} - ${period['endTime']}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // Helper method for timetable stats
  Widget _buildTimetableStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 20, color: Colors.blue[700]),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1976D2),
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  // Empty state for timetable
  Widget _buildEmptyTimetableState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Periods Assigned',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You currently have no teaching periods assigned in the timetable.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Please contact your school administrator to assign you to classes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get day order for sorting
  int _getDayOrder(String day) {
    const dayOrder = {
      'Monday': 1,
      'Tuesday': 2,
      'Wednesday': 3,
      'Thursday': 4,
      'Friday': 5,
      'Saturday': 6,
      'Sunday': 7,
    };
    return dayOrder[day] ?? 8;
  }

  void _showClassTimetable(Map<String, dynamic> selectedClass) {
    showDialog(
      context: context,
      builder: (context) => ClassTimetableDialog(
        schoolCode: widget.schoolCode,
        classId: selectedClass['id'],
        className: selectedClass['className'],
      ),
    );
  }

  String _capitalizeDay(String day) {
    if (day.isEmpty) return day;
    return "${day[0].toUpperCase()}${day.substring(1).toLowerCase()}";
  }

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

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
        title: Text(_isMobile ? 'Teacher Dashboard' : 'Teacher Dashboard'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 0,
        actions: [
          if (!_isMobile)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.blue),
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
                  icon: Icon(Icons.schedule),
                  label: 'Timetables',
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
                  _teacherName,
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
            leading: const Icon(Icons.schedule, color: Colors.orange),
            title: const Text('Timetables'),
            onTap: () {
              setState(() => _currentIndex = 1);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.green),
            title: const Text('Profile'),
            onTap: () {
              setState(() => _currentIndex = 2);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications, color: Colors.purple),
            title: const Text('Notices'),
            onTap: _navigateToNotices,
          ),

          ListTile(
            leading: const Icon(Icons.message, color: Colors.blueAccent),
            title: const Text('Communication'),
            onTap: _navigateToMessages,
          ),
          ListTile(
            leading: const Icon(Icons.assignment, color: Colors.red),
            title: const Text('Assignments'),
            onTap: _navigateToAssignments,
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
                      _teacherName.isNotEmpty
                          ? _teacherName[0].toUpperCase()
                          : 'T',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 22, 105, 200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _teacherName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromARGB(255, 21, 103, 197),
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
                  _buildSidebarItem(Icons.schedule, 'Timetables', 1),
                  _buildSidebarItem(Icons.person, 'Profile', 2),
                  const SizedBox(height: 16),
                  _buildSidebarActionItem(
                    Icons.notifications,
                    'Notices',
                    _navigateToNotices,
                  ),
                  _buildSidebarActionItem(
                    Icons.assignment,
                    'Assignments',
                    _navigateToAssignments,
                  ),
                  _buildSidebarActionItem(
                    Icons.grade,
                    'Assign Grades',
                    _navigateToAssignGrades,
                  ),
                  _buildSidebarActionItem(
                    Icons.event_note,
                    'Exam Schedules',
                    _navigateToExamSchedules,
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
        style: const TextStyle(color: Color.fromARGB(255, 99, 99, 99)),
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
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
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
        return 'Dashboard Overview';
      case 1:
        return 'Timetables';
      case 2:
        return 'My Profile';
      default:
        return 'Dashboard';
    }
  }

  Widget _getCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return _buildDashboard();
      case 1:
        return _buildTimetablesSection();
      case 2:
        return _buildProfileSection();
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    final attendanceType = _schoolSettings['attendance_type'] ?? 'per_day';
    final attendanceTypeText = _getAttendanceTypeText(attendanceType);

    return Container(
      color: const Color(0xFFF7F9FC), // Very light cool grey background
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
                  horizontal: _isMobile ? 16 : 24,
                  vertical: 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isMobile) _buildStatsRow(attendanceTypeText),
                    if (!_isMobile) _buildTeacherInfoCard(),
                    const SizedBox(height: 32),
                    _buildModernWorkspace(),
                    const SizedBox(height: 32),
                    _buildMyClassesCarousel(),
                    const SizedBox(height: 32),
                    _buildUpcomingLeavesWidget(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingLeavesWidget() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('leave_applications')
          .where('date', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(DateTime.now()))
          .orderBy('date')
          .limit(50)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final assignedClassIds = _assignedClasses.map((c) => c['classId'] as String).toSet();
        
        final leaves = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return assignedClassIds.contains(data['class_id']);
        }).toList();

        if (leaves.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upcoming Student Leaves',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D3A),
              ),
            ),
            const SizedBox(height: 16),
            ...leaves.take(5).map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final dateStr = data['date'] ?? '';
              DateTime? date;
              try { date = DateFormat('yyyy-MM-dd').parse(dateStr); } catch (_) {}
              final formattedDate = date != null ? DateFormat('MMM d').format(date) : dateStr;
              final type = data['type'] ?? 'Other';
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey[100]!),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B6B).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.event_busy_rounded,
                        color: Color(0xFFFF6B6B),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['student_name'] ?? 'Unknown Student',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF2D2D3A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$type • ${data['reason'] ?? ''}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        formattedDate,
                        style: const TextStyle(
                          color: Color(0xFF6C63FF),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildModernHeader() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo[800]!, Colors.blue[600]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(40),
            bottomRight: Radius.circular(40),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_getGreeting()},',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_teacherName 👋',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
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
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.school,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.schoolName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
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
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: const Icon(
                    Icons.person,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
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

  Widget _buildStatsRow(String attendanceTypeText) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _buildStatCard(
            title: 'Assigned Classes',
            value: _assignedClasses.length.toString(),
            icon: Icons.class_,
            color: Colors.purple,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            title: 'Attendance Mode',
            value: attendanceTypeText,
            icon: Icons.check_circle_outline,
            color: Colors.green,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            title: 'School Code',
            value: widget.schoolCode,
            icon: Icons.qr_code,
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildModernWorkspace() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 20),
          child: Text(
            'Workspace',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.grey.withOpacity(0.05)),
          ),
          padding: const EdgeInsets.all(24),
          child: GridView.count(
            crossAxisCount: _isMobile ? 4 : (_isTablet ? 6 : 8),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 16,
            childAspectRatio: MediaQuery.of(context).size.width < 350 ? 0.65 : 0.75,
            children: [
              _buildModernAppIcon(
                'Attendance',
                'checked-user-male',
                _navigateToAttendance,
              ),
              _buildModernAppIcon(
                'Assignments',
                'book-stack',
                _navigateToAssignments,
              ),
              _buildModernAppIcon(
                'Grades',
                'medal',
                _navigateToAssignGrades,
              ),
              _buildModernAppIcon(
                'Notices',
                'megaphone',
                _navigateToNotices,
              ),
              _buildModernAppIcon(
                'Messages',
                'speech-bubble-with-dots',
                _navigateToMessages,
              ),
              _buildModernAppIcon(
                'Exams',
                'exam',
                _navigateToExamSchedules,
              ),
              _buildModernAppIcon(
                'Timetable',
                'calendar',
                _showMyTimetable,
              ),
              _buildModernAppIcon(
                'Settings',
                'settings',
                _showChangePasswordDialog,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModernAppIcon(
    String label,
    String iconName,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
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
                width: 32,
                height: 32,
                errorWidget: (context, url, error) =>
                    const Icon(Icons.error_outline, color: Colors.grey),
              ),
            ),
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    );
  }

  Widget _buildMyClassesCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'My Classes',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                  letterSpacing: -0.5,
                ),
              ),
              if (_assignedClasses.isNotEmpty)
                Text(
                  '${_assignedClasses.length} Total',
                  style: TextStyle(
                    color: Colors.indigo[400],
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ),
        _isRefreshing
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            : _assignedClasses.isEmpty
            ? _buildEmptyClassesState()
            : SizedBox(
                height: 230,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  clipBehavior: Clip.none,
                  itemCount: _assignedClasses.length,
                  itemBuilder: (context, index) {
                    final classData = _assignedClasses[index];
                    return _buildClassCard(classData, index);
                  },
                ),
              ),
      ],
    );
  }

  Widget _buildClassCard(Map<String, dynamic> classData, int index) {
    final rawDayPeriods = classData['dayPeriods'];
    int daysTeaching = 0;
    if (rawDayPeriods is Map) {
      daysTeaching = rawDayPeriods.length;
    }

    // Rotate through some premium gradient colors based on index
    final List<List<Color>> gradients = [
      [Colors.indigo[600]!, Colors.blue[400]!],
      [Colors.purple[600]!, Colors.pink[400]!],
      [Colors.teal[600]!, Colors.green[400]!],
      [Colors.orange[600]!, Colors.deepOrange[400]!],
    ];
    final classGradient = gradients[index % gradients.length];

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: classGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: classGradient[0].withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Icon(
              Icons.school,
              size: 120,
              color: Colors.white.withOpacity(0.1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.4)),
                  ),
                  child: const Text(
                    'Scheduled Class',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  classData['className'] ?? 'Unknown Class',
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
                if (classData['subjects'] != null &&
                    (classData['subjects'] as List).isNotEmpty)
                  Text(
                    (classData['subjects'] as List).join(', '),
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
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Teaching $daysTeaching day(s)',
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
  }

  Widget _buildEmptyClassesState() {
    return Container(
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
                Icons.class_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No classes assigned yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Contact admin to get assigned to a class.',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
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
          colors: [Colors.indigo[800]!, Colors.blue[600]!],
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
                  '${_getGreeting()}, $_teacherName!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage your classes and responsibilities efficiently',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ],
            ),
          ),
          Icon(Icons.person, size: 80, color: Colors.white.withOpacity(0.2)),
        ],
      ),
    );
  }

  Widget _buildTeacherInfoCard() {
    final attendanceType = _schoolSettings['attendance_type'] ?? 'per_day';
    final attendanceTypeText = _getAttendanceTypeText(attendanceType);
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
                  child: Icon(
                    Icons.person_outline,
                    size: 28,
                    color: Colors.indigo[700],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _teacherName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo[800],
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Text(
                      'School Code:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
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
                    width: 100,
                    child: Text(
                      'Role:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  Text('Teacher', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment, size: 18, color: Colors.indigo[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Attendance: $attendanceTypeText',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo[800],
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

  Widget _buildTimetablesSection() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 32 : 16,
        vertical: _isDesktop ? 24 : 16,
      ),
      child: Column(
        children: [
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    'My Personal Timetable',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'View all your assigned periods in one place',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _assignedClasses.isNotEmpty
                        ? _showMyTimetable
                        : null,
                    icon: const Icon(Icons.schedule),
                    label: const Text('My Timetable'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'View Class Timetables',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select a class to view its complete timetable',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  _buildClassTimetableSelector(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 32 : 16,
        vertical: _isDesktop ? 24 : 16,
      ),
      child: Column(
        children: [
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      _teacherName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _teacherName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Teacher',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personal Information',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildProfileItem(
                    'Full Name',
                    _teacherData['full_name'] ?? 'Not set',
                  ),
                  _buildProfileItem(
                    'Username',
                    _teacherData['username'] ?? 'Not set',
                  ),
                  _buildProfileItem(
                    'Email',
                    _teacherData['gmail'] ?? 'Not set',
                  ),
                  _buildProfileItem(
                    'Mobile',
                    _teacherData['mobile_number'] ?? 'Not set',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'School Information',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildProfileItem('School Name', widget.schoolName),
                  _buildProfileItem('School Code', widget.schoolCode),

                  _buildProfileItem(
                    'Status',
                    _teacherData['status'] ?? 'active',
                  ),
                  _buildProfileItem('Role', _teacherData['role'] ?? 'teacher'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
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

  Widget _buildClassTimetableSelector() {
    if (_allClasses.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Text(
            'No timetables available for any class',
            style: TextStyle(color: Colors.grey),
          );
        }
        final timetables = snapshot.data!.docs;
        final availableClasses = _allClasses.where((classData) {
          return timetables.any((timetable) => timetable.id == classData['id']);
        }).toList();
        if (availableClasses.isEmpty) {
          return const Text(
            'No timetables available for any class',
            style: TextStyle(color: Colors.grey),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Class:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<Map<String, dynamic>>(
                isExpanded: true,
                underline: const SizedBox(),
                value: null,
                items: availableClasses.map((classData) {
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: classData,
                    child: Text(
                      classData['className'],
                      style: const TextStyle(fontSize: 16),
                    ),
                  );
                }).toList(),
                onChanged: (selectedClass) {
                  if (selectedClass != null) {
                    _showClassTimetable(selectedClass);
                  }
                },
                hint: const Text(
                  'Choose a class...',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _getAttendanceTypeText(String attendanceType) {
    switch (attendanceType) {
      case 'per_period':
        return 'Per Period';
      case 'per_day_twice':
        return 'Per Day (Twice)';
      case 'per_day':
      default:
        return 'Per Day';
    }
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
}

// Keep only ClassTimetableDialog and DiagonalLinePainter as they are used in the timetable section
class ClassTimetableDialog extends StatefulWidget {
  final String schoolCode;
  final String classId;
  final String className;
  const ClassTimetableDialog({
    super.key,
    required this.schoolCode,
    required this.classId,
    required this.className,
  });

  @override
  State<ClassTimetableDialog> createState() => _ClassTimetableDialogState();
}

class _ClassTimetableDialogState extends State<ClassTimetableDialog> {
  Map<String, dynamic>? _timetableData;
  bool _isLoading = true;
  String? _errorMessage;

  // Cache for timetable
  late SharedPreferences _prefs;
  static const String _timetableCacheKey = 'timetable_cache';

  // Helper methods for JSON conversion (same as above)
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

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadTimetable();
  }

  Future<void> _loadTimetable() async {
    try {
      // Try to load from cache first
      final cachedTimetable = _prefs.getString(
        '${_timetableCacheKey}_${widget.schoolCode}_${widget.classId}',
      );
      if (cachedTimetable != null) {
        final decodedData = json.decode(cachedTimetable);
        setState(() {
          _timetableData = Map<String, dynamic>.from(
            _convertFromJsonSerializable(decodedData),
          );
          _isLoading = false;
        });
      }
      // Then load from network
      final timetableDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .doc(widget.classId)
          .get();
      if (timetableDoc.exists) {
        final data = timetableDoc.data()!;
        setState(() {
          _timetableData = data;
          _isLoading = false;
        });
        // Cache the timetable
        await _prefs.setString(
          '${_timetableCacheKey}_${widget.schoolCode}_${widget.classId}',
          json.encode(_convertToJsonSerializable(data)),
        );
      } else {
        setState(() {
          _errorMessage = 'No timetable found for this class';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading timetable: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _sortScheduleByTime(
    List<Map<String, dynamic>> schedule,
  ) {
    List<Map<String, dynamic>> sortedSchedule = List.from(schedule);
    sortedSchedule.sort((a, b) {
      try {
        final timeFormat = DateFormat.jm();
        final aTime = timeFormat.parse(a['start_time']);
        final bTime = timeFormat.parse(b['start_time']);
        return aTime.compareTo(bTime);
      } catch (e) {
        try {
          final timeFormat = DateFormat.Hm();
          final aTime = timeFormat.parse(a['start_time']);
          final bTime = timeFormat.parse(b['start_time']);
          return aTime.compareTo(bTime);
        } catch (e) {
          return 0;
        }
      }
    });
    return sortedSchedule;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text('Timetable - ${widget.className}'),
              backgroundColor: Colors.blue[700],
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? Center(child: Text(_errorMessage!))
                  : _timetableData == null
                  ? const Center(child: Text('No timetable data available.'))
                  : _buildTimetableGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetableGrid() {
    final timetable = _timetableData!;
    final isUniform = timetable['is_uniform'] ?? true;
    final timetableData = timetable['timetable'] as Map<String, dynamic>? ?? {};
    final workingDays = List<String>.from(
      timetable['working_days'] ??
          ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
    );
    List<Map<String, dynamic>> dailySchedule = [];
    if (isUniform && timetableData.isNotEmpty) {
      dailySchedule = List<Map<String, dynamic>>.from(
        timetableData.values.first,
      );
    } else if (timetableData.isNotEmpty) {
      dailySchedule = List<Map<String, dynamic>>.from(
        timetableData.values.first,
      );
    }
    if (dailySchedule.isEmpty) {
      return const Center(child: Text('No schedule configured'));
    }
    final sortedSchedule = _sortScheduleByTime(dailySchedule);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            border: TableBorder.all(color: Colors.grey[300]!),
            defaultColumnWidth: const FixedColumnWidth(150),
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.blue[50]),
                children: [
                  _buildDiagonalSplitCell(),
                  ...sortedSchedule.asMap().entries.map((entry) {
                    final index = entry.key;
                    final slot = entry.value;
                    return Container(
                      height: 80,
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${slot['type'] == 'period' ? 'Period ${slot['number']}' : slot['name'] ?? 'Break'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${slot['start_time']}',
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            '${slot['end_time']}',
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
              ...workingDays.map((day) {
                final dayKey = day.toLowerCase();
                return TableRow(
                  decoration: BoxDecoration(
                    color: workingDays.indexOf(day) % 2 == 0
                        ? Colors.white
                        : Colors.grey[50],
                  ),
                  children: [
                    Container(
                      height: 80,
                      padding: const EdgeInsets.all(12.0),
                      child: Center(
                        child: Text(
                          day.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    ...sortedSchedule.asMap().entries.map((entry) {
                      final index = entry.key;
                      final periodData = isUniform
                          ? entry.value
                          : (timetableData[dayKey] as List<dynamic>? ??
                                    [])[index] ??
                                entry.value;
                      return Container(
                        height: 80,
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (periodData['type'] == 'period') ...[
                              Text(
                                periodData['subject'] ?? 'No Subject',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                periodData['teacher_name'] ?? 'Unassigned',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontStyle: periodData['teacher_name'] == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ] else
                              Text(
                                periodData['name'] ?? 'BREAK',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiagonalSplitCell() {
    return Container(
      height: 80,
      child: Stack(
        children: [
          CustomPaint(
            size: const Size(150, 80),
            painter: DiagonalLinePainter(),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, right: 8.0),
              child: Text(
                'PERIODS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0, left: 8.0),
              child: Text(
                'DAYS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DiagonalLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
