// attendance_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:async';
import 'teacher_dashboard_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final String schoolCode;
  final String userId;
  final String schoolName;
  final String teacherId;
  final String teacherName;
  final Map<String, dynamic> schoolSettings;

  const AttendanceScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.teacherId,
    required this.teacherName,
    required this.schoolSettings,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _allClasses = [];
  Map<String, dynamic>? _selectedClass;
  String? _selectedPeriod;
  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _students = [];
  Map<String, String> _attendanceStatuses = {};
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  bool _isSaving = false;
  bool _attendanceMarked = false;
  bool _showHistory = false;
  List<Map<String, dynamic>> _attendanceHistory = [];
  String? _markedByTeacherName;
  String? _updatedByTeacherName;

  // Leave applications map: studentId -> { reason, date, ... }
  Map<String, Map<String, dynamic>> _leaveApplications = {};

  final Map<String, Map<String, dynamic>> _attendanceDocsByPeriod = {};
  late final String _attendanceType;

  // Caching variables
  final Map<String, dynamic> _cache = {};
  static const String _classesCacheKey = 'classes_cache_v3';
  static const String _timetableCacheKey = 'timetable_cache_v3';
  static const String _studentsCacheKey =
      'students_cache_v4'; // Updated cache key
  static const String _attendanceCacheKey = 'attendance_cache_v3';
  SharedPreferences? _prefs;

  // Firebase read counter
  int _firebaseReads = 0;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // Tab controller
  late TabController _tabController;

  // Sidebar info page controller
  final PageController _infoPageController = PageController();
  int _currentInfoPage = 0;

  // Timer for auto-dismiss messages
  Timer? _messageTimer;

  bool get _isPerDayOnce => _attendanceType == 'per_day_once';
  bool get _isPerDayTwice => _attendanceType == 'per_day_twice';
  bool get _isPerPeriod => _attendanceType == 'per_period';

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _attendanceType = _normalizeAttendanceType(
      widget.schoolSettings['attendance_type']?.toString(),
    );
    _initSharedPreferences();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _infoPageController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    _messageTimer?.cancel();

    setState(() {
      if (isError) {
        _errorMessage = message;
        _successMessage = null;
      } else {
        _successMessage = message;
        _errorMessage = null;
      }
    });

    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (isError) {
            _errorMessage = null;
          } else {
            _successMessage = null;
          }
        });
      }
    });
  }

  void _logRead(String collection, {String? docId}) {
    _firebaseReads++;
    print(
      '🔥 FIREBASE READ #$_firebaseReads: $collection${docId != null ? '/$docId' : ''}',
    );
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadAllClasses();
  }

  String _normalizeAttendanceType(String? val) {
    if (val == null) return 'per_period';
    final v = val.toLowerCase().trim();
    if (v == 'per_day' || v.contains('once')) return 'per_day_once';
    if (v == 'per_day_twice' || v.contains('twice')) return 'per_day_twice';
    if (v == 'per_period' || v.contains('period')) return 'per_period';
    return 'per_period';
  }

  // Convert data for caching - handle Timestamp objects
  dynamic _prepareDataForCache(dynamic data) {
    if (data is Timestamp) {
      return {
        '__type': 'timestamp',
        'seconds': data.seconds,
        'nanoseconds': data.nanoseconds,
      };
    } else if (data is Map) {
      final result = <String, dynamic>{};
      for (final key in data.keys) {
        result[key] = _prepareDataForCache(data[key]);
      }
      return result;
    } else if (data is List) {
      return data.map(_prepareDataForCache).toList();
    }
    return data;
  }

  // Restore data from cache - convert back Timestamp objects
  dynamic _restoreDataFromCache(dynamic data) {
    if (data is Map) {
      if (data['__type'] == 'timestamp') {
        return Timestamp(data['seconds'], data['nanoseconds']);
      }
      final result = <String, dynamic>{};
      for (final key in data.keys) {
        result[key] = _restoreDataFromCache(data[key]);
      }
      return result;
    } else if (data is List) {
      return data.map(_restoreDataFromCache).toList();
    }
    return data;
  }

  Future<void> _saveToCache(String key, dynamic data) async {
    try {
      final preparedData = _prepareDataForCache(data);
      _cache[key] = {
        'data': preparedData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Also save to persistent storage for important data
      if (_prefs != null &&
          (key.contains(_classesCacheKey) ||
              key.contains(_timetableCacheKey))) {
        await _prefs!.setString(key, json.encode(preparedData));
      }
    } catch (e) {
      print('Error saving to cache: $e');
    }
  }

  dynamic _getFromCache(
    String key, {
    Duration maxAge = const Duration(hours: 1),
  }) {
    // Check memory cache first
    final cached = _cache[key];
    if (cached != null) {
      final timestamp = cached['timestamp'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age <= maxAge.inMilliseconds) {
        print('📦 MEMORY CACHE HIT: $key');
        return _restoreDataFromCache(cached['data']);
      } else {
        _cache.remove(key);
      }
    }

    // Try persistent storage
    if (_prefs != null && _prefs!.containsKey(key)) {
      try {
        final dataString = _prefs!.getString(key);
        if (dataString != null) {
          final data = json.decode(dataString);
          final restoredData = _restoreDataFromCache(data);
          _cache[key] = {
            'data': data,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          print('📦 PERSISTENT CACHE HIT: $key');
          return restoredData;
        }
      } catch (e) {
        print('Error reading from persistent cache: $e');
        _prefs!.remove(key);
      }
    }

    return null;
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
      _selectedClass = null;
      _selectedPeriod = null;
      _students = [];
      _attendanceStatuses = {};
      _periods = [];
      _attendanceMarked = false;
      _attendanceDocsByPeriod.clear();
    });

    // Clear cache
    _cache.clear();
    if (_prefs != null) {
      final keysToRemove = <String>[];
      final allKeys = _prefs!.getKeys();
      for (final key in allKeys) {
        if (key.contains(_classesCacheKey) ||
            key.contains(_timetableCacheKey) ||
            key.contains(_studentsCacheKey) ||
            key.contains(_attendanceCacheKey)) {
          keysToRemove.add(key);
        }
      }
      for (final key in keysToRemove) {
        await _prefs!.remove(key);
      }
    }

    await _loadAllClasses();
    _showMessage('Data refreshed successfully!');
  }

  Future<void> _loadAllClasses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Try cache first
    final cacheKey = '${_classesCacheKey}_${widget.schoolCode}';
    final cachedClasses = _getFromCache(
      cacheKey,
      maxAge: const Duration(hours: 24),
    );
    if (cachedClasses != null) {
      print('Loaded ${cachedClasses.length} classes from cache');
      setState(() {
        _allClasses = List<Map<String, dynamic>>.from(cachedClasses);
        _isLoading = false;
      });
      return;
    }

    try {
      _logRead('schools/${widget.schoolCode}/classes');
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();

      List<Map<String, dynamic>> classesWithSections = [];

      for (var doc in classesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final grade = data['grade']?.toString() ?? 'Unknown Grade';
        final sectionsRaw = data['sections'];

        List<String> sections = [];
        if (sectionsRaw is List) {
          sections = sectionsRaw.map((e) => e.toString()).toList();
        } else if (sectionsRaw is String) {
          sections = sectionsRaw
              .split(',')
              .map((s) => s.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }

        if (sections.isEmpty) {
          classesWithSections.add({
            'id': doc.id,
            'grade': grade,
            'section': null,
            'displayName': grade,
            'fullClassId': doc.id,
          });
        } else {
          for (var section in sections) {
            classesWithSections.add({
              'id': '${doc.id}_$section',
              'grade': grade,
              'section': section,
              'displayName': '$grade - $section',
              'fullClassId': doc.id,
            });
          }
        }
      }

      // Sort classes by grade and section for better UX
      classesWithSections.sort((a, b) {
        final gradeCompare = (a['grade'] as String).compareTo(
          b['grade'] as String,
        );
        if (gradeCompare != 0) return gradeCompare;
        final sectionA = a['section'] as String? ?? '';
        final sectionB = b['section'] as String? ?? '';
        return sectionA.compareTo(sectionB);
      });

      await _saveToCache(cacheKey, classesWithSections);

      print('Loaded ${classesWithSections.length} classes from Firebase');
      setState(() {
        _allClasses = classesWithSections;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading classes: $e');
      setState(() {
        _isLoading = false;
      });
      _showMessage('Error loading classes: $e', isError: true);
    }
  }

  Future<void> _onClassSelected(Map<String, dynamic>? cls) async {
    setState(() {
      _selectedClass = cls;
      _selectedPeriod = null;
      _periods = [];
      _students = [];
      _attendanceStatuses = {};
      _attendanceDocsByPeriod.clear();
      _attendanceMarked = false;
      _markedByTeacherName = null;
      _updatedByTeacherName = null;
      _leaveApplications = {};
      _errorMessage = null;
      _successMessage = null;
    });

    if (cls == null) return;

    print('Selected class: ${cls['displayName']}');
    print('Full class ID: ${cls['fullClassId']}');
    print('Section: ${cls['section']}');

    setState(() => _isLoading = true);
    try {
      await _loadTimetablePeriodsForSelectedClass();
      await _loadExistingAttendanceDocsForSelectedClassDate();
      await _loadLeaveApplications();

      if (_isToday || _attendanceDocsByPeriod.isNotEmpty) {
        await _loadStudentsForSelectedClass();
      }
    } catch (e) {
      print('Error initializing class: $e');
      _showMessage('Error initializing class: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLeaveApplications() async {
    if (_selectedClass == null) return;

    final fullClassId = _selectedClass!['fullClassId'];
    if (fullClassId == null) return;

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      _logRead('schools/${widget.schoolCode}/leave_applications (query)');
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('leave_applications')
          .where('class_id', isEqualTo: fullClassId)
          .where('date', isEqualTo: dateStr)
          .get();

      final leaveMap = <String, Map<String, dynamic>>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final studentId = data['student_id'] as String?;
        if (studentId != null) {
          leaveMap[studentId] = {
            'type': data['type'] ?? 'Other',
            'reason': data['reason'] ?? 'No reason provided',
            'student_name': data['student_name'] ?? '',
            'date': data['date'] ?? '',
            'status': data['status'] ?? 'applied',
            'attachment_url': data['attachment_url'],
          };
        }
      }

      setState(() {
        _leaveApplications = leaveMap;
      });
      print('Loaded ${_leaveApplications.length} leave applications for date $dateStr');
    } catch (e) {
      print('Error loading leave applications: $e');
    }
  }

  Future<void> _loadTimetablePeriodsForSelectedClass() async {
    if (_selectedClass == null) {
      print('No class selected for timetable loading');
      return;
    }

    final fullClassId = _selectedClass!['fullClassId'];
    if (fullClassId == null) {
      print('fullClassId is null for selected class');
      setState(() {
        _periods = [];
      });
      return;
    }

    final cacheKey = '${_timetableCacheKey}_${widget.schoolCode}_$fullClassId';
    final cachedTimetable = _getFromCache(
      cacheKey,
      maxAge: const Duration(hours: 12),
    );

    if (cachedTimetable != null) {
      print('Found cached timetable for class: $fullClassId');
      final day = DateFormat('EEEE').format(_selectedDate).toLowerCase();
      final timetableData =
          cachedTimetable['timetable'] as Map<String, dynamic>?;

      if (timetableData != null && timetableData[day] != null) {
        final dayPeriods = List<Map<String, dynamic>>.from(
          (timetableData[day] as List<dynamic>?) ?? [],
        );

        final periodList = dayPeriods
            .where((p) => (p['type'] ?? '') == 'period')
            .toList();

        setState(() {
          _periods = periodList.map((p) {
            return {
              'number': (p['number'] ?? '').toString(),
              'subject': p['subject'] ?? 'Unknown Subject',
              'startTime': p['start_time'] ?? '',
              'endTime': p['end_time'] ?? '',
            };
          }).toList();
        });
        print('Loaded ${_periods.length} periods from cache for $day');
        return;
      } else {
        print('No timetable data found in cache for day: $day');
      }
    }

    // If no cache or cache miss, fetch from Firestore
    final day = DateFormat('EEEE').format(_selectedDate).toLowerCase();
    print('Fetching timetable for class: $fullClassId, day: $day');

    try {
      _logRead('schools/${widget.schoolCode}/timetables/$fullClassId');
      final docSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .doc(fullClassId)
          .get();

      if (!docSnap.exists) {
        print('No timetable document found for class: $fullClassId');

        // Try alternative approach: look for timetable with class name
        await _tryAlternativeTimetableLookup();
        return;
      }

      final data = docSnap.data() ?? {};
      await _saveToCache(cacheKey, data); // Cache the entire timetable

      final timetableData = data['timetable'] as Map<String, dynamic>?;

      if (timetableData == null) {
        print('No timetable data found in document for class: $fullClassId');
        setState(() {
          _periods = [];
        });
        return;
      }

      if (timetableData[day] == null) {
        print('No timetable data for day: $day in class: $fullClassId');
        setState(() {
          _periods = [];
        });
        return;
      }

      final dayPeriods = List<Map<String, dynamic>>.from(
        (timetableData[day] as List<dynamic>?) ?? [],
      );

      final periodList = dayPeriods
          .where((p) => (p['type'] ?? '') == 'period')
          .toList();

      setState(() {
        _periods = periodList.map((p) {
          return {
            'number': (p['number'] ?? '').toString(),
            'subject': p['subject'] ?? 'Unknown Subject',
            'startTime': p['start_time'] ?? '',
            'endTime': p['end_time'] ?? '',
          };
        }).toList();
      });

      print('Loaded ${_periods.length} periods from Firebase for $day');
    } catch (e) {
      print('Error loading timetable from Firestore: $e');
      setState(() {
        _periods = [];
      });
    }
  }

  Future<void> _tryAlternativeTimetableLookup() async {
    if (_selectedClass == null) return;

    final className = _selectedClass!['displayName'];
    final grade = _selectedClass!['grade'];
    final section = _selectedClass!['section'];

    print(
      'Trying alternative timetable lookup for: $className, grade: $grade, section: $section',
    );

    try {
      // Query timetables collection to find matching timetable
      _logRead('schools/${widget.schoolCode}/timetables (query)');
      final querySnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .where('class_name', isEqualTo: className)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        print(
          'Found ${querySnapshot.docs.length} timetables with class name: $className',
        );

        // Use the first matching timetable
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        await _saveToCache(
          '${_timetableCacheKey}_${widget.schoolCode}_${doc.id}',
          data,
        );

        final day = DateFormat('EEEE').format(_selectedDate).toLowerCase();
        final timetableData = data['timetable'] as Map<String, dynamic>?;

        if (timetableData != null && timetableData[day] != null) {
          final dayPeriods = List<Map<String, dynamic>>.from(
            (timetableData[day] as List<dynamic>?) ?? [],
          );

          final periodList = dayPeriods
              .where((p) => (p['type'] ?? '') == 'period')
              .toList();

          setState(() {
            _periods = periodList.map((p) {
              return {
                'number': (p['number'] ?? '').toString(),
                'subject': p['subject'] ?? 'Unknown Subject',
                'startTime': p['start_time'] ?? '',
                'endTime': p['end_time'] ?? '',
              };
            }).toList();
          });
          print(
            'Loaded ${_periods.length} periods from alternative lookup for $day',
          );
        }
      } else {
        print('No timetables found with class name: $className');
        setState(() {
          _periods = [];
        });
      }
    } catch (e) {
      print('Error in alternative timetable lookup: $e');
      setState(() {
        _periods = [];
      });
    }
  }

  Future<void> _loadExistingAttendanceDocsForSelectedClassDate() async {
    if (_selectedClass == null) return;

    final fullClassId = _selectedClass!['fullClassId'];
    final section = _selectedClass!['section'];

    if (fullClassId == null) {
      print('fullClassId is null, cannot load attendance');
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final cacheKey =
        '${_attendanceCacheKey}_${widget.schoolCode}_${fullClassId}_${section ?? 'no-section'}_$dateStr';

    // Don't cache today's attendance, but cache past dates for longer
    final isToday = _isToday;
    final cachedAttendance = isToday
        ? null
        : _getFromCache(cacheKey, maxAge: const Duration(hours: 24));

    if (cachedAttendance != null) {
      _attendanceDocsByPeriod.clear();
      for (var doc in cachedAttendance) {
        final periodNumber = (doc['period_number'] ?? '').toString();
        if (periodNumber.isNotEmpty) {
          _attendanceDocsByPeriod[periodNumber] = Map<String, dynamic>.from(
            doc,
          );
        }
      }
      print(
        'Loaded ${_attendanceDocsByPeriod.length} attendance records from cache',
      );
      return;
    }

    final sectionVal = _selectedClass!['section'];

    _logRead('schools/${widget.schoolCode}/attendance (query)');
    Query q = FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolCode)
        .collection('attendance')
        .where('class_id', isEqualTo: fullClassId)
        .where('date', isEqualTo: dateStr);

    if (sectionVal != null) {
      q = q.where('section', isEqualTo: sectionVal);
    }

    final snap = await q.get();

    List<Map<String, dynamic>> attendanceData = [];
    _attendanceDocsByPeriod.clear();
    for (var doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final periodNumber = (data['period_number'] ?? '').toString();
      if (periodNumber.isNotEmpty) {
        final copy = Map<String, dynamic>.from(data);
        copy['__docId'] = doc.id;

        String subjectName = data['subject'] ?? 'Unknown Subject';

        if (subjectName == 'Unknown Subject' || subjectName.isEmpty) {
          try {
            final day = DateFormat('EEEE').format(_selectedDate).toLowerCase();
            final timetableCacheKey =
                '${_timetableCacheKey}_${widget.schoolCode}_$fullClassId';
            final cachedTimetable = _getFromCache(timetableCacheKey);

            Map<String, dynamic>? timetableData;
            if (cachedTimetable != null) {
              timetableData =
                  cachedTimetable['timetable'] as Map<String, dynamic>?;
            } else {
              _logRead('schools/${widget.schoolCode}/timetables/$fullClassId');
              final timetableDoc = await FirebaseFirestore.instance
                  .collection('schools')
                  .doc(widget.schoolCode)
                  .collection('timetables')
                  .doc(fullClassId)
                  .get();

              if (timetableDoc.exists) {
                final docData = timetableDoc.data();
                timetableData = docData?['timetable'] as Map<String, dynamic>?;
              }
            }

            if (timetableData != null && timetableData[day] != null) {
              final dayPeriods = List<Map<String, dynamic>>.from(
                (timetableData[day] as List<dynamic>?) ?? [],
              );

              for (var period in dayPeriods) {
                if ((period['type'] ?? '') == 'period' &&
                    (period['number']?.toString() ?? '') == periodNumber) {
                  subjectName = period['subject'] ?? 'Unknown Subject';
                  break;
                }
              }
            }
          } catch (e) {
            print('Error fetching subject from timetable: $e');
          }
        }

        copy['subject'] = subjectName;
        _attendanceDocsByPeriod[periodNumber] = copy;
        attendanceData.add(copy);
      }
    }

    // Cache attendance data for past dates
    if (!isToday) {
      await _saveToCache(cacheKey, attendanceData);
    }

    if (_isPerDayOnce && _attendanceDocsByPeriod.isNotEmpty) {
      final firstPeriod = _attendanceDocsByPeriod.keys.first;
      _selectedPeriod = firstPeriod;
    }

    print(
      'Loaded ${_attendanceDocsByPeriod.length} attendance records from Firebase',
    );
  }

  Future<void> _loadStudentsForSelectedClass() async {
    if (_selectedClass == null) return;

    final fullClassId = _selectedClass!['fullClassId'];
    final section = _selectedClass!['section'];

    if (fullClassId == null) {
      print('fullClassId is null, cannot load students');
      return;
    }

    setState(() {
      _isLoading = true;
      _students = [];
      _attendanceStatuses = {};
      _attendanceMarked = false;
      _markedByTeacherName = null;
      _updatedByTeacherName = null;
      _errorMessage = null;
      _successMessage = null;
    });

    // Try cache first
    final cacheKey =
        '${_studentsCacheKey}_${widget.schoolCode}_${fullClassId}_${section ?? 'no-section'}';
    final cachedStudents = _getFromCache(
      cacheKey,
      maxAge: const Duration(hours: 4),
    );
    if (cachedStudents != null) {
      print('Loaded ${cachedStudents.length} students from cache');
      setState(() {
        _students = List<Map<String, dynamic>>.from(cachedStudents);
      });

      if (_isToday) {
        for (var s in _students) {
          _attendanceStatuses[s['id'] as String] = 'present';
        }
      }

      if (_selectedPeriod != null &&
          _attendanceDocsByPeriod.containsKey(_selectedPeriod)) {
        _loadExistingAttendanceIntoUI(
          _attendanceDocsByPeriod[_selectedPeriod!]!,
        );
      }

      setState(() => _isLoading = false);
      return;
    }

    try {
      _logRead('users (query)');
      Query studentsQuery = FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .where('class_id', isEqualTo: fullClassId);

      if (section != null) {
        studentsQuery = studentsQuery.where('section', isEqualTo: section);
      }

      final studentsSnapshot = await studentsQuery.get();

      final loadedStudents = studentsSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};

        // Get full_name if available, otherwise use username
        final fullName = data['full_name']?.toString() ?? '';
        final username = data['username'] ?? 'Unknown Student';
        final displayName = fullName.isNotEmpty ? fullName : username;

        // Get roll number
        final rollNumber = data['roll_number']?.toString() ?? 'N/A';

        return {
          'id': doc.id,
          'name': displayName,
          'username': username,
          'full_name': fullName,
          'rollNumber': rollNumber,
        };
      }).toList();

      loadedStudents.sort(
        (a, b) =>
            (a['rollNumber'] as String).compareTo(b['rollNumber'] as String),
      );

      await _saveToCache(cacheKey, loadedStudents);

      print('Loaded ${loadedStudents.length} students from Firebase');
      setState(() {
        _students = loadedStudents;
        if (_isToday) {
          for (var s in _students) {
            _attendanceStatuses[s['id'] as String] = 'present';
          }
        }
      });

      if (_selectedPeriod != null &&
          _attendanceDocsByPeriod.containsKey(_selectedPeriod)) {
        _loadExistingAttendanceIntoUI(
          _attendanceDocsByPeriod[_selectedPeriod!]!,
        );
      }
    } catch (e) {
      print('Error loading students: $e');
      _showMessage('Error loading students: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _loadExistingAttendanceIntoUI(Map<String, dynamic> attendanceDoc) {
    final rawAttendance = attendanceDoc['attendance'];
    Map<String, dynamic> attendance = {};
    if (rawAttendance is Map) {
      attendance = Map<String, dynamic>.from(rawAttendance);
    }

    for (var student in _students) {
      final sid = student['id'] as String;
      final val = (attendance[sid]?.toString()) ?? '';
      if (val.isNotEmpty) {
        _attendanceStatuses[sid] = val;
      }
    }

    setState(() {
      _attendanceMarked = true;
      _markedByTeacherName = attendanceDoc['marked_by_teacher_name'] as String?;
      _updatedByTeacherName =
          attendanceDoc['updated_by_teacher_name'] as String?;
    });
  }

  bool _canCreateForSelectedPeriod(String? selectedPeriod) {
    final existingPeriods = _attendanceDocsByPeriod.keys.toSet();

    if (_isPerPeriod) return true;

    if (_isPerDayOnce) {
      if (existingPeriods.isEmpty) return true;
      if (selectedPeriod != null && existingPeriods.contains(selectedPeriod)) {
        return true;
      }
      return false;
    }

    if (_isPerDayTwice) {
      if (existingPeriods.length < 2) return true;
      if (selectedPeriod != null && existingPeriods.contains(selectedPeriod)) {
        return true;
      }
      return false;
    }

    return true;
  }

  Future<void> _loadExistingAttendance() async {
    if (_selectedClass == null || _selectedPeriod == null) return;

    final key = _selectedPeriod!;
    if (_attendanceDocsByPeriod.containsKey(key)) {
      _loadExistingAttendanceIntoUI(_attendanceDocsByPeriod[key]!);
    } else {
      setState(() {
        _attendanceMarked = false;
        _markedByTeacherName = null;
        _updatedByTeacherName = null;
        if (_isToday) {
          for (var s in _students) {
            _attendanceStatuses[s['id'] as String] = 'present';
          }
        }
      });
    }
  }

  Future<void> _saveAttendance() async {
    if (_selectedClass == null) {
      _showMessage('Please select class and section', isError: true);
      return;
    }
    if (_selectedPeriod == null) {
      _showMessage('Please select a period', isError: true);
      return;
    }

    if (!_canCreateForSelectedPeriod(_selectedPeriod)) {
      _showMessage(
        'Attendance cannot be created for this period due to school attendance policy.',
        isError: true,
      );
      return;
    }

    if (_students.isEmpty) {
      _showMessage('No students found in this class', isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final sectionPart = _selectedClass!['section'] != null
          ? '_${_selectedClass!['section']}'
          : '';
      final attendanceId =
          '${_selectedClass!['fullClassId']}${sectionPart}_${dateStr}_${_selectedPeriod}';

      final presentCount = _attendanceStatuses.values
          .where((s) => s == 'present')
          .length;
      final totalStudents = _students.length;

      String subjectName = 'Unknown Subject';
      try {
        final periodData = _periods.firstWhere(
          (period) => period['number'] == _selectedPeriod,
        );
        subjectName = periodData['subject'] ?? 'Unknown Subject';
      } catch (e) {
        print('Error getting subject name: $e');
      }

      // 1. First, save the main attendance document
      final attendanceData = <String, dynamic>{
        'school_code': widget.schoolCode,
        'class_id': _selectedClass!['fullClassId'],
        'class_name': _selectedClass!['displayName'],
        'section': _selectedClass!['section'],
        'date': dateStr,
        'period_number': _selectedPeriod,
        'subject': subjectName,
        'attendance': _attendanceStatuses,
        'marked_by_teacher_id': widget.teacherId,
        'marked_by_teacher_name': widget.teacherName,
        'marked_at': FieldValue.serverTimestamp(),
        'total_students': totalStudents,
        'present_count': presentCount,
        'absent_count': totalStudents - presentCount,
        'attendance_percentage': totalStudents > 0
            ? (presentCount / totalStudents * 100).round()
            : 0,
      };

      // Save main attendance document
      final existing = _attendanceDocsByPeriod[_selectedPeriod ?? ''];
      if (existing != null && existing['__docId'] != null) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('attendance')
            .doc(existing['__docId'] as String)
            .update({
              ...attendanceData,
              'updated_by_teacher_id': widget.teacherId,
              'updated_by_teacher_name': widget.teacherName,
              'updated_at': FieldValue.serverTimestamp(),
            });
      } else {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('attendance')
            .doc(attendanceId)
            .set(attendanceData);
      }

      // 2. Save student attendance records in optimized chunks
      await _saveStudentAttendanceInChunks(dateStr, subjectName);

      // 3. Update cache and UI
      await _loadExistingAttendanceDocsForSelectedClassDate();

      setState(() {
        _isSaving = false;
        _attendanceMarked = true;
        _markedByTeacherName = widget.teacherName;
        _updatedByTeacherName = widget.teacherName;
      });

      if (_attendanceDocsByPeriod.containsKey(_selectedPeriod)) {
        _loadExistingAttendanceIntoUI(
          _attendanceDocsByPeriod[_selectedPeriod!]!,
        );
      }

      _showMessage(
        'Attendance saved successfully for $totalStudents students!',
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      _showMessage('Error saving attendance: $e', isError: true);
    }
  }

  // New optimized method for saving student attendance in chunks
  Future<void> _saveStudentAttendanceInChunks(
    String dateStr,
    String subjectName,
  ) async {
    const int chunkSize = 50; // Process 50 students at a time
    final List<Map<String, dynamic>> studentsChunks = [];

    // Split students into chunks
    for (int i = 0; i < _students.length; i += chunkSize) {
      final end = (i + chunkSize < _students.length)
          ? i + chunkSize
          : _students.length;
      studentsChunks.add({'start': i, 'end': end});
    }

    // Process each chunk with delay between chunks
    for (int chunkIndex = 0; chunkIndex < studentsChunks.length; chunkIndex++) {
      final chunk = studentsChunks[chunkIndex];
      final start = chunk['start'] as int;
      final end = chunk['end'] as int;

      print(
        'Processing student chunk ${chunkIndex + 1}/${studentsChunks.length} (students $start to $end)',
      );

      await _processStudentChunk(dateStr, subjectName, start, end);

      // Add delay between chunks to avoid overwhelming Firestore
      if (chunkIndex < studentsChunks.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  Future<void> _processStudentChunk(
    String dateStr,
    String subjectName,
    int start,
    int end,
  ) async {
    final batch = FirebaseFirestore.instance.batch();

    for (int i = start; i < end; i++) {
      final student = _students[i];
      final studentId = student['id'] as String;
      final status = _attendanceStatuses[studentId] ?? 'absent';
      final points = status == 'present' ? 1 : 0;

      final studentAttendanceRef = FirebaseFirestore.instance
          .collection('users')
          .doc(studentId)
          .collection('attendance')
          .doc('${dateStr}_$_selectedPeriod');

      final studentAttendanceData = {
        'date': dateStr,
        'class_id': _selectedClass!['fullClassId'],
        'class_name': _selectedClass!['displayName'],
        'section': _selectedClass!['section'],
        'period_number': _selectedPeriod,
        'subject': subjectName,
        'school_code': widget.schoolCode,
        'status': status,
        'points': points,
        'marked_by_teacher_id': widget.teacherId,
        'marked_by_teacher_name': widget.teacherName,
        'marked_at': FieldValue.serverTimestamp(),
      };

      batch.set(studentAttendanceRef, studentAttendanceData);
    }

    try {
      await batch.commit();
      print('Successfully committed batch for students $start to $end');
    } catch (e) {
      print('Error committing batch for students $start to $end: $e');
      // If batch fails, try individual writes as fallback
      await _fallbackIndividualWrites(dateStr, subjectName, start, end);
    }
  }

  // Fallback method for individual writes if batch fails
  Future<void> _fallbackIndividualWrites(
    String dateStr,
    String subjectName,
    int start,
    int end,
  ) async {
    print('Using fallback individual writes for students $start to $end');

    for (int i = start; i < end; i++) {
      final student = _students[i];
      final studentId = student['id'] as String;
      final status = _attendanceStatuses[studentId] ?? 'absent';
      final points = status == 'present' ? 1 : 0;

      final studentAttendanceRef = FirebaseFirestore.instance
          .collection('users')
          .doc(studentId)
          .collection('attendance')
          .doc('${dateStr}_$_selectedPeriod');

      final studentAttendanceData = {
        'date': dateStr,
        'class_id': _selectedClass!['fullClassId'],
        'class_name': _selectedClass!['displayName'],
        'section': _selectedClass!['section'],
        'period_number': _selectedPeriod,
        'subject': subjectName,
        'school_code': widget.schoolCode,
        'status': status,
        'points': points,
        'marked_by_teacher_id': widget.teacherId,
        'marked_by_teacher_name': widget.teacherName,
        'marked_at': FieldValue.serverTimestamp(),
      };

      try {
        await studentAttendanceRef.set(studentAttendanceData);
        // Small delay between individual writes
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        print('Error writing individual attendance for student $studentId: $e');
        // Continue with other students even if one fails
      }
    }
  }

  Future<String> _getSubjectNameForHistoryRecord(
    Map<String, dynamic> record,
  ) async {
    try {
      final classId = record['class_id'];
      final periodNumber = record['period_number']?.toString();
      final dateStr = record['date'];

      if (classId == null || periodNumber == null || dateStr == null) {
        return 'N/A';
      }

      final date = DateFormat('yyyy-MM-dd').parse(dateStr);
      final day = DateFormat('EEEE').format(date).toLowerCase();

      final cacheKey = '${_timetableCacheKey}_${widget.schoolCode}_$classId';
      final cachedTimetable = _getFromCache(cacheKey);

      Map<String, dynamic>? timetableData;
      if (cachedTimetable != null) {
        timetableData = cachedTimetable['timetable'] as Map<String, dynamic>?;
      } else {
        _logRead('schools/${widget.schoolCode}/timetables/$classId');
        final docSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('timetables')
            .doc(classId)
            .get();

        if (!docSnap.exists) {
          return 'N/A';
        }

        final docData = docSnap.data();
        timetableData = docData?['timetable'] as Map<String, dynamic>?;
        if (timetableData != null) {
          await _saveToCache(cacheKey, docData!);
        }
      }

      if (timetableData == null || timetableData[day] == null) {
        return 'N/A';
      }

      final dayPeriods = List<Map<String, dynamic>>.from(
        (timetableData[day] as List<dynamic>?) ?? [],
      );

      for (var period in dayPeriods) {
        if ((period['type'] ?? '') == 'period' &&
            (period['number']?.toString() ?? '') == periodNumber) {
          return period['subject']?.toString() ?? 'N/A';
        }
      }

      return 'N/A';
    } catch (e) {
      print('Error fetching subject for history: $e');
      return 'N/A';
    }
  }

  Future<void> _loadAttendanceHistory() async {
    setState(() {
      _isLoading = true;
      _attendanceHistory = [];
      _errorMessage = null;
    });

    try {
      _logRead('schools/${widget.schoolCode}/attendance (query)');
      final historySnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('attendance')
          .where(
            'date',
            isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate),
          )
          .orderBy('marked_at', descending: true)
          .limit(50)
          .get();

      List<Map<String, dynamic>> historyRecords = historySnapshot.docs.map((
        doc,
      ) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        return {
          'id': doc.id,
          'class_id': data['class_id'],
          'class_name': data['class_name'],
          'section': data['section'],
          'period_number': data['period_number'],
          'marked_by': data['marked_by_teacher_name'],
          'updated_by': data['updated_by_teacher_name'] ?? 'N/A',
          'total_students': data['total_students'] ?? 0,
          'present_count': data['present_count'] ?? 0,
          'attendance_percentage': data['attendance_percentage'] ?? 0,
          'marked_at': data['marked_at'],
          'date': data['date'],
          'subject': data['subject'] ?? 'N/A',
        };
      }).toList();

      for (var record in historyRecords) {
        if (record['subject'] == 'N/A') {
          final subject = await _getSubjectNameForHistoryRecord(record);
          record['subject'] = subject;
        }
      }

      setState(() {
        _attendanceHistory = historyRecords;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Error loading history: $e', isError: true);
    }
  }

  bool get _isToday {
    final today = DateTime.now();
    return _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;
  }

  void _toggleStudentAttendance(String studentId) {
    setState(() {
      final currentStatus = _attendanceStatuses[studentId] ?? 'present';
      _attendanceStatuses[studentId] = currentStatus == 'present'
          ? 'absent'
          : 'present';
    });
  }

  Color _getStatusColor(String status) {
    return status == 'present' ? Colors.green : Colors.red;
  }

  Widget _buildStatusButton(String studentId) {
    // Check for leave application
    if (_leaveApplications.containsKey(studentId)) {
      return _buildLeaveAppliedBadge(studentId);
    }

    final status = _attendanceStatuses[studentId] ?? 'present';
    final isPresent = status == 'present';

    return ElevatedButton(
      onPressed: () => _toggleStudentAttendance(studentId),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPresent ? Colors.green : Colors.red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(isPresent ? 'Present' : 'Absent'),
    );
  }

  Widget _buildLeaveAppliedBadge(String studentId) {
    final leaveData = _leaveApplications[studentId]!;
    final type = leaveData['type'] as String? ?? 'Other';
    final reason = leaveData['reason'] as String? ?? 'No reason';
    final attachmentUrl = leaveData['attachment_url'] as String?;

    return Tooltip(
      message: '$type: $reason',
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ECDC4).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_busy_rounded,
                      color: Color(0xFF4ECDC4),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Leave Applied',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Student: ${leaveData['student_name'] ?? 'Unknown'}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Date: ${leaveData['date'] ?? ''}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      type,
                      style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ECDC4).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF4ECDC4).withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reason',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reason,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  if (attachmentUrl != null && attachmentUrl.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          launchUrl(Uri.parse(attachmentUrl));
                        },
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: const Text('View Attachment'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF4ECDC4).withOpacity(0.15),
                const Color(0xFF6C63FF).withOpacity(0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF4ECDC4).withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.event_busy_rounded,
                color: Color(0xFF4ECDC4),
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'Leave Applied',
                style: TextStyle(
                  color: Color(0xFF4ECDC4),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.info_outline,
                color: const Color(0xFF4ECDC4).withOpacity(0.7),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearSelection() {
    setState(() {
      _selectedClass = null;
      _selectedPeriod = null;
      _students = [];
      _attendanceStatuses = {};
      _periods = [];
      _attendanceMarked = false;
      _errorMessage = null;
      _successMessage = null;
      _attendanceDocsByPeriod.clear();
    });
  }

  String _formatClassName(String className, String? section) {
    if (section == null) return className;
    if (className.contains(' - $section')) {
      return className;
    }
    return '$className - $section';
  }

  Widget _buildMessage(String message, bool isError) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
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
            isError ? Icons.error_outline : Icons.check_circle,
            color: isError ? Colors.red[700] : Colors.green[700],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red[700] : Colors.green[700],
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 20,
              color: isError ? Colors.red[700] : Colors.green[700],
            ),
            onPressed: () {
              setState(() {
                if (isError) {
                  _errorMessage = null;
                } else {
                  _successMessage = null;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color ?? Colors.grey, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.grey,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildActionButton() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveAttendance,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(_attendanceMarked ? Icons.edit : Icons.save),
        label: Text(
          _isSaving
              ? 'Saving...'
              : (_attendanceMarked ? 'Update Attendance' : 'Save Attendance'),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2196F3),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey[300]!)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.assignment_ind,
                  size: 48,
                  color: Color(0xFF2196F3),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Attendance Management',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2196F3),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.schoolName,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Teacher: ${widget.teacherName}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Compact Statistics
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildCompactStatItem(
                      _allClasses.length.toString(),
                      'Classes',
                    ),
                    _buildCompactStatItem(
                      _students.length.toString(),
                      'Students',
                    ),
                    _buildCompactStatItem(
                      _periods.length.toString(),
                      'Periods',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Info Pages
          Expanded(
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

          // Page Indicator
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPageIndicator(0),
                const SizedBox(width: 8),
                _buildPageIndicator(1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStatItem(String value, String label) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2196F3),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildDesktopTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF2196F3)),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => TeacherDashboardScreen(
                    userId: widget.userId,
                    schoolCode: widget.schoolCode,
                    schoolName: widget.schoolName,
                  ),
                ),
                (route) => false,
              );
            },
            tooltip: 'Back to Dashboard',
          ),

          const Text(
            'Attendance Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2196F3),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF2196F3)),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
    );
  }

  Widget _buildMarkAttendanceTab() {
    return _isMobile
        ? _buildMobileMarkAttendanceContent()
        : _buildDesktopMarkAttendanceContent();
  }

  Widget _buildMobileMarkAttendanceContent() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Class Selection Dropdown
        DropdownButtonFormField<Map<String, dynamic>?>(
          decoration: const InputDecoration(
            labelText: 'Select Class & Section',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.class_),
            filled: true,
            fillColor: Color(0xFFF5F5F5),
          ),
          value: _selectedClass,
          items: [
            const DropdownMenuItem<Map<String, dynamic>?>(
              value: null,
              child: Text('Select a class...'),
            ),
            ..._allClasses.map<DropdownMenuItem<Map<String, dynamic>?>>((cls) {
              final displayName = cls['displayName'] as String?;
              return DropdownMenuItem<Map<String, dynamic>?>(
                value: cls,
                child: Text(displayName ?? 'Unknown Class'),
              );
            }).toList(),
          ],
          onChanged: (value) async {
            await _onClassSelected(value);
          },
        ),

        const SizedBox(height: 16),

        // Attendance Type Info Card
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF2196F3)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isPerDayOnce
                        ? 'Attendance can be marked once per day only'
                        : _isPerDayTwice
                        ? 'Attendance can be marked twice per day'
                        : 'Attendance must be marked for each period',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Period Selection (only show if class is selected and conditions are met)
        if (_selectedClass != null &&
            _periods.isNotEmpty &&
            !(_isPerDayOnce && _attendanceDocsByPeriod.isNotEmpty) &&
            !(_isPerDayTwice && _attendanceDocsByPeriod.length >= 2))
          Container(
            width: double.infinity, // Add this container to constrain width
            child: DropdownButtonFormField<String?>(
              isExpanded: true, // Add this to prevent overflow
              decoration: const InputDecoration(
                labelText: 'Select Period',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.schedule),
                filled: true,
                fillColor: Color(0xFFF5F5F5),
              ),
              value: _selectedPeriod,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Select a period...'),
                ),
                ..._periods.map<DropdownMenuItem<String?>>((period) {
                  final periodNum = period['number'].toString();
                  final isTaken = _attendanceDocsByPeriod.containsKey(
                    periodNum,
                  );
                  String label =
                      'Period ${period['number']} - ${period['subject']}';
                  if (isTaken) {
                    label = '$label (attendance exists)';
                  }
                  return DropdownMenuItem<String?>(
                    value: periodNum,
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis, // Add overflow handling
                    ),
                  );
                }).toList(),
              ],
              onChanged: (value) async {
                setState(() {
                  _selectedPeriod = value;
                  _errorMessage = null;
                  _successMessage = null;
                  _attendanceMarked = false;
                });
                await _loadExistingAttendance();
              },
            ),
          )
        else if (_selectedClass != null && _periods.isEmpty)
          _buildEmptyState(
            icon: Icons.schedule,
            title: 'No Timetable Periods',
            subtitle: 'No timetable periods available for this class today',
          ),

        const SizedBox(height: 16),

        // Show existing attendance records
        if (_selectedClass != null &&
            ((_isPerDayOnce && _attendanceDocsByPeriod.isNotEmpty) ||
                (_isPerDayTwice && _attendanceDocsByPeriod.length >= 2)))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Attendance already taken for this class/date:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._attendanceDocsByPeriod.entries.map((entry) {
                final periodNum = entry.key;
                final doc = entry.value;
                final present = (doc['present_count'] ?? 0).toString();
                final total = (doc['total_students'] ?? 0).toString();
                final markedBy = doc['marked_by_teacher_name'] ?? 'Unknown';
                final subject = doc['subject'] ?? 'Subject';

                // Check if this period is currently being edited
                final bool isEditing = _selectedPeriod == periodNum;

                return Card(
                  elevation: isEditing ? 4 : 2,
                  color: isEditing ? const Color(0xFFE3F2FD) : Colors.white,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: isEditing
                          ? const Color(0xFF2196F3)
                          : Colors.grey.shade300,
                      width: isEditing ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    title: Text('Period $periodNum - $subject'),
                    subtitle: Text(
                      'Present: $present / $total\nMarked by: $markedBy',
                    ),
                    isThreeLine: true,
                    trailing: ElevatedButton(
                      onPressed: () async {
                        setState(() {
                          _selectedPeriod = periodNum;
                          _errorMessage = null;
                          _successMessage = null;
                        });
                        if (_students.isEmpty) {
                          await _loadStudentsForSelectedClass();
                        }
                        _loadExistingAttendanceIntoUI(doc);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isEditing
                            ? const Color(0xFF1976D2)
                            : const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Edit'),
                    ),
                  ),
                );
              }).toList(),
              const SizedBox(height: 12),
            ],
          ),

        // Student Attendance Section for Mobile
        if (_students.isNotEmpty && _selectedPeriod != null)
          _buildStudentAttendanceSectionForMobile()
        else if (_selectedClass != null && _students.isEmpty && !_isLoading)
          _buildEmptyState(
            icon: Icons.people_outline,
            title: 'No Students Found',
            subtitle: 'No students found in this class section',
          )
        else if (_selectedClass == null && !_isLoading)
          _buildEmptyState(
            icon: Icons.class_,
            title: 'Select Class',
            subtitle: 'Please select a class to mark attendance',
          ),
      ],
    );
  }

  Widget _buildStudentAttendanceSectionForMobile() {
    if (!_isToday && !_attendanceMarked) {
      return _buildEmptyState(
        icon: Icons.calendar_today,
        title: 'No Attendance Found',
        subtitle: 'Switch to today\'s date to mark attendance',
      );
    }

    return Column(
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedClass!['displayName'] ?? 'Class',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_attendanceMarked)
                      const Icon(Icons.verified, color: Colors.green),
                  ],
                ),
                if (_attendanceMarked) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Marked by: ${_markedByTeacherName ?? 'Unknown'}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  if (_updatedByTeacherName != null)
                    Text(
                      'Updated by: $_updatedByTeacherName',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      'Total',
                      _students.length.toString(),
                      Icons.people,
                    ),
                    _buildStatItem(
                      'Present',
                      _attendanceStatuses.values
                          .where((s) => s == 'present')
                          .length
                          .toString(),
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    _buildStatItem(
                      'Absent',
                      _attendanceStatuses.values
                          .where((s) => s == 'absent')
                          .length
                          .toString(),
                      Icons.cancel,
                      color: Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Students List for Mobile
        Column(
          children: _students.map((student) {
            final studentId = student['id'] as String;
            final status = _attendanceStatuses[studentId] ?? 'present';

            // Build display name with roll number
            String displayName = student['name'] as String;
            final rollNumber = student['rollNumber'] as String;
            if (rollNumber != 'N/A') {
              displayName = '$rollNumber. $displayName';
            }

            return Card(
              elevation: 1,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF2196F3).withOpacity(0.1),
                  child: Text(
                    displayName[0].toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                ),
                title: Text(displayName),
                subtitle: Text('ID: ${student['username']}'),
                trailing: _leaveApplications.containsKey(studentId)
                    ? _buildLeaveAppliedBadge(studentId)
                    : _isToday
                        ? _buildStatusButton(studentId)
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status == 'present' ? 'Present' : 'Absent',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
              ),
            );
          }).toList(),
        ),

        // Save/Update Button for Mobile
        if (_isToday) ...[
          const SizedBox(height: 20),
          Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildActionButton(),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildDesktopMarkAttendanceContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Class Selection Dropdown
          DropdownButtonFormField<Map<String, dynamic>?>(
            decoration: const InputDecoration(
              labelText: 'Select Class & Section',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.class_),
              filled: true,
              fillColor: Color(0xFFF5F5F5),
            ),
            value: _selectedClass,
            items: [
              const DropdownMenuItem<Map<String, dynamic>?>(
                value: null,
                child: Text('Select a class...'),
              ),
              ..._allClasses.map<DropdownMenuItem<Map<String, dynamic>?>>((
                cls,
              ) {
                final displayName = cls['displayName'] as String?;
                return DropdownMenuItem<Map<String, dynamic>?>(
                  value: cls,
                  child: Text(displayName ?? 'Unknown Class'),
                );
              }).toList(),
            ],
            onChanged: (value) async {
              await _onClassSelected(value);
            },
          ),

          const SizedBox(height: 16),

          // Attendance Type Info Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF2196F3)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isPerDayOnce
                          ? 'Attendance can be marked once per day only'
                          : _isPerDayTwice
                          ? 'Attendance can be marked twice per day'
                          : 'Attendance must be marked for each period',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          // Period Selection (only show if class is selected and conditions are met)
          if (_selectedClass != null &&
              _periods.isNotEmpty &&
              !(_isPerDayOnce && _attendanceDocsByPeriod.isNotEmpty) &&
              !(_isPerDayTwice && _attendanceDocsByPeriod.length >= 2))
            Container(
              constraints: BoxConstraints(
                maxWidth: _isDesktop
                    ? 400
                    : double.infinity, // Responsive constraint
              ),
              child: DropdownButtonFormField<String?>(
                isExpanded: true, // Add this for consistent behavior
                decoration: const InputDecoration(
                  labelText: 'Select Period',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.schedule),
                  filled: true,
                  fillColor: Color(0xFFF5F5F5),
                ),
                value: _selectedPeriod,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Select a period...'),
                  ),
                  ..._periods.map<DropdownMenuItem<String?>>((period) {
                    final periodNum = period['number'].toString();
                    final isTaken = _attendanceDocsByPeriod.containsKey(
                      periodNum,
                    );
                    String label =
                        'Period ${period['number']} - ${period['subject']}';
                    if (isTaken) {
                      label = '$label (attendance exists)';
                    }
                    return DropdownMenuItem<String?>(
                      value: periodNum,
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                ],
                onChanged: (value) async {
                  setState(() {
                    _selectedPeriod = value;
                    _errorMessage = null;
                    _successMessage = null;
                    _attendanceMarked = false;
                  });
                  await _loadExistingAttendance();
                },
              ),
            )
          else if (_selectedClass != null && _periods.isEmpty)
            _buildEmptyState(
              icon: Icons.schedule,
              title: 'No Timetable Periods',
              subtitle: 'No timetable periods available for this class today',
            ),

          const SizedBox(height: 16),

          // Show existing attendance records
          if (_selectedClass != null &&
              ((_isPerDayOnce && _attendanceDocsByPeriod.isNotEmpty) ||
                  (_isPerDayTwice && _attendanceDocsByPeriod.length >= 2)))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance already taken for this class/date:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._attendanceDocsByPeriod.entries.map((entry) {
                  final periodNum = entry.key;
                  final doc = entry.value;
                  final present = (doc['present_count'] ?? 0).toString();
                  final total = (doc['total_students'] ?? 0).toString();
                  final markedBy = doc['marked_by_teacher_name'] ?? 'Unknown';
                  final subject = doc['subject'] ?? 'Subject';

                  // Check if this period is currently being edited
                  final bool isEditing = _selectedPeriod == periodNum;

                  return Card(
                    elevation: isEditing ? 4 : 2,
                    color: isEditing ? const Color(0xFFE3F2FD) : Colors.white,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: isEditing
                            ? const Color(0xFF2196F3)
                            : Colors.grey.shade300,
                        width: isEditing ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      title: Text('Period $periodNum - $subject'),
                      subtitle: Text(
                        'Present: $present / $total\nMarked by: $markedBy',
                      ),
                      isThreeLine: true,
                      trailing: ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            _selectedPeriod = periodNum;
                            _errorMessage = null;
                            _successMessage = null;
                          });
                          if (_students.isEmpty) {
                            await _loadStudentsForSelectedClass();
                          }
                          _loadExistingAttendanceIntoUI(doc);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isEditing
                              ? const Color(0xFF1976D2)
                              : const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Edit'),
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 12),
              ],
            ),

          // Student Attendance Section
          if (_students.isNotEmpty && _selectedPeriod != null)
            _buildStudentAttendanceSection()
          else if (_selectedClass != null && _students.isEmpty && !_isLoading)
            _buildEmptyState(
              icon: Icons.people_outline,
              title: 'No Students Found',
              subtitle: 'No students found in this class section',
            )
          else if (_selectedClass == null && !_isLoading)
            _buildEmptyState(
              icon: Icons.class_,
              title: 'Select Class',
              subtitle: 'Please select a class to mark attendance',
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(
                Icons.calendar_today,
                color: Color(0xFF2196F3),
              ),
              title: const Text('Selected Date'),
              subtitle: Text(DateFormat('MMMM d, yyyy').format(_selectedDate)),
              trailing: IconButton(
                icon: const Icon(Icons.edit_calendar, color: Color(0xFF2196F3)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = picked;
                    });
                    _loadAttendanceHistory();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Attendance History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _attendanceHistory.isEmpty
                ? _buildEmptyState(
                    icon: Icons.history,
                    title: 'No Records Found',
                    subtitle: 'No attendance records found for selected date',
                  )
                : ListView.builder(
                    itemCount: _attendanceHistory.length,
                    itemBuilder: (context, index) {
                      final record = _attendanceHistory[index];
                      final displayClassName = _formatClassName(
                        record['class_name'] ?? 'Unknown Class',
                        record['section'],
                      );
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(
                              0xFF2196F3,
                            ).withOpacity(0.1),
                            child: Text(
                              '${record['attendance_percentage']}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2196F3),
                              ),
                            ),
                          ),
                          title: Text(displayClassName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Period: ${record['period_number']} (${record['subject'] ?? 'Subject'})',
                              ),
                              Text(
                                'Present: ${record['present_count']}/${record['total_students']}',
                              ),
                              Text('Marked by: ${record['marked_by']}'),
                              if (record['updated_by'] != 'N/A')
                                Text('Updated by: ${record['updated_by']}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentAttendanceSection() {
    if (!_isToday && !_attendanceMarked) {
      return _buildEmptyState(
        icon: Icons.calendar_today,
        title: 'No Attendance Found',
        subtitle: 'Switch to today\'s date to mark attendance',
      );
    }

    return Column(
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedClass!['displayName'] ?? 'Class',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_attendanceMarked)
                      const Icon(Icons.verified, color: Colors.green),
                  ],
                ),
                if (_attendanceMarked) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Marked by: ${_markedByTeacherName ?? 'Unknown'}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  if (_updatedByTeacherName != null)
                    Text(
                      'Updated by: $_updatedByTeacherName',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      'Total',
                      _students.length.toString(),
                      Icons.people,
                    ),
                    _buildStatItem(
                      'Present',
                      _attendanceStatuses.values
                          .where((s) => s == 'present')
                          .length
                          .toString(),
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    _buildStatItem(
                      'Absent',
                      _attendanceStatuses.values
                          .where((s) => s == 'absent')
                          .length
                          .toString(),
                      Icons.cancel,
                      color: Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Students List - Fixed to have proper constraints
        Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _students.length,
            itemBuilder: (context, index) {
              final student = _students[index];
              final studentId = student['id'] as String;
              final status = _attendanceStatuses[studentId] ?? 'present';

              // Build display name with roll number
              String displayName = student['name'] as String;
              final rollNumber = student['rollNumber'] as String;
              if (rollNumber != 'N/A') {
                displayName = '$rollNumber. $displayName';
              }

              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF2196F3).withOpacity(0.1),
                    child: Text(
                      displayName[0].toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2196F3),
                      ),
                    ),
                  ),
                  title: Text(displayName),
                  subtitle: Text('ID: ${student['username']}'),
                  trailing: _leaveApplications.containsKey(studentId)
                      ? _buildLeaveAppliedBadge(studentId)
                      : _isToday
                          ? _buildStatusButton(studentId)
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(status),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status == 'present' ? 'Present' : 'Absent',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                ),
              );
            },
          ),
        ),

        // Save/Update Button - Now properly placed with constraints
        if (_isToday) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _buildActionButton(),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Info pages content
  Widget _buildInfoPage1() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How to Use This Screen',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2196F3),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.class_,
            'Select Class',
            'Choose the class and section you want to mark attendance for',
          ),
          _buildInfoItem(
            Icons.schedule,
            'Select Period',
            'Choose the period from the timetable (if available)',
          ),
          _buildInfoItem(
            Icons.people,
            'Mark Attendance',
            'Toggle between Present/Absent for each student',
          ),
          _buildInfoItem(
            Icons.save,
            'Save Attendance',
            'Save the attendance data for the selected period',
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
            'Tips & Best Practices',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2196F3),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            '📝',
            'Mark attendance at the beginning of each period',
          ),
          _buildTipItem(
            '🔄',
            'You can update attendance anytime during the day',
          ),
          _buildTipItem(
            '📊',
            'Attendance statistics help track student performance',
          ),
          _buildTipItem(
            '👥',
            'Only students in selected class section will appear',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF2196F3).withOpacity(0.3),
              ),
            ),
            child: const Text(
              'Need help? Contact your school administrator for assistance with attendance management.',
              style: TextStyle(fontSize: 12, color: Color(0xFF2196F3)),
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
          Icon(icon, size: 20, color: const Color(0xFF2196F3)),
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

  Widget _buildPageIndicator(int pageIndex) {
    return GestureDetector(
      onTap: () {
        _infoPageController.animateToPage(
          pageIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _currentInfoPage == pageIndex
              ? const Color(0xFF2196F3)
              : Colors.grey[300],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Row(
        children: [
          // Sidebar with info pages
          _buildDesktopSidebar(),
          // Main Content
          Expanded(
            child: Column(
              children: [
                _buildDesktopTopBar(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Messages
                        if (_errorMessage != null)
                          _buildMessage(_errorMessage!, true),
                        if (_successMessage != null)
                          _buildMessage(_successMessage!, false),
                        const SizedBox(height: 16),

                        // Tab Bar
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TabBar(
                            controller: _tabController,
                            labelColor: const Color(0xFF2196F3),
                            unselectedLabelColor: Colors.grey,
                            indicator: BoxDecoration(
                              color: const Color(0xFF2196F3).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontWeight: FontWeight.normal,
                            ),
                            tabs: const [
                              Tab(
                                icon: Icon(Icons.assignment_ind, size: 20),
                                text: 'Mark Attendance',
                              ),
                              Tab(
                                icon: Icon(Icons.history, size: 20),
                                text: 'Attendance History',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Tab Content
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildMarkAttendanceTab(),
                              _buildHistoryTab(),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          _isMobile ? 'Attendance' : 'Attendance - ${widget.schoolName}',
          style: TextStyle(
            fontSize: _isMobile ? 18 : 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFFE3F2FD),
        foregroundColor: const Color(0xFF2196F3),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2196F3),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF2196F3),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.assignment_ind), text: 'Mark Attendance'),
            Tab(icon: Icon(Icons.history), text: 'Attendance History'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Messages
                  if (_errorMessage != null)
                    _buildMessage(_errorMessage!, true),
                  if (_successMessage != null)
                    _buildMessage(_successMessage!, false),
                  const SizedBox(height: 16),

                  // Compact Statistics for Mobile/Tablet
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildCompactStatItem(
                            _allClasses.length.toString(),
                            'Classes',
                          ),
                          _buildCompactStatItem(
                            _students.length.toString(),
                            'Students',
                          ),
                          _buildCompactStatItem(
                            _periods.length.toString(),
                            'Periods',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tab Content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [_buildMarkAttendanceTab(), _buildHistoryTab()],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return _buildDesktopLayout();
    } else {
      return _buildMobileTabletLayout();
    }
  }
}
