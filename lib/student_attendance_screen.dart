import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'student_dashboard_screen.dart';

class StudentAttendanceScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String studentId;
  final String studentName;
  final String? classId;
  final String? section;
  final String userId;

  const StudentAttendanceScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.studentId,
    required this.studentName,
    required this.classId,
    required this.section,
    required this.userId,
  });

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _dailyAttendance = [];
  Map<String, dynamic> _attendanceSummary = {};
  bool _isLoading = true;
  bool _isInitialLoad = true;
  String? _errorMessage;
  String? _className;
  String? _attendanceType;

  // Cache for attendance data
  List<Map<String, dynamic>> _cachedAttendanceRecords = [];
  DateTime? _lastFetchTime;
  SharedPreferences? _prefs;

  // Caching keys
  static const String _settingsCacheKey = 'school_settings';
  static const String _studentCacheKey = 'student_data';
  static const String _attendanceCacheKey = 'attendance_data';

  // Firebase read counter
  int _firebaseReads = 0;

  // Subject-wise attendance for per_period type
  Map<String, Map<String, dynamic>> _subjectWiseAttendance = {};

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  void initState() {
    super.initState();
    _initializeAttendanceSummary();
    _initSharedPreferences();
  }

  // Get academic year start and end dates (June to May)
  Map<String, DateTime> _getAcademicYearDates() {
    final now = DateTime.now();
    DateTime academicYearStart;
    DateTime academicYearEnd;

    if (now.month >= 6) {
      // Current year June to next year May
      academicYearStart = DateTime(now.year, 6, 1);
      academicYearEnd = DateTime(now.year + 1, 5, 31);
    } else {
      // Previous year June to current year May
      academicYearStart = DateTime(now.year - 1, 6, 1);
      academicYearEnd = DateTime(now.year, 5, 31);
    }

    return {'start': academicYearStart, 'end': academicYearEnd};
  }

  String _getAcademicYearText() {
    final dates = _getAcademicYearDates();
    final startYear = dates['start']!.year;
    final endYear = dates['end']!.year;
    return 'Academic Year: ${startYear}-${endYear}';
  }

  void _logRead(String collection, {String? docId}) {
    _firebaseReads++;
    print(
      '🔥 FIREBASE READ #$_firebaseReads: $collection${docId != null ? '/$docId' : ''}',
    );
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadClassName();
    _loadSchoolSettings().then((_) {
      _loadAttendanceData();
    });
  }

  // Helper method to convert data for caching (remove Timestamp objects)
  Map<String, dynamic> _prepareDataForCache(Map<String, dynamic> data) {
    final preparedData = Map<String, dynamic>.from(data);

    // Convert Timestamp to milliseconds since epoch for caching
    preparedData.forEach((key, value) {
      if (value is Timestamp) {
        preparedData[key] = value.millisecondsSinceEpoch;
      }
    });

    return preparedData;
  }

  // Helper method to restore data from cache (convert milliseconds back to DateTime)
  Map<String, dynamic> _restoreDataFromCache(Map<String, dynamic> data) {
    final restoredData = Map<String, dynamic>.from(data);

    // Convert milliseconds back to DateTime
    restoredData.forEach((key, value) {
      if (value is int &&
          (key.contains('time') ||
              key.contains('at') ||
              key.contains('date'))) {
        restoredData[key] = DateTime.fromMillisecondsSinceEpoch(value);
      }
    });

    return restoredData;
  }

  Future<void> _saveToCache(
    String key,
    dynamic data, {
    Duration maxAge = const Duration(hours: 1),
  }) async {
    // Prepare data for caching by converting Timestamps
    dynamic preparedData = data;
    if (data is Map<String, dynamic>) {
      preparedData = _prepareDataForCache(data);
    } else if (data is List) {
      preparedData = data.map((item) {
        if (item is Map<String, dynamic>) {
          return _prepareDataForCache(item);
        }
        return item;
      }).toList();
    }

    final cacheData = {
      'data': preparedData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'maxAge': maxAge.inMilliseconds,
    };

    if (_prefs != null) {
      try {
        await _prefs!.setString(key, json.encode(cacheData));
      } catch (e) {
        print('Error saving to persistent cache: $e');
      }
    }
  }

  dynamic _getFromCache(String key) {
    if (_prefs == null) return null;

    try {
      final cachedString = _prefs!.getString(key);
      if (cachedString != null) {
        final cacheData = json.decode(cachedString);
        final timestamp = cacheData['timestamp'] as int? ?? 0;
        final maxAge =
            cacheData['maxAge'] as int? ??
            const Duration(hours: 1).inMilliseconds;
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;

        if (age <= maxAge) {
          print('📦 CACHE HIT: $key');
          final data = cacheData['data'];

          // Restore data from cache by converting back from milliseconds
          if (data is Map<String, dynamic>) {
            return _restoreDataFromCache(data);
          } else if (data is List) {
            return data.map((item) {
              if (item is Map<String, dynamic>) {
                return _restoreDataFromCache(item);
              }
              return item;
            }).toList();
          }
          return data;
        } else {
          _prefs!.remove(key);
        }
      }
    } catch (e) {
      print('Error reading from cache: $e');
      _prefs!.remove(key);
    }

    return null;
  }

  void _initializeAttendanceSummary() {
    setState(() {
      _attendanceSummary = {
        'total': 0,
        'present': 0,
        'absent': 0,
        'percentage': 0.0,
      };
    });
  }

  Future<void> _loadSchoolSettings() async {
    final cacheKey = '${_settingsCacheKey}_${widget.schoolCode}';
    final cachedSettings = _getFromCache(cacheKey);

    if (cachedSettings != null) {
      setState(() {
        _attendanceType = _normalizeAttendanceType(
          cachedSettings['attendance_type']?.toString(),
        );
      });
      return;
    }

    try {
      _logRead('schools/${widget.schoolCode}/settings/config');
      final settingsDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('settings')
          .doc('config')
          .get();

      if (settingsDoc.exists) {
        final data = settingsDoc.data();
        await _saveToCache(cacheKey, data, maxAge: const Duration(hours: 24));
        setState(() {
          _attendanceType = _normalizeAttendanceType(
            data?['attendance_type']?.toString(),
          );
        });
      } else {
        setState(() {
          _attendanceType = 'per_period';
        });
      }
    } catch (e) {
      print('Error loading school settings: $e');
      setState(() {
        _attendanceType = 'per_period';
      });
    }
  }

  String _normalizeAttendanceType(String? val) {
    if (val == null) return 'per_period';
    final v = val.toLowerCase().trim();
    if (v == 'per_day' || v.contains('once')) return 'per_day_once';
    if (v == 'per_day_twice' || v.contains('twice')) return 'per_day_twice';
    if (v == 'per_period' || v.contains('period')) return 'per_period';
    return 'per_period';
  }

  bool get _isPerDayOnce => _attendanceType == 'per_day_once';
  bool get _isPerDayTwice => _attendanceType == 'per_day_twice';
  bool get _isPerPeriod => _attendanceType == 'per_period';

  Future<void> _loadClassName() async {
    final cacheKey = '${_studentCacheKey}_${widget.studentId}';
    final cachedStudent = _getFromCache(cacheKey);

    if (cachedStudent != null) {
      setState(() {
        _className = cachedStudent['class_name'] ?? 'Unknown Class';
      });
      return;
    }

    try {
      _logRead('users/${widget.studentId}');
      final studentDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.studentId)
          .get();

      if (studentDoc.exists) {
        final studentData = studentDoc.data();
        await _saveToCache(
          cacheKey,
          studentData,
          maxAge: const Duration(hours: 24),
        );
        setState(() {
          _className = studentData?['class_name'] ?? 'Unknown Class';
        });
      }
    } catch (e) {
      print('Error loading class name: $e');
      setState(() {
        _className = 'Unknown Class';
      });
    }
  }

  Future<void> _loadAttendanceData() async {
    if (widget.classId == null) {
      setState(() {
        _errorMessage = 'You are not assigned to any class';
        _isLoading = false;
        _isInitialLoad = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load attendance for selected date
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final dailyCacheKey =
          '${_attendanceCacheKey}_daily_${widget.studentId}_$dateStr';

      final cachedDailyAttendance = _getFromCache(dailyCacheKey);
      if (cachedDailyAttendance != null) {
        setState(() {
          _dailyAttendance = List<Map<String, dynamic>>.from(
            cachedDailyAttendance,
          );
        });
      } else {
        _logRead('users/${widget.studentId}/attendance (query)');
        final attendanceSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.studentId)
            .collection('attendance')
            .where('date', isEqualTo: dateStr)
            .orderBy('period_number')
            .get();

        final dailyAttendance = attendanceSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'period_number': data['period_number'],
            'subject': data['subject'] ?? 'Unknown',
            'status': data['status'] ?? 'absent',
            'marked_by': data['marked_by_teacher_name'] ?? 'Unknown',
            'time': data['marked_at'] != null
                ? DateFormat(
                    'HH:mm',
                  ).format((data['marked_at'] as Timestamp).toDate())
                : 'N/A',
          };
        }).toList();

        await _saveToCache(
          dailyCacheKey,
          dailyAttendance,
          maxAge: const Duration(hours: 2),
        );
        setState(() {
          _dailyAttendance = dailyAttendance;
        });
      }

      // Load attendance summary with caching - NOW USING ACADEMIC YEAR
      await _loadAttendanceSummaryWithCache();
    } catch (e) {
      print('Error loading attendance data: $e');
      setState(() {
        _errorMessage =
            'Error loading attendance data. Please check your internet connection.';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isInitialLoad = false;
      });
    }
  }

  Future<void> _loadAttendanceSummaryWithCache() async {
    try {
      // Get academic year dates (June to May)
      final academicYearDates = _getAcademicYearDates();
      final startDateStr = DateFormat(
        'yyyy-MM-dd',
      ).format(academicYearDates['start']!);
      final endDateStr = DateFormat(
        'yyyy-MM-dd',
      ).format(academicYearDates['end']!);

      final academicYearCacheKey =
          '${_attendanceCacheKey}_academic_${widget.studentId}_${academicYearDates['start']!.year}_${academicYearDates['end']!.year}';

      List<Map<String, dynamic>> allRecords;
      final cachedAcademicYear = _getFromCache(academicYearCacheKey);

      if (cachedAcademicYear != null) {
        allRecords = List<Map<String, dynamic>>.from(cachedAcademicYear);
        _cachedAttendanceRecords = allRecords;
        _lastFetchTime = DateTime.now();
      } else {
        // First time - fetch all records for current academic year
        print('Fetching all attendance records for academic year...');
        allRecords = await _fetchAttendanceRecords(startDateStr, endDateStr);
        await _saveToCache(
          academicYearCacheKey,
          allRecords,
          maxAge: const Duration(hours: 4),
        );
        _cachedAttendanceRecords = allRecords;
        _lastFetchTime = DateTime.now();
      }

      // Calculate summary from records based on attendance type
      _calculateAttendanceSummaryByType(allRecords);
    } catch (e) {
      print('Error loading attendance summary: $e');
      // Fallback: calculate with empty data
      _calculateAttendanceSummaryByType([]);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAttendanceRecords(
    String startDate,
    String endDate,
  ) async {
    try {
      _logRead('users/${widget.studentId}/attendance (query)');
      final attendanceSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.studentId)
          .collection('attendance')
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .get();

      return attendanceSnapshot.docs.map((doc) {
        final data = doc.data();
        // Remove marked_at because it contains Timestamp which causes serialization issues
        final cleanData = Map<String, dynamic>.from(data);
        cleanData.remove('marked_at');
        return cleanData;
      }).toList();
    } catch (e) {
      print('Error fetching attendance records: $e');
      return [];
    }
  }

  void _calculateAttendanceSummaryByType(
    List<Map<String, dynamic>> allRecords,
  ) {
    if (allRecords.isEmpty) {
      setState(() {
        _attendanceSummary = {
          'total': 0,
          'present': 0,
          'absent': 0,
          'percentage': 0.0,
        };
        _subjectWiseAttendance = {};
      });
      return;
    }

    if (_isPerPeriod) {
      _calculatePerPeriodSummary(allRecords);
    } else if (_isPerDayOnce) {
      _calculatePerDayOnceSummary(allRecords);
    } else if (_isPerDayTwice) {
      _calculatePerDayTwiceSummary(allRecords);
    }
  }

  void _calculatePerPeriodSummary(List<Map<String, dynamic>> allRecords) {
    // For per_period: Count each period individually
    final totalPeriods = allRecords.length;
    final presentPeriods = allRecords
        .where((record) => record['status'] == 'present')
        .length;
    final absentPeriods = totalPeriods - presentPeriods;
    final percentage = totalPeriods > 0
        ? (presentPeriods / totalPeriods * 100)
        : 0.0;

    // Calculate subject-wise attendance
    _calculateSubjectWiseAttendance(allRecords);

    setState(() {
      _attendanceSummary = {
        'total': totalPeriods,
        'present': presentPeriods,
        'absent': absentPeriods,
        'percentage': percentage,
        'type': 'periods',
      };
    });
  }

  void _calculatePerDayOnceSummary(List<Map<String, dynamic>> allRecords) {
    // For per_day_once: Only the first period of each day counts
    final uniqueDates = <String, Map<String, dynamic>>{};

    for (var record in allRecords) {
      final date = record['date'];
      final periodNumber =
          int.tryParse(record['period_number']?.toString() ?? '0') ?? 0;

      if (!uniqueDates.containsKey(date)) {
        uniqueDates[date] = {
          'period_number': periodNumber,
          'status': record['status'],
        };
      } else {
        // Keep only the earliest period for each day
        final existingPeriod = uniqueDates[date]!['period_number'] as int;
        if (periodNumber < existingPeriod) {
          uniqueDates[date] = {
            'period_number': periodNumber,
            'status': record['status'],
          };
        }
      }
    }

    final totalDays = uniqueDates.length;
    final presentDays = uniqueDates.values
        .where((day) => day['status'] == 'present')
        .length;
    final absentDays = totalDays - presentDays;
    final percentage = totalDays > 0 ? (presentDays / totalDays * 100) : 0.0;

    setState(() {
      _attendanceSummary = {
        'total': totalDays,
        'present': presentDays,
        'absent': absentDays,
        'percentage': percentage,
        'type': 'days',
      };
    });
  }

  void _calculatePerDayTwiceSummary(List<Map<String, dynamic>> allRecords) {
    // For per_day_twice: Count all periods (since each period is marked separately)
    final totalPeriods = allRecords.length;
    final presentPeriods = allRecords
        .where((record) => record['status'] == 'present')
        .length;
    final absentPeriods = totalPeriods - presentPeriods;
    final percentage = totalPeriods > 0
        ? (presentPeriods / totalPeriods * 100)
        : 0.0;

    setState(() {
      _attendanceSummary = {
        'total': totalPeriods,
        'present': presentPeriods,
        'absent': absentPeriods,
        'percentage': percentage,
        'type': 'periods',
      };
    });
  }

  void _calculateSubjectWiseAttendance(List<Map<String, dynamic>> allRecords) {
    final subjectStats = <String, Map<String, int>>{};

    for (var record in allRecords) {
      final subject = record['subject'] ?? 'Unknown';
      final status = record['status'];

      if (!subjectStats.containsKey(subject)) {
        subjectStats[subject] = {'total': 0, 'present': 0};
      }

      subjectStats[subject]!['total'] = subjectStats[subject]!['total']! + 1;
      if (status == 'present') {
        subjectStats[subject]!['present'] =
            subjectStats[subject]!['present']! + 1;
      }
    }

    // Convert to percentage format
    final subjectWise = <String, Map<String, dynamic>>{};
    for (var entry in subjectStats.entries) {
      final subject = entry.key;
      final stats = entry.value;
      final percentage = stats['total']! > 0
          ? (stats['present']! / stats['total']! * 100)
          : 0.0;

      subjectWise[subject] = {
        'total': stats['total'],
        'present': stats['present'],
        'absent': stats['total']! - stats['present']!,
        'percentage': percentage,
      };
    }

    setState(() {
      _subjectWiseAttendance = subjectWise;
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _isLoading = true;
      });
      _loadAttendanceData();
    }
  }

  Color _getStatusColor(String status) {
    return status == 'present' ? Colors.green : Colors.red;
  }

  IconData _getStatusIcon(String status) {
    return status == 'present' ? Icons.check_circle : Icons.cancel;
  }

  void _retryLoading() {
    setState(() {
      _isLoading = true;
      _isInitialLoad = true;
    });
    _loadAttendanceData();
  }

  String _getAttendanceTypeDescription() {
    switch (_attendanceType) {
      case 'per_day_once':
        return 'Daily Attendance (One Period Only)';
      case 'per_day_twice':
        return 'Daily Attendance (Two Periods)';
      case 'per_period':
        return 'Period-wise Attendance';
      default:
        return 'Period-wise Attendance';
    }
  }

  Future<void> _refreshData() async {
    // Clear cache to force fresh data fetch
    final academicYearDates = _getAcademicYearDates();
    final academicYearCacheKey =
        '${_attendanceCacheKey}_academic_${widget.studentId}_${academicYearDates['start']!.year}_${academicYearDates['end']!.year}';
    final dailyCacheKey =
        '${_attendanceCacheKey}_daily_${widget.studentId}_${DateFormat('yyyy-MM-dd').format(_selectedDate)}';

    if (_prefs != null) {
      await _prefs!.remove(academicYearCacheKey);
      await _prefs!.remove(dailyCacheKey);
    }

    _cachedAttendanceRecords.clear();
    _lastFetchTime = null;
    await _loadAttendanceData();
  }

  // Desktop Layout
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar with auto-slide
        _AttendanceInfoSidebar(
          schoolName: widget.schoolName,
          studentName: widget.studentName,
          className: _className,
          section: widget.section,
          academicYear: _getAcademicYearText(),
          attendanceType: _getAttendanceTypeDescription(),
        ),
        // Main Content
        Expanded(
          child: Column(
            children: [
              _buildDesktopTopBar(),
              Expanded(child: _buildMainContent()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: Colors.white,
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Color.fromARGB(255, 33, 150, 243),
            ),
            onPressed: () {
              Navigator.of(
                context,
              ).pop(); // Changed from pushAndRemoveUntil to simple pop
            },
            tooltip: 'Back to Dashboard',
          ),
          const Text(
            'My Attendance',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 33, 150, 243),
            ),
          ),
          const Spacer(),
          // Academic Year Info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[100]!),
            ),
            child: Text(
              _getAcademicYearText(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color.fromARGB(255, 33, 150, 243),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _refreshData,
            tooltip: 'Refresh Attendance',
          ),
        ],
      ),
    );
  }

  // Mobile/Tablet Layout
  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${widget.schoolName} - Attendance',
                style: TextStyle(fontSize: _isDesktop ? 20 : 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Color.fromARGB(255, 33, 150, 243),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh Attendance',
          ),
        ],
      ),
      body: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading && _isInitialLoad) {
      return _buildLoadingState();
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Messages
          if (_errorMessage != null) _buildMessage(_errorMessage!, true),
          const SizedBox(height: 16),

          // Student Info Card for mobile/tablet
          if (!_isDesktop) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue[100],
                        child: Text(
                          widget.studentName[0].toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.studentName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Class: ${_className ?? 'Unknown'}${widget.section != null ? ' - ${widget.section}' : ''}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _getAcademicYearText(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Attendance Summary Card
          Padding(
            padding: _isDesktop
                ? const EdgeInsets.fromLTRB(24, 16, 24, 16)
                : const EdgeInsets.symmetric(horizontal: 16),
            child: _buildAttendanceSummaryCard(),
          ),

          const SizedBox(height: 16),

          // Subject-wise Attendance (for per_period only)
          if (_isPerPeriod && _subjectWiseAttendance.isNotEmpty)
            Padding(
              padding: _isDesktop
                  ? const EdgeInsets.fromLTRB(24, 0, 24, 16)
                  : const EdgeInsets.symmetric(horizontal: 16),
              child: _buildSubjectWiseAttendanceCard(),
            ),

          const SizedBox(height: 16),

          // Date Selection Card
          Padding(
            padding: _isDesktop
                ? const EdgeInsets.fromLTRB(24, 0, 24, 16)
                : const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Date',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.calendar_today,
                          color: Colors.blue[700],
                        ),
                      ),
                      title: const Text(
                        'View Attendance For',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        DateFormat('MMMM d, yyyy').format(_selectedDate),
                        style: const TextStyle(fontSize: 16),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.edit_calendar,
                          color: Colors.blue,
                        ),
                        onPressed: _selectDate,
                      ),
                      onTap: _selectDate,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Daily Attendance List
          Padding(
            padding: _isDesktop
                ? const EdgeInsets.fromLTRB(24, 0, 24, 24)
                : const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily Attendance',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                if (_errorMessage != null)
                  _buildMessage(_errorMessage!, true)
                else if (_dailyAttendance.isEmpty)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(
                        child: Text(
                          'No attendance records found for selected date',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  )
                else
                  ..._dailyAttendance.map(
                    (attendance) => Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                              attendance['status'],
                            ).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _getStatusColor(attendance['status']),
                            ),
                          ),
                          child: Icon(
                            _getStatusIcon(attendance['status']),
                            color: _getStatusColor(attendance['status']),
                          ),
                        ),
                        title: Text(
                          'Period ${attendance['period_number']} - ${attendance['subject']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Status: ${attendance['status'].toString().toUpperCase()}',
                              style: TextStyle(
                                color: _getStatusColor(attendance['status']),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text('Marked by: ${attendance['marked_by']}'),
                            if (attendance['time'] != 'N/A')
                              Text('Time: ${attendance['time']}'),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceSummaryCard() {
    final percentage = (_attendanceSummary['percentage'] ?? 0.0).toDouble();
    final type = _attendanceSummary['type'] ?? 'periods';
    final total = _attendanceSummary['total'] ?? 0;
    final present = _attendanceSummary['present'] ?? 0;
    final absent = _attendanceSummary['absent'] ?? 0;

    Color getPercentageColor(double percentage) {
      if (percentage >= 75) return Colors.green;
      if (percentage >= 50) return Colors.orange;
      return Colors.red;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Percentage Circle
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: percentage / 100,
                    strokeWidth: 12,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      getPercentageColor(percentage),
                    ),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Attendance',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Stats Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: _isMobile ? 0.9 : 1.2,
              children: [
                _buildStatItem(
                  type == 'days' ? 'Total Days' : 'Total Periods',
                  total.toString(),
                  type == 'days' ? Icons.calendar_today : Icons.schedule,
                  Colors.blue,
                ),
                _buildStatItem(
                  type == 'days' ? 'Present Days' : 'Present Periods',
                  present.toString(),
                  Icons.check_circle,
                  Colors.green,
                ),
                _buildStatItem(
                  type == 'days' ? 'Absent Days' : 'Absent Periods',
                  absent.toString(),
                  Icons.cancel,
                  Colors.red,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Additional Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getAttendanceTypeDescription(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _buildSubjectWiseAttendanceCard() {
    // Sort subjects by percentage (highest first)
    final sortedSubjects = _subjectWiseAttendance.entries.toList()
      ..sort((a, b) => b.value['percentage'].compareTo(a.value['percentage']));

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subject-wise Attendance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...sortedSubjects.map((entry) {
              final subject = entry.key;
              final stats = entry.value;
              final percentage = (stats['percentage'] as double).toDouble();
              final present = stats['present'] as int;
              final total = stats['total'] as int;

              Color getPercentageColor(double percentage) {
                if (percentage >= 75) return Colors.green;
                if (percentage >= 50) return Colors.orange;
                return Colors.red;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Present: $present/$total periods',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: getPercentageColor(percentage).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: getPercentageColor(percentage),
                        ),
                      ),
                      child: Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: getPercentageColor(percentage),
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
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            color: Color.fromARGB(255, 33, 150, 243),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading Attendance...',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String message, bool isError) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? Colors.red[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? Colors.red[200]! : Colors.green[200]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red[700] : Colors.green[700],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red[700] : Colors.green[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() {
              _errorMessage = null;
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(body: _buildDesktopLayout());
    } else {
      return _buildMobileTabletLayout();
    }
  }
}

// Separate StatefulWidget for sidebar to isolate its state
class _AttendanceInfoSidebar extends StatefulWidget {
  final String schoolName;
  final String studentName;
  final String? className;
  final String? section;
  final String academicYear;
  final String attendanceType;

  const _AttendanceInfoSidebar({
    required this.schoolName,
    required this.studentName,
    required this.className,
    required this.section,
    required this.academicYear,
    required this.attendanceType,
  });

  @override
  State<_AttendanceInfoSidebar> createState() => _AttendanceInfoSidebarState();
}

class _AttendanceInfoSidebarState extends State<_AttendanceInfoSidebar> {
  final PageController _infoPageController = PageController();
  int _currentInfoPage = 0;
  Timer? _autoSlideTimer;

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  @override
  void dispose() {
    _stopAutoSlide();
    _infoPageController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_infoPageController.hasClients) {
        final nextPage = (_currentInfoPage + 1) % 2; // Only 2 pages
        _infoPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _stopAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
  }

  void _nextInfoPage() {
    if (_infoPageController.hasClients) {
      final nextPage = (_currentInfoPage + 1) % 2;
      _infoPageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousInfoPage() {
    if (_infoPageController.hasClients) {
      final previousPage = (_currentInfoPage - 1) % 2;
      _infoPageController.animateToPage(
        previousPage < 0 ? 1 : previousPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // Info pages content
  Widget _buildInfoPage1() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Understanding Your Attendance',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 33, 150, 243),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.calendar_today,
            'Academic Year Cycle',
            'Attendance is calculated from June to May each year',
          ),
          _buildInfoItem(
            Icons.assignment,
            'Attendance Types',
            'Your school uses ${widget.attendanceType.toLowerCase()}',
          ),
          _buildInfoItem(
            Icons.timeline,
            'Percentage Calculation',
            'Based on present days/periods vs total days/periods',
          ),
          _buildInfoItem(
            Icons.notifications_active,
            'Regular Monitoring',
            'Check your attendance regularly to maintain good percentage',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPage2() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attendance Tips',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 33, 150, 243),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            '📅',
            'Maintain at least 75% attendance for academic success',
          ),
          _buildTipItem(
            '⏰',
            'Regular attendance helps in better learning and understanding',
          ),
          _buildTipItem(
            '📊',
            'Monitor your subject-wise attendance for weak areas',
          ),
          _buildTipItem(
            '🔄',
            'Use refresh button to get latest attendance updates',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.fromARGB(255, 33, 150, 243).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Color.fromARGB(255, 33, 150, 243).withOpacity(0.3),
              ),
            ),
            child: Text(
              'Good attendance is directly linked to academic performance and school participation.',
              style: TextStyle(
                fontSize: 12,
                color: Color.fromARGB(255, 33, 150, 243),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String title, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Color.fromARGB(255, 33, 150, 243)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipItem(String emoji, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Color.fromARGB(255, 33, 150, 243).withOpacity(0.1),
              border: Border(
                bottom: BorderSide(
                  color: Color.fromARGB(255, 33, 150, 243).withOpacity(0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 40,
                  color: Color.fromARGB(255, 33, 150, 243),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Student Attendance',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 33, 150, 243),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.schoolName,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color.fromARGB(255, 33, 150, 243),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Class: ${widget.className ?? 'Unknown'}${widget.section != null ? ' - ${widget.section}' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.academicYear,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          // Info Pages with Gesture Detection
          Expanded(
            child: GestureDetector(
              onPanUpdate: (details) {
                // Swipe left
                if (details.delta.dx > 3) {
                  _previousInfoPage();
                }
                // Swipe right
                if (details.delta.dx < -3) {
                  _nextInfoPage();
                }
              },
              child: PageView(
                controller: _infoPageController,
                onPageChanged: (page) {
                  setState(() {
                    _currentInfoPage = page;
                  });
                },
                children: [_buildInfoPage1(), _buildInfoPage2()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
