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
  DateTime _currentMonthView = DateTime(DateTime.now().year, DateTime.now().month);
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

  // ===== Calendar Helper Methods =====

  Map<int, String> _getDailyStatusForMonth(DateTime month) {
    final Map<int, String> dailyStatus = {};
    final yearMonth =
        '${month.year}-${month.month.toString().padLeft(2, '0')}';

    final Map<String, List<Map<String, dynamic>>> recordsByDate = {};
    for (var record in _cachedAttendanceRecords) {
      final date = record['date'] as String?;
      if (date != null && date.startsWith(yearMonth)) {
        recordsByDate.putIfAbsent(date, () => []).add(record);
      }
    }

    for (var entry in recordsByDate.entries) {
      final dateParts = entry.key.split('-');
      if (dateParts.length >= 3) {
        final day = int.tryParse(dateParts[2]) ?? 0;
        final records = entry.value;

        if (_isPerDayOnce) {
          var firstPeriod = records.first;
          for (var r in records) {
            final curr =
                int.tryParse(r['period_number']?.toString() ?? '999') ?? 999;
            final best =
                int.tryParse(
                    firstPeriod['period_number']?.toString() ?? '999') ??
                999;
            if (curr < best) firstPeriod = r;
          }
          dailyStatus[day] =
              firstPeriod['status'] == 'present' ? 'present' : 'absent';
        } else {
          final allPresent =
              records.every((r) => r['status'] == 'present');
          dailyStatus[day] = allPresent ? 'present' : 'absent';
        }
      }
    }

    return dailyStatus;
  }

  void _navigateMonth(int direction) {
    setState(() {
      _currentMonthView = DateTime(
          _currentMonthView.year, _currentMonthView.month + direction);
    });
  }

  void _showDayDetailsSheet(DateTime date) async {
    setState(() {
      _selectedDate = date;
    });
    await _loadAttendanceData();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildDayDetailsSheet(date),
    );
  }

  Widget _buildDayDetailsSheet(DateTime date) {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(date);
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.calendar_today,
                      color: Color(0xFF1565C0), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Day Details',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E))),
                      Text(dateStr,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF1565C0)),
            )
          else if (_dailyAttendance.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.event_busy, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text('No attendance records for this day',
                      style:
                          TextStyle(fontSize: 15, color: Colors.grey[500])),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _dailyAttendance.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final att = _dailyAttendance[index];
                  final isPresent = att['status'] == 'present';
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isPresent
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isPresent
                            ? const Color(0xFF66BB6A)
                            : const Color(0xFFEF5350),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isPresent
                                ? const Color(0xFF43A047)
                                : const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isPresent
                                ? Icons.check_rounded
                                : Icons.close_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Period ${att['period_number']} — ${att['subject']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Color(0xFF1A1A2E)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'By ${att['marked_by']}${att['time'] != 'N/A' ? ' • ${att['time']}' : ''}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPresent
                                ? const Color(0xFF43A047)
                                : const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isPresent ? 'PRESENT' : 'ABSENT',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ===== Layout Builders =====

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        _AttendanceInfoSidebar(
          schoolName: widget.schoolName,
          studentName: widget.studentName,
          className: _className,
          section: widget.section,
          academicYear: _getAcademicYearText(),
          attendanceType: _getAttendanceTypeDescription(),
        ),
        Expanded(
          child: Column(
            children: [
              _buildDesktopTopBar(),
              Expanded(
                child: Container(
                  color: const Color(0xFFF5F7FA),
                  child: SingleChildScrollView(child: _buildMainContent()),
                ),
              ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1565C0)),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back to Dashboard',
          ),
          const SizedBox(width: 8),
          const Text(
            'My Attendance',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _getAcademicYearText(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1565C0),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1565C0)),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  // Mobile/Tablet Layout
  Widget _buildMobileTabletLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _refreshData,
                tooltip: 'Refresh',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
              title: Text(
                'My Attendance',
                style: TextStyle(
                  fontSize: _isMobile ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A237E), Color(0xFF1565C0), Color(0xFF42A5F5)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      top: -30,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -20,
                      bottom: -40,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _isLoading && _isInitialLoad
                ? SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: _buildLoadingState(),
                  )
                : _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading && _isInitialLoad && _isDesktop) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: _buildLoadingState(),
      );
    }

    final padding = _isDesktop
        ? const EdgeInsets.fromLTRB(24, 16, 24, 24)
        : const EdgeInsets.fromLTRB(16, 16, 16, 24);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMessage != null) ...[
            _buildMessage(_errorMessage!, true),
            const SizedBox(height: 16),
          ],
          // Student Info (mobile/tablet only)
          if (!_isDesktop) ...[
            _buildStudentInfoCard(),
            const SizedBox(height: 16),
          ],
          // Summary Stats
          _buildSummarySection(),
          const SizedBox(height: 20),
          // Calendar
          _buildCalendarCard(),
          const SizedBox(height: 20),
          // Subject-wise Attendance
          if (_isPerPeriod && _subjectWiseAttendance.isNotEmpty) ...[
            _buildSubjectWiseAttendanceCard(),
            const SizedBox(height: 20),
          ],
          // Legend
          _buildLegend(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStudentInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF1565C0)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                widget.studentName[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Class: ${_className ?? 'Unknown'}${widget.section != null ? ' • ${widget.section}' : ''}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _getAcademicYearText().replaceAll('Academic Year: ', ''),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1565C0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    final percentage = (_attendanceSummary['percentage'] ?? 0.0).toDouble();
    final total = _attendanceSummary['total'] ?? 0;
    final present = _attendanceSummary['present'] ?? 0;
    final absent = _attendanceSummary['absent'] ?? 0;

    Color percentColor;
    if (percentage >= 75) {
      percentColor = const Color(0xFF43A047);
    } else if (percentage >= 50) {
      percentColor = const Color(0xFFFF8F00);
    } else {
      percentColor = const Color(0xFFE53935);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Percentage Ring
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: percentage / 100,
                        strokeWidth: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(percentColor),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: percentColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildMiniStat('Total', total.toString(),
                          Icons.calendar_month_rounded, const Color(0xFF1565C0)),
                    ),
                    Expanded(
                      child: _buildMiniStat('Present', present.toString(),
                          Icons.check_circle_rounded, const Color(0xFF43A047)),
                    ),
                    Expanded(
                      child: _buildMiniStat('Absent', absent.toString(),
                          Icons.cancel_rounded, const Color(0xFFE53935)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFF1565C0), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getAttendanceTypeDescription(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1565C0),
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
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildCalendarCard() {
    final dailyStatus = _getDailyStatusForMonth(_currentMonthView);
    final firstDay =
        DateTime(_currentMonthView.year, _currentMonthView.month, 1);
    final daysInMonth =
        DateTime(_currentMonthView.year, _currentMonthView.month + 1, 0).day;
    final startWeekday = firstDay.weekday; // 1=Monday, 7=Sunday
    final offset = startWeekday - 1;
    final totalCells = offset + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final gridItemCount = rows * 7;

    final today = DateTime.now();
    final isCurrentMonth = _currentMonthView.year == today.year &&
        _currentMonthView.month == today.month;
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Month Navigation Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF1565C0)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () => _navigateMonth(-1),
                ),
                Flexible(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_currentMonthView),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () => _navigateMonth(1),
                ),
              ],
            ),
          ),
          // Day of Week Headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: dayLabels.map((day) {
                final isWeekend = day == 'Sat' || day == 'Sun';
                return Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isWeekend
                            ? Colors.grey[400]
                            : const Color(0xFF1A1A2E),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Divider(height: 1, indent: 12, endIndent: 12, color: Colors.grey[200]),
          // Calendar Grid
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: MediaQuery.of(context).size.width < 380 ? 0.8 : 1.0,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: gridItemCount,
              itemBuilder: (context, index) {
                if (index < offset || index >= offset + daysInMonth) {
                  return const SizedBox();
                }
                final day = index - offset + 1;
                final date = DateTime(
                    _currentMonthView.year, _currentMonthView.month, day);
                final isToday = isCurrentMonth && day == today.day;
                final isFuture = date.isAfter(today);
                final status = dailyStatus[day];
                return _buildDayCell(day, status, isToday, isFuture, date);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
      int day, String? status, bool isToday, bool isFuture, DateTime date) {
    Color bgColor;
    Color textColor;
    BoxBorder? border;

    if (isFuture) {
      bgColor = Colors.grey[50]!;
      textColor = Colors.grey[350]!;
    } else if (status == 'present') {
      bgColor = const Color(0xFF43A047);
      textColor = Colors.white;
    } else if (status == 'absent') {
      bgColor = const Color(0xFFE53935);
      textColor = Colors.white;
    } else {
      bgColor = Colors.grey[100]!;
      textColor = const Color(0xFF1A1A2E);
    }

    if (isToday) {
      border = Border.all(color: const Color(0xFF1565C0), width: 2.5);
    }

    return GestureDetector(
      onTap: isFuture ? null : () => _showDayDetailsSheet(date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: border,
          boxShadow: status != null && !isFuture
              ? [
                  BoxShadow(
                    color: bgColor.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 14,
              fontWeight:
                  isToday || status != null ? FontWeight.bold : FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          _buildLegendItem(const Color(0xFF43A047), 'Present'),
          _buildLegendItem(const Color(0xFFE53935), 'Absent'),
          _buildLegendItem(Colors.grey[200]!, 'No Record'),
          _buildLegendDot(const Color(0xFF1565C0), 'Today'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 2.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildSubjectWiseAttendanceCard() {
    final sortedSubjects = _subjectWiseAttendance.entries.toList()
      ..sort((a, b) => b.value['percentage'].compareTo(a.value['percentage']));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: Color(0xFF1565C0), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Subject-wise Attendance',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...sortedSubjects.map((entry) {
            final subject = entry.key;
            final stats = entry.value;
            final percentage = (stats['percentage'] as double).toDouble();
            final present = stats['present'] as int;
            final total = stats['total'] as int;

            Color barColor;
            if (percentage >= 75) {
              barColor = const Color(0xFF43A047);
            } else if (percentage >= 50) {
              barColor = const Color(0xFFFF8F00);
            } else {
              barColor = const Color(0xFFE53935);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subject,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Color(0xFF1A1A2E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: barColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: barColor),
                        ),
                        child: Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: barColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percentage / 100,
                            minHeight: 6,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$present/$total',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            strokeWidth: 3,
            color: Color(0xFF1565C0),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFFEF5350) : const Color(0xFF66BB6A),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: isError ? const Color(0xFFE53935) : const Color(0xFF43A047),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? const Color(0xFFE53935) : const Color(0xFF43A047),
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: Icon(Icons.close_rounded, size: 18, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: _buildDesktopLayout(),
      );
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
