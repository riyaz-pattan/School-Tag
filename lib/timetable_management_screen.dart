import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'all_timetables_screen.dart';

class TimetableManagementScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;

  const TimetableManagementScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<TimetableManagementScreen> createState() =>
      _TimetableManagementScreenState();
}

class _TimetableManagementScreenState extends State<TimetableManagementScreen> {
  String? _selectedClassId;
  Map<String, dynamic>? _selectedClassData;
  List<Map<String, dynamic>> _dailySchedule = [];
  List<String> _workingDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
  ];
  bool _isUniformSchedule = true;
  String? _errorMessage;
  String? _successMessage;
  bool _isLoading = false;
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _subjects = [];
  final _numPeriodsController = TextEditingController();
  Map<String, dynamic>? _existingTimetable;
  bool _showTimetableGrid = false;
  Map<String, List<Map<String, dynamic>>> _nonUniformTimetable = {};

  // Cache variables
  List<Map<String, dynamic>> _cachedClasses = [];
  DateTime? _lastTeachersCacheUpdate;
  DateTime? _lastSubjectsCacheUpdate;
  DateTime? _lastClassesCacheUpdate;
  static const int _cacheDurationMinutes = 30;

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
    _loadCachedData();
    _loadTeachers();
    _loadSubjects();
    _loadCachedClasses();
  }

  // Add this method to handle back button
  Future<bool> _onWillPop() async {
    // If we're showing timetable grid or have selected class, reset the state
    if (_showTimetableGrid || _selectedClassId != null) {
      setState(() {
        _showTimetableGrid = false;
        _selectedClassId = null;
        _selectedClassData = null;
        _dailySchedule = [];
        _successMessage = null;
        _errorMessage = null;
      });
      return false; // Don't navigate back yet
    }
    return true; // Allow navigation back
  }

  // Timestamp conversion methods
  dynamic _convertTimestamp(dynamic value) {
    if (value is Timestamp) {
      return {
        '_type': 'timestamp',
        'seconds': value.seconds,
        'nanoseconds': value.nanoseconds,
      };
    }
    return value;
  }

  dynamic _restoreTimestamp(dynamic value) {
    if (value is Map && value['_type'] == 'timestamp') {
      return Timestamp(value['seconds'], value['nanoseconds']);
    }
    return value;
  }

  Map<String, dynamic> _convertMapToSerializable(Map<String, dynamic> data) {
    final converted = <String, dynamic>{};
    data.forEach((key, value) {
      if (value is Timestamp) {
        converted[key] = _convertTimestamp(value);
      } else if (value is List) {
        converted[key] = value.map((e) => _convertTimestamp(e)).toList();
      } else if (value is Map) {
        converted[key] = _convertMapToSerializable(
          Map<String, dynamic>.from(value),
        );
      } else {
        converted[key] = value;
      }
    });
    return converted;
  }

  Map<String, dynamic> _restoreMapFromSerializable(Map<String, dynamic> data) {
    final restored = <String, dynamic>{};
    data.forEach((key, value) {
      if (value is Map && value['_type'] == 'timestamp') {
        restored[key] = _restoreTimestamp(value);
      } else if (value is List) {
        restored[key] = value.map((e) => _restoreTimestamp(e)).toList();
      } else if (value is Map) {
        restored[key] = _restoreMapFromSerializable(
          Map<String, dynamic>.from(value),
        );
      } else {
        restored[key] = value;
      }
    });
    return restored;
  }

  // Load all cached data
  Future<void> _loadCachedData() async {
    await _loadCachedTeachers();
    await _loadCachedSubjects();
  }

  // Cache management for teachers
  Future<void> _loadCachedTeachers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cached_teachers_${widget.schoolCode}';
      final cachedData = prefs.getString(cacheKey);

      if (cachedData != null) {
        final cacheMap = json.decode(cachedData) as Map<String, dynamic>;
        final lastUpdate = DateTime.parse(cacheMap['lastUpdate'] as String);

        if (DateTime.now().difference(lastUpdate).inMinutes <
            _cacheDurationMinutes) {
          final teachers = (cacheMap['teachers'] as List<dynamic>)
              .map(
                (e) => _restoreMapFromSerializable(e as Map<String, dynamic>),
              )
              .toList();

          setState(() {
            _teachers = List<Map<String, dynamic>>.from(teachers);
            _lastTeachersCacheUpdate = lastUpdate;
          });
        }
      }
    } catch (e) {
      print('Error loading cached teachers: $e');
    }
  }

  Future<void> _saveTeachersToCache(List<Map<String, dynamic>> teachers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cached_teachers_${widget.schoolCode}';

      final serializableTeachers = teachers
          .map((teacher) => _convertMapToSerializable(teacher))
          .toList();

      final cacheData = {
        'lastUpdate': DateTime.now().toIso8601String(),
        'teachers': serializableTeachers,
      };
      await prefs.setString(cacheKey, json.encode(cacheData));

      setState(() {
        _lastTeachersCacheUpdate = DateTime.now();
      });
    } catch (e) {
      print('Error saving teachers to cache: $e');
    }
  }

  // Cache management for subjects
  Future<void> _loadCachedSubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cached_subjects_${widget.schoolCode}';
      final cachedData = prefs.getString(cacheKey);

      if (cachedData != null) {
        final cacheMap = json.decode(cachedData) as Map<String, dynamic>;
        final lastUpdate = DateTime.parse(cacheMap['lastUpdate'] as String);

        if (DateTime.now().difference(lastUpdate).inMinutes <
            _cacheDurationMinutes) {
          final subjects = (cacheMap['subjects'] as List<dynamic>)
              .map(
                (e) => _restoreMapFromSerializable(e as Map<String, dynamic>),
              )
              .toList();

          setState(() {
            _subjects = List<Map<String, dynamic>>.from(subjects);
            _lastSubjectsCacheUpdate = lastUpdate;
          });
        }
      }
    } catch (e) {
      print('Error loading cached subjects: $e');
    }
  }

  Future<void> _saveSubjectsToCache(List<Map<String, dynamic>> subjects) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cached_subjects_${widget.schoolCode}';

      final serializableSubjects = subjects
          .map((subject) => _convertMapToSerializable(subject))
          .toList();

      final cacheData = {
        'lastUpdate': DateTime.now().toIso8601String(),
        'subjects': serializableSubjects,
      };
      await prefs.setString(cacheKey, json.encode(cacheData));

      setState(() {
        _lastSubjectsCacheUpdate = DateTime.now();
      });
    } catch (e) {
      print('Error saving subjects to cache: $e');
    }
  }

  // Cache management for classes
  Future<void> _loadCachedClasses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cached_classes_${widget.schoolCode}';
      final cachedData = prefs.getString(cacheKey);

      if (cachedData != null) {
        final cacheMap = json.decode(cachedData) as Map<String, dynamic>;
        final lastUpdate = DateTime.parse(cacheMap['lastUpdate'] as String);

        if (DateTime.now().difference(lastUpdate).inMinutes <
            _cacheDurationMinutes) {
          final classes = (cacheMap['classes'] as List<dynamic>)
              .map(
                (e) => _restoreMapFromSerializable(e as Map<String, dynamic>),
              )
              .toList();

          setState(() {
            _cachedClasses = List<Map<String, dynamic>>.from(classes);
            _lastClassesCacheUpdate = lastUpdate;
          });
        }
      }
    } catch (e) {
      print('Error loading cached classes: $e');
    }
  }

  Future<void> _saveClassesToCache(List<Map<String, dynamic>> classes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cached_classes_${widget.schoolCode}';

      final serializableClasses = classes
          .map((classData) => _convertMapToSerializable(classData))
          .toList();

      final cacheData = {
        'lastUpdate': DateTime.now().toIso8601String(),
        'classes': serializableClasses,
      };
      await prefs.setString(cacheKey, json.encode(cacheData));

      setState(() {
        _cachedClasses = classes;
        _lastClassesCacheUpdate = DateTime.now();
      });
    } catch (e) {
      print('Error saving classes to cache: $e');
    }
  }

  // Clear all cache
  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_teachers_${widget.schoolCode}');
      await prefs.remove('cached_subjects_${widget.schoolCode}');
      await prefs.remove('cached_classes_${widget.schoolCode}');

      setState(() {
        _teachers = [];
        _subjects = [];
        _cachedClasses = [];
        _lastTeachersCacheUpdate = null;
        _lastSubjectsCacheUpdate = null;
        _lastClassesCacheUpdate = null;
      });

      // Reload data
      _loadTeachers();
      _loadSubjects();
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  Future<void> _loadTeachers() async {
    // If we have cached teachers and they're still valid, don't fetch from Firestore
    if (_teachers.isNotEmpty &&
        _lastTeachersCacheUpdate != null &&
        DateTime.now().difference(_lastTeachersCacheUpdate!).inMinutes <
            _cacheDurationMinutes) {
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'teacher')
          .get();

      final teachers = snapshot.docs.map((doc) {
        final data = doc.data();
        final username = data['username'] ?? 'Unknown';
        final fullName = data['full_name'] ?? '';
        // Use full_name if available, otherwise use username
        final displayName = fullName.isNotEmpty ? fullName : username;
        return {
          'id': doc.id,
          'name': displayName, // This will be used for display
          'username': username, // Keep username for reference
          'full_name': fullName, // Keep full_name for reference
        };
      }).toList();

      setState(() {
        _teachers = teachers;
      });
      _saveTeachersToCache(teachers);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading teachers: $e';
      });
    }
  }

  Future<void> _loadSubjects() async {
    // If we have cached subjects and they're still valid, don't fetch from Firestore
    if (_subjects.isNotEmpty &&
        _lastSubjectsCacheUpdate != null &&
        DateTime.now().difference(_lastSubjectsCacheUpdate!).inMinutes <
            _cacheDurationMinutes) {
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('subjects')
          .orderBy('subject_name')
          .get();

      final subjects = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'subject_id': data['subject_id'],
          'subject_name': data['subject_name'],
          'teacher_ids': List<String>.from(data['teacher_ids'] ?? []),
          'teacher_names': List<String>.from(data['teacher_names'] ?? []),
        };
      }).toList();

      setState(() {
        _subjects = subjects;
      });
      _saveSubjectsToCache(subjects);
    } catch (e) {
      print('Error loading subjects: $e');
    }
  }

  Future<void> _loadExistingTimetable() async {
    if (_selectedClassId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .doc(_selectedClassId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _existingTimetable = data;
          _workingDays = List<String>.from(
            data['working_days'] ?? _workingDays,
          );
          _isUniformSchedule = data['is_uniform'] ?? true;

          if (data['timetable'] != null) {
            final timetable = data['timetable'] as Map<String, dynamic>;
            if (_isUniformSchedule) {
              final firstDay = timetable.keys.first;
              _dailySchedule = List<Map<String, dynamic>>.from(
                timetable[firstDay] ?? [],
              );
            } else {
              _nonUniformTimetable =
                  Map<String, List<Map<String, dynamic>>>.from(
                    timetable.map(
                      (key, value) =>
                          MapEntry(key, List<Map<String, dynamic>>.from(value)),
                    ),
                  );
              _dailySchedule = _nonUniformTimetable.values.first ?? [];
            }

            if (_dailySchedule.isNotEmpty) {
              _dailySchedule = _sortScheduleByTime(_dailySchedule);
            }
          }
        });
      } else {
        setState(() {
          _existingTimetable = null;
          _dailySchedule = [];
          _nonUniformTimetable = {};
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading timetable: $e';
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

  void _handleClassSelection(
    String? value,
    List<Map<String, dynamic>> classes,
  ) {
    if (value == null) return;

    final selectedClass = classes.firstWhere(
      (classMap) => classMap['id'] == value,
    );
    final classData = selectedClass;

    setState(() {
      _selectedClassId = value;
      _selectedClassData = classData;
      _showTimetableGrid = false;
      _dailySchedule = [];
      _nonUniformTimetable = {};
      _numPeriodsController.clear();
    });

    _checkExistingTimetable();
  }

  Future<void> _checkExistingTimetable() async {
    if (_selectedClassId == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolCode)
        .collection('timetables')
        .doc(_selectedClassId)
        .get();

    if (doc.exists) {
      _showTimetableOptionsDialog();
    } else {
      setState(() {
        _existingTimetable = null;
        _dailySchedule = [];
        _showTimetableGrid = false;
      });
    }
  }

  void _showTimetableOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Timetable Exists'),
        content: const Text(
          'This class already has a timetable. What would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _loadExistingTimetableForEdit();
            },
            child: const Text('Edit Existing'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _createNewTimetable();
            },
            child: const Text('Create New'),
          ),
        ],
      ),
    );
  }

  void _loadExistingTimetableForEdit() async {
    await _loadExistingTimetable();
    setState(() {
      _showTimetableGrid = true;
    });
  }

  void _createNewTimetable() {
    setState(() {
      _existingTimetable = null;
      _dailySchedule = [];
      _nonUniformTimetable = {};
      _numPeriodsController.clear();
      _showTimetableGrid = false;
      _showFloatingMessage('Create a new timetable for this class', false);
    });
  }

  Future<void> _saveTimetable() async {
    if (_selectedClassId == null || _dailySchedule.isEmpty) {
      setState(() {
        _errorMessage = 'Please select a class and configure the schedule';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final grade = _selectedClassData?['grade'] ?? 'Unknown';
      final sections = _selectedClassData?['sections'] ?? [];

      final sortedSchedule = _sortScheduleByTime(_dailySchedule);

      final timetableData = {
        'grade': grade,
        'sections': sections,
        'class_name': _getClassName(grade, sections),
        'working_days': _workingDays,
        'is_uniform': _isUniformSchedule,
        'timetable': _isUniformSchedule
            ? {for (var day in _workingDays) day.toLowerCase(): sortedSchedule}
            : _nonUniformTimetable,
        'updated_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .doc(_selectedClassId)
          .set(timetableData);

      setState(() {
        _showFloatingMessage('Timetable saved successfully', false);
        _isLoading = false;
        _existingTimetable = timetableData;
        _dailySchedule = sortedSchedule;
        _showTimetableGrid = true;
      });
    } catch (e) {
      setState(() {
        _showFloatingMessage('Error saving timetable: $e', true);
        _isLoading = false;
      });
    }
  }

  String _getClassName(String grade, List<dynamic> sections) {
    if (sections.isEmpty) return grade;
    return '$grade (${sections.join(', ')})';
  }

  void _configureDailySchedule() {
    final numPeriods = int.tryParse(_numPeriodsController.text) ?? 0;
    if (numPeriods <= 0) {
      setState(() {
        _showFloatingMessage('Please enter a valid number of periods', true);
        _successMessage = null;
      });
      return;
    }

    showDialog(
      context: context,
      builder: (context) => ScheduleConfigDialog(
        numPeriods: numPeriods,
        teachers: _teachers,
        subjects: _subjects,
        existingSchedule: _dailySchedule,
        onScheduleConfigured: (schedule) {
          final sortedSchedule = _sortScheduleByTime(schedule);

          setState(() {
            _dailySchedule = sortedSchedule;
            if (!_isUniformSchedule) {
              for (var day in _workingDays) {
                _nonUniformTimetable[day.toLowerCase()] = List.from(
                  sortedSchedule,
                );
              }
            }
            _errorMessage = null;
            _successMessage = 'Daily schedule configured';
            _showTimetableGrid = true;
          });
        },
      ),
    );
  }

  void _editPeriodSlot(int periodIndex, String day) {
    final dayKey = day.toLowerCase();
    final periodData = _isUniformSchedule
        ? _dailySchedule[periodIndex]
        : _nonUniformTimetable[dayKey]?[periodIndex] ??
              _dailySchedule[periodIndex];

    // Check if the assigned teacher still exists
    final teacherId = periodData['teacher_id'];
    final teacherExists =
        teacherId == null ||
        _teachers.any((teacher) => teacher['id'] == teacherId);

    // Check if the subject still exists
    final subjectName = periodData['subject'];
    final subjectExists =
        subjectName == null ||
        _subjects.any((subject) => subject['subject_name'] == subjectName);

    showDialog(
      context: context,
      builder: (context) => PeriodEditDialog(
        periodData: Map<String, dynamic>.from(periodData),
        teachers: _teachers,
        subjects: _subjects,
        day: day,
        teacherExists: teacherExists,
        subjectExists: subjectExists,
        onPeriodUpdated: (updatedData) {
          setState(() {
            if (_isUniformSchedule) {
              for (var currentDay in _workingDays) {
                final currentDayKey = currentDay.toLowerCase();
                if (!_nonUniformTimetable.containsKey(currentDayKey)) {
                  _nonUniformTimetable[currentDayKey] = List.from(
                    _dailySchedule,
                  );
                }
                _nonUniformTimetable[currentDayKey]![periodIndex] = updatedData;
              }
              _dailySchedule[periodIndex] = updatedData;
            } else {
              if (!_nonUniformTimetable.containsKey(dayKey)) {
                _nonUniformTimetable[dayKey] = List.from(_dailySchedule);
              }
              _nonUniformTimetable[dayKey]![periodIndex] = updatedData;
            }
          });
        },
      ),
    );
  }

  Map<String, dynamic> _getPeriodData(int periodIndex, String day) {
    if (!_isUniformSchedule) {
      final dayData = _nonUniformTimetable[day.toLowerCase()];
      if (dayData != null && dayData.length > periodIndex) {
        return dayData[periodIndex];
      }
    }
    return _dailySchedule[periodIndex];
  }

  void _resetTimetable() {
    setState(() {
      _dailySchedule = [];
      _nonUniformTimetable = {};
      _numPeriodsController.clear();
      _successMessage = null;
      _errorMessage = null;
      _showTimetableGrid = false;
    });
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return DateFormat('MMM dd, yyyy HH:mm').format(timestamp.toDate());
    } else if (timestamp is DateTime) {
      return DateFormat('MMM dd, yyyy HH:mm').format(timestamp);
    } else {
      return 'Unknown';
    }
  }

  // Get classes stream with caching
  Stream<List<Map<String, dynamic>>> _getClassesStream() {
    return FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolCode)
        .collection('classes')
        .snapshots()
        .asyncMap((snapshot) async {
          final classes = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'grade': data['grade'],
              'sections': data['sections'],
              'created_at': data['created_at'],
            };
          }).toList();

          // Save to cache whenever we get fresh data
          await _saveClassesToCache(classes);
          return classes;
        });
  }

  @override
  void dispose() {
    _numPeriodsController.dispose();
    super.dispose();
  }

  // Desktop layout components
  Widget _buildDesktopSidebar() {
    return Container(
      width: 300,
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
                    child: Icon(
                      Icons.schedule,
                      size: 40,
                      color: Color.fromARGB(255, 22, 105, 200),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Timetable Management',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromARGB(255, 21, 100, 191),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    widget.schoolName,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AllTimetablesScreen(
                        schoolCode: widget.schoolCode,
                        schoolName: widget.schoolName,
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.list, color: Colors.blue[700]),
                label: Text(
                  'View All Timetables',
                  style: TextStyle(color: Colors.blue[700]),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.blue.withOpacity(0.5)),
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

  // Add these new methods to the _TimetableManagementScreenState class:

  final PageController _infoPageController = PageController();
  int _currentInfoPage = 0;

  Widget _buildInfoPage1() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to Manage Timetables',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.class_,
            'Select Class',
            'Choose a class from the dropdown to manage its timetable',
          ),
          _buildInfoItem(
            Icons.settings,
            'Configure Schedule',
            'Set number of periods, working days, and schedule type',
          ),
          _buildInfoItem(
            Icons.edit,
            'Edit Periods',
            'Click on any period in the grid to edit subject and teacher',
          ),
          _buildInfoItem(
            Icons.save,
            'Save Changes',
            'Remember to save your timetable after making changes',
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
          Text(
            'Tips & Best Practices',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            '📅',
            'Plan your weekly schedule considering teacher availability',
          ),
          _buildTipItem(
            '⏰',
            'Ensure proper time gaps between periods for breaks',
          ),
          _buildTipItem(
            '👨‍🏫',
            'Assign teachers based on their subject expertise',
          ),
          _buildTipItem(
            '🔄',
            'Use uniform schedule for consistency across all days',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[100]!),
            ),
            child: const Text(
              'Need help? Use the "View All Timetables" button below to see and edit all class timetables at once.',
              style: TextStyle(fontSize: 12, color: Colors.blue),
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
          Icon(icon, size: 20, color: Colors.blue[700]),
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
              ? Color.fromARGB(255, 21, 101, 192)
              : Colors.grey[300],
        ),
      ),
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
        style: TextStyle(color: Color.fromARGB(255, 96, 96, 96)),
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
          // Add back button - ALWAYS VISIBLE in timetable management
          IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.blue),
            onPressed: () {
              Navigator.of(context).pop();
            },
            tooltip: 'Back to Dashboard',
          ),
          SizedBox(width: 8),
          Text(
            'Timetable Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 103, 195),
            ),
          ),
          const Spacer(),
          if (_lastClassesCacheUpdate != null ||
              _lastTeachersCacheUpdate != null ||
              _lastSubjectsCacheUpdate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_done, size: 14, color: Colors.green[700]),
                  const SizedBox(width: 6),
                  Text(
                    'Cached Data',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 16),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.blue),
            onPressed: _clearCache,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return PopScope(
      canPop: !_showTimetableGrid && _selectedClassId == null,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop) {
          // Handle back button when we prevent pop
          if (_showTimetableGrid || _selectedClassId != null) {
            setState(() {
              _showTimetableGrid = false;
              _selectedClassId = null;
              _selectedClassData = null;
              _dailySchedule = [];
              _successMessage = null;
              _errorMessage = null;
            });
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
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(_isDesktop ? 24 : 16),
                    child: _buildMainContent(),
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
      appBar: AppBar(
        title: Text(
          _isMobile ? 'Timetable' : 'Timetable Management',
          style: TextStyle(fontSize: _isMobile ? 18 : 20),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Color.fromARGB(255, 21, 101, 192),
        elevation: 0,
        actions: [
          if (_lastClassesCacheUpdate != null ||
              _lastTeachersCacheUpdate != null ||
              _lastSubjectsCacheUpdate != null)
            IconButton(
              icon: Icon(Icons.cloud_done, color: Colors.green),
              onPressed: () {},
              tooltip: 'Using cached data',
            ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _clearCache,
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: Icon(Icons.list),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AllTimetablesScreen(
                    schoolCode: widget.schoolCode,
                    schoolName: widget.schoolName,
                  ),
                ),
              );
            },
            tooltip: 'View All Timetables',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(_isMobile ? 16 : 20),
        child: _buildMainContent(),
      ),
    );
  }

  void _showFloatingMessage(String message, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(_isMobile ? 16 : 24),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 0),
        // Class Selection Card
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: EdgeInsets.all(_isDesktop ? 24 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Class',
                  style: TextStyle(
                    fontSize: _isMobile ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
                ),
                SizedBox(height: 16),
                _buildClassDropdown(),
              ],
            ),
          ),
        ),

        SizedBox(height: 20),

        // Existing Timetable Info
        if (_existingTimetable != null && _selectedClassId != null)
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: EdgeInsets.all(_isDesktop ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Existing Timetable',
                    style: TextStyle(
                      fontSize: _isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 21, 101, 192),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Class: ${_existingTimetable!['class_name'] ?? 'Unknown'}',
                    style: TextStyle(fontSize: _isMobile ? 14 : 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Grade: ${_existingTimetable!['grade'] ?? 'Unknown'}',
                    style: TextStyle(fontSize: _isMobile ? 14 : 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Sections: ${(_existingTimetable!['sections'] as List<dynamic>?)?.join(', ') ?? 'None'}',
                    style: TextStyle(fontSize: _isMobile ? 14 : 16),
                  ),
                  if (_existingTimetable!['updated_at'] != null) ...[
                    SizedBox(height: 8),
                    Text(
                      'Last Updated: ${_formatTimestamp(_existingTimetable!['updated_at'])}',
                      style: TextStyle(
                        fontSize: _isMobile ? 12 : 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadExistingTimetableForEdit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      padding: EdgeInsets.symmetric(
                        horizontal: _isMobile ? 16 : 24,
                        vertical: _isMobile ? 12 : 16,
                      ),
                    ),
                    child: Text(
                      'Edit Existing Timetable',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _isMobile ? 14 : 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        SizedBox(height: 20),

        // Schedule Configuration
        if (_selectedClassId != null && !_showTimetableGrid)
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: EdgeInsets.all(_isDesktop ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configure Schedule',
                    style: TextStyle(
                      fontSize: _isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 21, 101, 192),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _numPeriodsController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Number of Periods per Day',
                      hintText: 'Enter number (e.g., 5)',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey[50],
                      suffixIcon: _dailySchedule.isNotEmpty
                          ? Icon(Icons.check_circle, color: Colors.green)
                          : null,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Working Days',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        [
                          'Monday',
                          'Tuesday',
                          'Wednesday',
                          'Thursday',
                          'Friday',
                          'Saturday',
                          'Sunday',
                        ].map((day) {
                          return ChoiceChip(
                            label: Text(day),
                            selected: _workingDays.contains(day),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _workingDays.add(day);
                                } else {
                                  _workingDays.remove(day);
                                }
                              });
                            },
                            selectedColor: Colors.blue[100],
                            labelStyle: TextStyle(
                              color: _workingDays.contains(day)
                                  ? Colors.blue[700]
                                  : Colors.grey[700],
                            ),
                          );
                        }).toList(),
                  ),
                  SizedBox(height: 16),
                  CheckboxListTile(
                    title: Text(
                      'Same schedule for all working days?',
                      style: TextStyle(fontSize: _isMobile ? 14 : 16),
                    ),
                    subtitle: Text(
                      'If unchecked, you can configure each day individually',
                      style: TextStyle(fontSize: _isMobile ? 12 : 14),
                    ),
                    value: _isUniformSchedule,
                    onChanged: (value) {
                      setState(() {
                        _isUniformSchedule = value ?? true;
                        if (!_isUniformSchedule && _dailySchedule.isNotEmpty) {
                          for (var day in _workingDays) {
                            _nonUniformTimetable[day.toLowerCase()] = List.from(
                              _dailySchedule,
                            );
                          }
                        }
                      });
                    },
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _configureDailySchedule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      padding: EdgeInsets.symmetric(
                        horizontal: _isMobile ? 24 : 32,
                        vertical: _isMobile ? 16 : 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Configure Daily Schedule',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _isMobile ? 14 : 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        SizedBox(height: 20),

        // Timetable Grid
        if (_showTimetableGrid && _dailySchedule.isNotEmpty)
          _buildTimetableGrid(),

        SizedBox(height: 20),

        // Action Buttons
        if (_dailySchedule.isNotEmpty && !_showTimetableGrid)
          Row(
            children: [
              ElevatedButton(
                onPressed: _saveTimetable,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: EdgeInsets.symmetric(
                    horizontal: _isMobile ? 24 : 32,
                    vertical: _isMobile ? 16 : 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : Text(
                        'Save Timetable',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _isMobile ? 14 : 16,
                        ),
                      ),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: _resetTimetable,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  padding: EdgeInsets.symmetric(
                    horizontal: _isMobile ? 24 : 32,
                    vertical: _isMobile ? 16 : 20,
                  ),
                ),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _isMobile ? 14 : 16,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildClassDropdown() {
    // Use cached classes initially, then stream for updates
    if (_cachedClasses.isNotEmpty) {
      return _buildClassDropdownFromList(_cachedClasses);
    }

    // Fall back to stream if no cache
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getClassesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _cachedClasses.isEmpty) {
          return const CircularProgressIndicator();
        }

        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }

        final classes = snapshot.hasData ? snapshot.data! : _cachedClasses;
        return _buildClassDropdownFromList(classes);
      },
    );
  }

  Widget _buildClassDropdownFromList(List<Map<String, dynamic>> classes) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: 'Class',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      items: classes.map((classMap) {
        final grade = classMap['grade'] ?? 'Unknown';
        final sections =
            (classMap['sections'] as List<dynamic>?)?.join(', ') ?? '';
        final displayName = sections.isEmpty ? grade : '$grade ($sections)';
        return DropdownMenuItem<String>(
          value: classMap['id'],
          child: Text(displayName),
        );
      }).toList(),
      onChanged: (value) => _handleClassSelection(value, classes),
    );
  }

  Widget _buildTimetableGrid() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(_isDesktop ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Timetable Grid',
                  style: TextStyle(
                    fontSize: _isMobile ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _saveTimetable,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: EdgeInsets.symmetric(
                          horizontal: _isMobile ? 16 : 24,
                          vertical: _isMobile ? 12 : 16,
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Save Changes',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: _isMobile ? 12 : 14,
                              ),
                            ),
                    ),
                    ElevatedButton(
                      onPressed: _resetTimetable,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: EdgeInsets.symmetric(
                          horizontal: _isMobile ? 16 : 24,
                          vertical: _isMobile ? 12 : 16,
                        ),
                      ),
                      child: Text(
                        'Create New',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _isMobile ? 12 : 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              _isUniformSchedule
                  ? 'Uniform Schedule (Changes apply to all days)'
                  : 'Non-Uniform Schedule (Edit individual days)',
              style: TextStyle(
                color: _isUniformSchedule ? Colors.blue : Colors.purple,
                fontWeight: FontWeight.w500,
                fontSize: _isMobile ? 12 : 14,
              ),
            ),
            SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildTraditionalTimetable(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTraditionalTimetable() {
    return Table(
      border: TableBorder.all(color: Colors.grey[300]!),
      defaultColumnWidth: FixedColumnWidth(_isMobile ? 120 : 150),
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.blue[50]),
          children: [
            _buildDiagonalSplitCell(),
            ..._dailySchedule.asMap().entries.map((entry) {
              final index = entry.key;
              final slot = entry.value;
              return Container(
                height: _isMobile ? 60 : 80,
                padding: EdgeInsets.all(_isMobile ? 4 : 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${slot['type'] == 'period' ? 'Period ${slot['number']}' : slot['name'] ?? 'Break'}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: _isMobile ? 10 : 14,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: _isMobile ? 2 : 4),
                    Text(
                      '${slot['start_time']}',
                      style: TextStyle(fontSize: _isMobile ? 8 : 12),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${slot['end_time']}',
                      style: TextStyle(fontSize: _isMobile ? 8 : 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
        ..._workingDays.map((day) {
          return TableRow(
            decoration: BoxDecoration(
              color: _workingDays.indexOf(day) % 2 == 0
                  ? Colors.white
                  : Colors.grey[50],
            ),
            children: [
              Container(
                height: _isMobile ? 60 : 80,
                padding: EdgeInsets.all(_isMobile ? 8 : 12),
                child: Center(
                  child: Text(
                    _isMobile ? day.substring(0, 3) : day.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: _isMobile ? 10 : 14,
                    ),
                  ),
                ),
              ),
              ..._dailySchedule.asMap().entries.map((entry) {
                final index = entry.key;
                final periodData = _getPeriodData(index, day);

                return GestureDetector(
                  onTap: () => _editPeriodSlot(index, day),
                  child: Container(
                    height: _isMobile ? 60 : 80,
                    padding: EdgeInsets.all(_isMobile ? 4 : 8),
                    child: Stack(
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (periodData['type'] == 'period') ...[
                              Text(
                                periodData['subject'] ?? 'No Subject',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: _isMobile ? 10 : 14,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: _isMobile ? 2 : 4),
                              Text(
                                periodData['teacher_name'] ?? 'Unassigned',
                                style: TextStyle(
                                  fontSize: _isMobile ? 8 : 12,
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
                                  fontSize: _isMobile ? 10 : 14,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Icon(
                            Icons.edit,
                            size: _isMobile ? 12 : 16,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        }).toList(),
      ],
    );
  }

  Widget _buildDiagonalSplitCell() {
    return Container(
      height: _isMobile ? 60 : 80,
      child: Stack(
        children: [
          CustomPaint(
            size: Size(_isMobile ? 120 : 150, _isMobile ? 60 : 80),
            painter: DiagonalLinePainter(),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.only(
                top: _isMobile ? 4 : 8,
                right: _isMobile ? 4 : 8,
              ),
              child: Text(
                'PERIODS',
                style: TextStyle(
                  fontSize: _isMobile ? 8 : 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: _isMobile ? 4 : 8,
                left: _isMobile ? 4 : 8,
              ),
              child: Text(
                'DAYS',
                style: TextStyle(
                  fontSize: _isMobile ? 8 : 12,
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

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(body: _buildDesktopLayout());
    } else {
      return _buildMobileTabletLayout();
    }
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

class ScheduleConfigDialog extends StatefulWidget {
  final int numPeriods;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> subjects;
  final List<Map<String, dynamic>> existingSchedule;
  final Function(List<Map<String, dynamic>>) onScheduleConfigured;

  const ScheduleConfigDialog({
    super.key,
    required this.numPeriods,
    required this.teachers,
    required this.subjects,
    required this.existingSchedule,
    required this.onScheduleConfigured,
  });

  @override
  State<ScheduleConfigDialog> createState() => _ScheduleConfigDialogState();
}

class _ScheduleConfigDialogState extends State<ScheduleConfigDialog> {
  late List<PeriodData> _periodsData;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    if (widget.existingSchedule.isNotEmpty) {
      _periodsData = widget.existingSchedule.asMap().entries.map((entry) {
        final index = entry.key;
        final slot = entry.value;
        return PeriodData(
          index: index,
          isBreak: slot['type'] == 'break',
          startTime: _parseTime(slot['start_time']),
          endTime: _parseTime(slot['end_time']),
          subject: slot['subject'] ?? '',
          teacherId: slot['teacher_id'],
          breakName: slot['name'] ?? 'Break',
        );
      }).toList();
    } else {
      _periodsData = List.generate(
        widget.numPeriods,
        (index) => PeriodData(index: index, isBreak: false),
      );
    }
  }

  TimeOfDay? _parseTime(String? timeString) {
    if (timeString == null) return null;
    try {
      final format = DateFormat.jm();
      final date = format.parse(timeString);
      return TimeOfDay.fromDateTime(date);
    } catch (e) {
      return null;
    }
  }

  void _addBreak() {
    setState(() {
      _periodsData.add(
        PeriodData(
          index: _periodsData.length,
          isBreak: true,
          breakName: 'Break',
        ),
      );
    });
  }

  void _saveSchedule() {
    for (var period in _periodsData) {
      if (period.startTime == null || period.endTime == null) {
        setState(() {
          _dialogError = 'Please set time for all periods and breaks';
        });
        return;
      }

      if (!period.isBreak) {
        if (period.subject.isEmpty) {
          setState(() {
            _dialogError = 'Please enter subject for all periods';
          });
          return;
        }
      }
    }

    final schedule = _periodsData.map((period) {
      final teacher = widget.teachers.firstWhere(
        (t) => t['id'] == period.teacherId,
        orElse: () => {'name': 'Unassigned'},
      );

      if (period.isBreak) {
        return {
          'type': 'break',
          'name': period.breakName,
          'start_time': period.startTime!.format(context),
          'end_time': period.endTime!.format(context),
        };
      } else {
        return {
          'type': 'period',
          'number': period.index + 1,
          'subject': period.subject,
          'teacher_id': period.teacherId,
          'teacher_name': teacher['name'],
          'start_time': period.startTime!.format(context),
          'end_time': period.endTime!.format(context),
        };
      }
    }).toList();

    widget.onScheduleConfigured(schedule);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isDesktop = MediaQuery.of(context).size.width >= 1200;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: isDesktop
            ? 600
            : (isMobile ? double.infinity : 700), // Fixed width for web
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Makes it compact
            children: [
              Text(
                'Configure Daily Schedule',
                style: TextStyle(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
              SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < _periodsData.length; i++)
                        _PeriodInput(
                          periodData: _periodsData[i],
                          teachers: widget.teachers,
                          subjects: widget.subjects,
                          onDataChanged: () => setState(() {}),
                          lastEndTime: i > 0
                              ? _periodsData[i - 1].endTime
                              : null,
                          onRemove: i >= widget.numPeriods
                              ? () {
                                  setState(() {
                                    _periodsData.removeAt(i);
                                    for (
                                      int j = i;
                                      j < _periodsData.length;
                                      j++
                                    ) {
                                      _periodsData[j].index = j;
                                    }
                                  });
                                }
                              : null,
                        ),
                      SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _addBreak,
                        icon: Icon(Icons.add, size: isMobile ? 16 : 20),
                        label: Text(
                          'Add Break',
                          style: TextStyle(fontSize: isMobile ? 12 : 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      if (_dialogError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _dialogError!,
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: isMobile ? 12 : 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontSize: isMobile ? 12 : 14),
                    ),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveSchedule,
                    child: Text(
                      'Save',
                      style: TextStyle(fontSize: isMobile ? 12 : 14),
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
}

class PeriodEditDialog extends StatefulWidget {
  final Map<String, dynamic> periodData;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> subjects;
  final String day;
  final bool teacherExists;
  final bool subjectExists;
  final Function(Map<String, dynamic>) onPeriodUpdated;

  const PeriodEditDialog({
    super.key,
    required this.periodData,
    required this.teachers,
    required this.subjects,
    required this.day,
    required this.teacherExists,
    required this.subjectExists,
    required this.onPeriodUpdated,
  });

  @override
  State<PeriodEditDialog> createState() => _PeriodEditDialogState();
}

class _PeriodEditDialogState extends State<PeriodEditDialog> {
  late TextEditingController _subjectController;
  late TextEditingController _breakNameController;
  late String? _selectedTeacherId;
  late String? _selectedSubject;
  late bool _originalTeacherExists;
  late bool _originalSubjectExists;

  @override
  void initState() {
    super.initState();
    _subjectController = TextEditingController(
      text: widget.periodData['subject'] ?? '',
    );
    _breakNameController = TextEditingController(
      text: widget.periodData['name'] ?? 'Break',
    );

    _originalTeacherExists = widget.teacherExists;
    _originalSubjectExists = widget.subjectExists;

    // Fix: Properly handle subject matching with validation
    final existingSubject = widget.periodData['subject']?.toString().trim();
    if (existingSubject != null &&
        existingSubject.isNotEmpty &&
        _originalSubjectExists) {
      final matchedSubject = widget.subjects.firstWhere(
        (subject) =>
            subject['subject_name'].toString().trim() == existingSubject,
        orElse: () => {},
      );
      _selectedSubject = matchedSubject.isNotEmpty
          ? matchedSubject['subject_name']
          : null;
    } else {
      _selectedSubject = null;
    }

    // Fix: Validate teacher ID exists in current teachers list
    final teacherId = widget.periodData['teacher_id'];
    if (teacherId != null && _originalTeacherExists) {
      final teacherExists = widget.teachers.any(
        (teacher) => teacher['id'] == teacherId,
      );
      _selectedTeacherId = teacherExists ? teacherId : null;
    } else {
      _selectedTeacherId = null;
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _breakNameController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getTeachersForSubject(String? subjectName) {
    if (subjectName == null) return [];

    final subject = widget.subjects.firstWhere(
      (s) => s['subject_name'] == subjectName,
      orElse: () => {},
    );

    if (subject.isEmpty) return [];

    final teacherIds = List<String>.from(subject['teacher_ids'] ?? []);
    return widget.teachers
        .where((teacher) => teacherIds.contains(teacher['id']))
        .toList();
  }

  String? _getValidatedTeacherValue() {
    if (_selectedTeacherId == null) return null;

    // Check if the selected teacher ID exists in the current teachers list
    final teacherExists = widget.teachers.any(
      (teacher) => teacher['id'] == _selectedTeacherId,
    );
    return teacherExists ? _selectedTeacherId : null;
  }

  String? _getValidatedSubjectValue() {
    if (_selectedSubject == null) return null;

    // Check if the selected subject exists in the current subjects list
    final subjectExists = widget.subjects.any(
      (subject) => subject['subject_name'] == _selectedSubject,
    );
    return subjectExists ? _selectedSubject : null;
  }

  void _saveChanges() {
    final updatedData = Map<String, dynamic>.from(widget.periodData);

    if (widget.periodData['type'] == 'period') {
      updatedData['subject'] = _selectedSubject ?? _subjectController.text;
      updatedData['teacher_id'] = _selectedTeacherId;

      final teacher = widget.teachers.firstWhere(
        (t) => t['id'] == _selectedTeacherId,
        orElse: () => {'name': 'Unassigned'},
      );
      updatedData['teacher_name'] = teacher['name'];
    } else {
      updatedData['name'] = _breakNameController.text.isNotEmpty
          ? _breakNameController.text
          : 'Break';
    }

    widget.onPeriodUpdated(updatedData);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    final subjectTeachers = _getTeachersForSubject(_selectedSubject);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: isDesktop ? 400 : (isMobile ? double.infinity : 500),
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Edit ${widget.day} - ${widget.periodData['type'] == 'period' ? 'Period ${widget.periodData['number']}' : widget.periodData['name'] ?? 'Break'}',
              style: TextStyle(
                fontSize: isMobile ? 14 : 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
              textAlign: TextAlign.center,
            ),

            // Show warnings if original teacher or subject doesn't exist
            if (widget.periodData['type'] == 'period') ...[
              SizedBox(height: 12),
              if (!_originalSubjectExists)
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Original subject "${widget.periodData['subject']}" no longer exists. Please select a new subject.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_originalTeacherExists && _originalSubjectExists)
                Container(
                  padding: EdgeInsets.all(8),
                  margin: EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Original teacher no longer assigned to this subject. Please select a new teacher.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            SizedBox(height: 16),

            if (widget.periodData['type'] == 'period') ...[
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: isMobile ? 8 : 12,
                  ),
                ),
                value: _getValidatedSubjectValue(), // Use validated value
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(
                      'Select Subject',
                      style: TextStyle(fontSize: isMobile ? 12 : 14),
                    ),
                  ),
                  ...widget.subjects.map((subject) {
                    return DropdownMenuItem<String>(
                      value: subject['subject_name'],
                      child: Text(
                        '${subject['subject_name']} (${subject['subject_id']})',
                        style: TextStyle(fontSize: isMobile ? 12 : 14),
                      ),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedSubject = value;
                    _selectedTeacherId =
                        null; // Reset teacher when subject changes
                  });
                },
              ),
              SizedBox(height: 16),

              if (_selectedSubject != null && subjectTeachers.isNotEmpty)
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Teacher',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: isMobile ? 8 : 12,
                    ),
                  ),
                  value: _getValidatedTeacherValue(), // Use validated value
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'Unassigned',
                        style: TextStyle(fontSize: isMobile ? 12 : 14),
                      ),
                    ),
                    ...subjectTeachers.map((teacher) {
                      return DropdownMenuItem<String>(
                        value: teacher['id'],
                        child: Text(
                          teacher['name'],
                          style: TextStyle(fontSize: isMobile ? 12 : 14),
                        ),
                      );
                    }).toList(),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedTeacherId = value;
                    });
                  },
                )
              else if (_selectedSubject != null)
                Text(
                  'No teachers assigned to this subject',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: isMobile ? 12 : 14,
                  ),
                  textAlign: TextAlign.center,
                )
              else
                Text(
                  'Please select a subject first',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: isMobile ? 12 : 14,
                  ),
                  textAlign: TextAlign.center,
                ),
            ] else ...[
              TextField(
                controller: _breakNameController,
                decoration: InputDecoration(
                  labelText: 'Break Name',
                  hintText: 'Enter break name (e.g., Lunch, Interval, Break)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: isMobile ? 8 : 12,
                  ),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'You can rename this break period to anything you want',
                style: TextStyle(
                  fontSize: isMobile ? 10 : 12,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(fontSize: isMobile ? 12 : 14),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveChanges,
                  child: Text(
                    'Save',
                    style: TextStyle(fontSize: isMobile ? 12 : 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PeriodData {
  int index;
  final bool isBreak;
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  String subject;
  String? teacherId;
  String breakName;

  PeriodData({
    required this.index,
    required this.isBreak,
    this.startTime,
    this.endTime,
    this.subject = '',
    this.teacherId,
    this.breakName = 'Break',
  });
}

class _PeriodInput extends StatefulWidget {
  final PeriodData periodData;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> subjects;
  final VoidCallback onDataChanged;
  final TimeOfDay? lastEndTime;
  final VoidCallback? onRemove;

  const _PeriodInput({
    required this.periodData,
    required this.teachers,
    required this.subjects,
    required this.onDataChanged,
    this.lastEndTime,
    this.onRemove,
  });

  @override
  State<_PeriodInput> createState() => __PeriodInputState();
}

class __PeriodInputState extends State<_PeriodInput> {
  final _subjectController = TextEditingController();
  final _breakNameController = TextEditingController();
  String? _selectedSubject;
  String? _selectedTeacherId;

  @override
  void initState() {
    super.initState();
    _subjectController.text = widget.periodData.subject;
    _breakNameController.text = widget.periodData.breakName;

    // Fix: Properly handle subject matching with trimming
    final existingSubject = widget.periodData.subject?.trim();
    if (existingSubject != null && existingSubject.isNotEmpty) {
      final matchedSubject = widget.subjects.firstWhere(
        (subject) =>
            subject['subject_name'].toString().trim() == existingSubject,
        orElse: () => {},
      );
      _selectedSubject = matchedSubject.isNotEmpty
          ? matchedSubject['subject_name']
          : null;
    } else {
      _selectedSubject = null;
    }

    _selectedTeacherId = widget.periodData.teacherId;

    if (widget.periodData.startTime == null && widget.lastEndTime != null) {
      widget.periodData.startTime = widget.lastEndTime;
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _breakNameController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getTeachersForSubject(String? subjectName) {
    if (subjectName == null) return [];

    final subject = widget.subjects.firstWhere(
      (s) => s['subject_name'] == subjectName,
      orElse: () => {},
    );

    if (subject.isEmpty) return [];

    final teacherIds = List<String>.from(subject['teacher_ids'] ?? []);
    return widget.teachers
        .where((teacher) => teacherIds.contains(teacher['id']))
        .toList();
  }

  Future<void> _selectStartTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime:
          widget.periodData.startTime ??
          widget.lastEndTime ??
          const TimeOfDay(hour: 9, minute: 0),
    );
    if (selected != null) {
      setState(() {
        widget.periodData.startTime = selected;
      });
      widget.onDataChanged();
    }
  }

  Future<void> _selectEndTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime:
          widget.periodData.endTime ??
          widget.periodData.startTime ??
          const TimeOfDay(hour: 9, minute: 45),
    );
    if (selected != null) {
      setState(() {
        widget.periodData.endTime = selected;
      });
      widget.onDataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final subjectTeachers = _getTeachersForSubject(_selectedSubject);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 8 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.periodData.isBreak
                      ? 'Break'
                      : 'Period ${widget.periodData.index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 12 : 14,
                  ),
                ),
                const Spacer(),
                if (widget.onRemove != null)
                  IconButton(
                    icon: Icon(
                      Icons.delete,
                      color: Colors.red,
                      size: isMobile ? 16 : 20,
                    ),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            SizedBox(height: 8),
            if (!widget.periodData.isBreak) ...[
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: isMobile ? 8 : 12,
                  ),
                ),
                value: _selectedSubject,
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(
                      'Select Subject',
                      style: TextStyle(fontSize: isMobile ? 12 : 14),
                    ),
                  ),
                  ...widget.subjects.map((subject) {
                    return DropdownMenuItem<String>(
                      value: subject['subject_name'],
                      child: Text(
                        '${subject['subject_name']} (${subject['subject_id']})',
                        style: TextStyle(fontSize: isMobile ? 12 : 14),
                      ),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedSubject = value;
                    _selectedTeacherId = null;
                    widget.periodData.subject = value ?? '';
                    widget.periodData.teacherId = null;
                  });
                  widget.onDataChanged();
                },
              ),
              SizedBox(height: 8),

              if (_selectedSubject != null && subjectTeachers.isNotEmpty)
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Assign Teacher',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: isMobile ? 8 : 12,
                    ),
                  ),
                  value: _selectedTeacherId,
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'Unassigned',
                        style: TextStyle(fontSize: isMobile ? 12 : 14),
                      ),
                    ),
                    ...subjectTeachers.map((teacher) {
                      return DropdownMenuItem<String>(
                        value: teacher['id'],
                        child: Text(
                          teacher['name'],
                          style: TextStyle(fontSize: isMobile ? 12 : 14),
                        ),
                      );
                    }).toList(),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedTeacherId = value;
                      widget.periodData.teacherId = value;
                    });
                    widget.onDataChanged();
                  },
                )
              else if (_selectedSubject != null)
                Text(
                  'No teachers assigned to this subject',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: isMobile ? 10 : 12,
                  ),
                ),
            ] else ...[
              TextField(
                controller: _breakNameController,
                decoration: InputDecoration(
                  labelText: 'Break Name',
                  hintText: 'Enter break name (e.g., Lunch, Interval)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: isMobile ? 8 : 12,
                  ),
                ),
                onChanged: (value) {
                  widget.periodData.breakName = value;
                  widget.onDataChanged();
                },
              ),
            ],
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectStartTime,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 8 : 12,
                      ),
                    ),
                    child: Text(
                      widget.periodData.startTime != null
                          ? widget.periodData.startTime!.format(context)
                          : 'Start Time',
                      style: TextStyle(fontSize: isMobile ? 10 : 12),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectEndTime,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 8 : 12,
                      ),
                    ),
                    child: Text(
                      widget.periodData.endTime != null
                          ? widget.periodData.endTime!.format(context)
                          : 'End Time',
                      style: TextStyle(fontSize: isMobile ? 10 : 12),
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
}
