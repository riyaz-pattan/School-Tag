import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AllTimetablesScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;

  const AllTimetablesScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<AllTimetablesScreen> createState() => _AllTimetablesScreenState();
}

class _AllTimetablesScreenState extends State<AllTimetablesScreen> {
  List<Map<String, dynamic>> _allClasses = [];
  List<String> _selectedClassIds = [];
  Map<String, Map<String, dynamic>> _timetablesData = {};
  Map<String, List<Map<String, dynamic>>> _editedTimetables = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;
  bool _isSaving = false;
  TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _subjects = [];

  // Cache variables
  DateTime? _lastTeachersCacheUpdate;
  DateTime? _lastSubjectsCacheUpdate;
  DateTime? _lastClassesCacheUpdate;
  DateTime? _lastTimetablesCacheUpdate;
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
    _infoPageController = PageController();
    _loadCachedData();
    _loadAllData();
    _loadTeachers();
    _loadSubjects();
  }

  // Add this method to handle back button
  Future<bool> _onWillPop() async {
    // If we have selected classes, clear the selection first
    if (_selectedClassIds.isNotEmpty) {
      setState(() {
        _selectedClassIds.clear();
      });
      return false; // Don't navigate back yet
    }

    // If we have edited timetables, show confirmation
    if (_editedTimetables.isNotEmpty) {
      final shouldPop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Unsaved Changes'),
          content: Text(
            'You have unsaved changes. Are you sure you want to go back?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Discard'),
            ),
          ],
        ),
      );
      return shouldPop ?? false;
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
    await _loadCachedClasses();
    await _loadCachedTimetables();
  }

  // Cache management for teachers
  Future<void> _loadCachedTeachers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'all_cached_teachers_${widget.schoolCode}';
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
      final cacheKey = 'all_cached_teachers_${widget.schoolCode}';

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
      final cacheKey = 'all_cached_subjects_${widget.schoolCode}';
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
      final cacheKey = 'all_cached_subjects_${widget.schoolCode}';

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
      final cacheKey = 'all_cached_classes_${widget.schoolCode}';
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
            _allClasses = List<Map<String, dynamic>>.from(classes);
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
      final cacheKey = 'all_cached_classes_${widget.schoolCode}';

      final serializableClasses = classes
          .map((classData) => _convertMapToSerializable(classData))
          .toList();

      final cacheData = {
        'lastUpdate': DateTime.now().toIso8601String(),
        'classes': serializableClasses,
      };
      await prefs.setString(cacheKey, json.encode(cacheData));

      setState(() {
        _lastClassesCacheUpdate = DateTime.now();
      });
    } catch (e) {
      print('Error saving classes to cache: $e');
    }
  }

  // Cache management for timetables
  Future<void> _loadCachedTimetables() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'all_cached_timetables_${widget.schoolCode}';
      final cachedData = prefs.getString(cacheKey);

      if (cachedData != null) {
        final cacheMap = json.decode(cachedData) as Map<String, dynamic>;
        final lastUpdate = DateTime.parse(cacheMap['lastUpdate'] as String);

        if (DateTime.now().difference(lastUpdate).inMinutes <
            _cacheDurationMinutes) {
          final timetables = (cacheMap['timetables'] as Map<String, dynamic>)
              .map(
                (key, value) => MapEntry(
                  key,
                  _restoreMapFromSerializable(value as Map<String, dynamic>),
                ),
              );

          setState(() {
            _timetablesData = Map<String, Map<String, dynamic>>.from(
              timetables,
            );
            _lastTimetablesCacheUpdate = lastUpdate;
          });
        }
      }
    } catch (e) {
      print('Error loading cached timetables: $e');
    }
  }

  Future<void> _saveTimetablesToCache(
    Map<String, Map<String, dynamic>> timetables,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'all_cached_timetables_${widget.schoolCode}';

      final serializableTimetables = timetables.map(
        (key, value) => MapEntry(key, _convertMapToSerializable(value)),
      );

      final cacheData = {
        'lastUpdate': DateTime.now().toIso8601String(),
        'timetables': serializableTimetables,
      };
      await prefs.setString(cacheKey, json.encode(cacheData));

      setState(() {
        _lastTimetablesCacheUpdate = DateTime.now();
      });
    } catch (e) {
      print('Error saving timetables to cache: $e');
    }
  }

  // Clear all cache
  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('all_cached_teachers_${widget.schoolCode}');
      await prefs.remove('all_cached_subjects_${widget.schoolCode}');
      await prefs.remove('all_cached_classes_${widget.schoolCode}');
      await prefs.remove('all_cached_timetables_${widget.schoolCode}');

      setState(() {
        _teachers = [];
        _subjects = [];
        _allClasses = [];
        _timetablesData = {};
        _lastTeachersCacheUpdate = null;
        _lastSubjectsCacheUpdate = null;
        _lastClassesCacheUpdate = null;
        _lastTimetablesCacheUpdate = null;
      });

      // Reload data
      _loadAllData();
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
      print('Error loading teachers: $e');
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

  Future<void> _loadAllData() async {
    // If we have cached data and they're still valid, don't fetch from Firestore
    if (_allClasses.isNotEmpty &&
        _timetablesData.isNotEmpty &&
        _lastClassesCacheUpdate != null &&
        _lastTimetablesCacheUpdate != null &&
        DateTime.now().difference(_lastClassesCacheUpdate!).inMinutes <
            _cacheDurationMinutes &&
        DateTime.now().difference(_lastTimetablesCacheUpdate!).inMinutes <
            _cacheDurationMinutes) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Load classes
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();

      final classes = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'grade': data['grade'] ?? 'Unknown',
          'sections': data['sections'] ?? [],
          'displayName': _getClassName(
            data['grade'] ?? 'Unknown',
            data['sections'] ?? [],
          ),
        };
      }).toList();

      // Load timetables
      final timetablesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .get();

      final Map<String, Map<String, dynamic>> tempTimetables = {};
      for (var doc in timetablesSnapshot.docs) {
        final data = doc.data();
        tempTimetables[doc.id] = data;
      }

      setState(() {
        _allClasses = classes;
        _timetablesData = tempTimetables;
        _isLoading = false;
      });

      // Save to cache
      _saveClassesToCache(classes);
      _saveTimetablesToCache(tempTimetables);
    } catch (e) {
      setState(() {
        _showFloatingMessage('Error loading data: $e', true);
        _isLoading = false;
      });
    }
  }

  String _getClassName(String grade, List<dynamic> sections) {
    if (sections.isEmpty) return grade;
    return '$grade (${sections.join(', ')})';
  }

  List<Map<String, dynamic>> _getFilteredClasses() {
    if (_searchQuery.isEmpty) {
      return _allClasses;
    }
    return _allClasses.where((classData) {
      final displayName = classData['displayName'].toString().toLowerCase();
      return displayName.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _toggleClassSelection(String classId) {
    setState(() {
      if (_selectedClassIds.contains(classId)) {
        _selectedClassIds.remove(classId);
      } else {
        _selectedClassIds.add(classId);
      }
    });
  }

  void _editPeriodSlot(String classId, int periodIndex, String day) {
    final timetable = _timetablesData[classId];
    if (timetable == null) return;

    final dayKey = day.toLowerCase();
    final isUniform = timetable['is_uniform'] ?? true;
    final timetableData = timetable['timetable'] as Map<String, dynamic>? ?? {};

    List<Map<String, dynamic>> daySchedule;
    if (isUniform) {
      daySchedule = List<Map<String, dynamic>>.from(
        timetableData.values.first ?? [],
      );
    } else {
      daySchedule = List<Map<String, dynamic>>.from(
        timetableData[dayKey] ?? [],
      );
    }

    if (daySchedule.length <= periodIndex) return;

    final periodData = daySchedule[periodIndex];

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
            if (!_editedTimetables.containsKey(classId)) {
              _editedTimetables[classId] = [];
            }

            if (isUniform) {
              for (var currentDay in timetableData.keys) {
                final currentDaySchedule = List<Map<String, dynamic>>.from(
                  timetableData[currentDay] ?? [],
                );
                if (currentDaySchedule.length > periodIndex) {
                  currentDaySchedule[periodIndex] = updatedData;
                  timetableData[currentDay] = currentDaySchedule;
                }
              }
            } else {
              final currentDaySchedule = List<Map<String, dynamic>>.from(
                timetableData[dayKey] ?? [],
              );
              if (currentDaySchedule.length > periodIndex) {
                currentDaySchedule[periodIndex] = updatedData;
                timetableData[dayKey] = currentDaySchedule;
              }
            }

            _editedTimetables[classId]!.add(updatedData);
          });
        },
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_editedTimetables.isEmpty) {
      setState(() {
        _showFloatingMessage('No changes to save', false);
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (var classId in _editedTimetables.keys) {
        final timetableRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('timetables')
            .doc(classId);

        final updatedData = {
          ..._timetablesData[classId]!,
          'updated_at': FieldValue.serverTimestamp(),
        };

        batch.set(timetableRef, updatedData);
      }

      await batch.commit();

      // Update cache with new data
      await _saveTimetablesToCache(_timetablesData);

      setState(() {
        _showFloatingMessage('Changes saved successfully', false);
        _isSaving = false;
        _editedTimetables.clear();
      });
    } catch (e) {
      setState(() {
        _showFloatingMessage('Error saving changes: $e', true);
        _isSaving = false;
      });
    }
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
                      Icons.list_alt,
                      size: 40,
                      color: Color.fromARGB(255, 22, 105, 200),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'All Timetables',
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
          ],
        ),
      ),
    );
  }

  // Add these new methods to the _AllTimetablesScreenState class:

  late PageController _infoPageController;
  int _currentInfoPage = 0;

  Widget _buildInfoPage1() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to View All Timetables',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.search,
            'Search & Filter',
            'Use the search bar to find specific classes quickly',
          ),
          _buildInfoItem(
            Icons.check_box,
            'Select Multiple',
            'Choose multiple classes to compare their timetables',
          ),
          _buildInfoItem(
            Icons.edit,
            'Quick Edit',
            'Click on any period to edit directly in the grid',
          ),
          _buildInfoItem(
            Icons.save,
            'Save All Changes',
            'Use the Save Changes button to apply all edits at once',
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
            '👀',
            'View multiple classes to identify scheduling conflicts',
          ),
          _buildTipItem(
            '⚡',
            'Use this screen for quick edits across multiple timetables',
          ),
          _buildTipItem(
            '📊',
            'Compare uniform vs non-uniform schedules easily',
          ),
          _buildTipItem('🔄', 'Refresh data regularly to see latest changes'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[100]!),
            ),
            child: const Text(
              'Pro Tip: Use this screen when you need to make bulk changes or compare schedules across different classes.',
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

  Widget _buildDesktopTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: Colors.white,
      child: Row(
        children: [
          // Add back button
          IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.blue),
            onPressed: () {
              if (_selectedClassIds.isNotEmpty) {
                setState(() {
                  _selectedClassIds.clear();
                });
              } else {
                Navigator.of(context).pop();
              }
            },
            tooltip: 'Back',
          ),
          SizedBox(width: 8),
          Text(
            'All Timetables - ${widget.schoolName}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 103, 195),
            ),
          ),
          const Spacer(),
          if (_lastClassesCacheUpdate != null ||
              _lastTimetablesCacheUpdate != null)
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
      canPop: _selectedClassIds.isEmpty && _editedTimetables.isEmpty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop) {
          // Handle back button when we prevent pop
          if (_selectedClassIds.isNotEmpty) {
            setState(() {
              _selectedClassIds.clear();
            });
          } else if (_editedTimetables.isNotEmpty) {
            final shouldPop = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Unsaved Changes'),
                content: Text(
                  'You have unsaved changes. Are you sure you want to go back?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context, true);
                      // After dialog closes, trigger the pop
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        Navigator.of(context).pop();
                      });
                    },
                    child: Text('Discard'),
                  ),
                ],
              ),
            );
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
          _isMobile ? 'Timetables' : 'All Timetables',
          style: TextStyle(fontSize: _isMobile ? 18 : 20),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Color.fromARGB(255, 21, 101, 192),
        elevation: 0,
        actions: [
          if (_lastClassesCacheUpdate != null ||
              _lastTimetablesCacheUpdate != null)
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
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
        // Class Selector Card
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
                  'Select Classes to View Timetables',
                  style: TextStyle(
                    fontSize: _isMobile ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search Classes',
                    hintText: 'Enter class name...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                SizedBox(height: 16),
                if (_getFilteredClasses().isEmpty)
                  Center(
                    child: Text(
                      'No classes found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _getFilteredClasses().map((classData) {
                      final isSelected = _selectedClassIds.contains(
                        classData['id'],
                      );
                      return FilterChip(
                        label: Text(classData['displayName']),
                        selected: isSelected,
                        onSelected: (_) =>
                            _toggleClassSelection(classData['id']),
                        backgroundColor: isSelected
                            ? Colors.blue[100]
                            : Colors.grey[200],
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.blue[700]
                              : Colors.grey[700],
                        ),
                      );
                    }).toList(),
                  ),
                SizedBox(height: 16),
                if (_selectedClassIds.isNotEmpty)
                  Text(
                    '${_selectedClassIds.length} class(es) selected',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),

        SizedBox(height: 20),

        // Timetables Section
        if (_selectedClassIds.isNotEmpty) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Timetables',
                style: TextStyle(
                  fontSize: _isMobile ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
              ),
              if (_editedTimetables.isNotEmpty)
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(
                      horizontal: _isMobile ? 16 : 24,
                      vertical: _isMobile ? 12 : 16,
                    ),
                  ),
                  child: _isSaving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : Text(
                          'Save Changes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _isMobile ? 12 : 14,
                          ),
                        ),
                ),
            ],
          ),
          SizedBox(height: 16),

          ..._selectedClassIds
              .map(
                (classId) => Column(
                  children: [
                    _buildTimetableForClass(classId),
                    SizedBox(height: 20),
                  ],
                ),
              )
              .toList(),
        ] else
          Center(
            child: Text(
              'Select classes to view timetables',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildTimetableForClass(String classId) {
    final timetable = _timetablesData[classId];
    if (timetable == null) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: EdgeInsets.all(_isDesktop ? 24 : 16),
          child: Center(
            child: Text(
              'No timetable found for ${_allClasses.firstWhere((c) => c['id'] == classId, orElse: () => {'displayName': 'Unknown'})['displayName']}',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    final className = timetable['class_name'] ?? 'Unknown Class';
    final workingDays = List<String>.from(
      timetable['working_days'] ??
          ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
    );
    final isUniform = timetable['is_uniform'] ?? true;
    final timetableData = timetable['timetable'] as Map<String, dynamic>? ?? {};

    List<Map<String, dynamic>> dailySchedule;
    if (isUniform && timetableData.isNotEmpty) {
      dailySchedule = List<Map<String, dynamic>>.from(
        timetableData.values.first,
      );
    } else if (timetableData.isNotEmpty) {
      dailySchedule = List<Map<String, dynamic>>.from(
        timetableData.values.first,
      );
    } else {
      dailySchedule = [];
    }

    if (dailySchedule.isNotEmpty) {
      dailySchedule = _sortScheduleByTime(dailySchedule);
    }

    if (dailySchedule.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: EdgeInsets.all(_isDesktop ? 24 : 16),
          child: Center(
            child: Text(
              'No schedule configured for $className',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(_isDesktop ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    className,
                    style: TextStyle(
                      fontSize: _isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 21, 101, 192),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Chip(
                  label: Text(
                    isUniform ? 'Uniform' : 'Non-Uniform',
                    style: TextStyle(
                      fontSize: _isMobile ? 10 : 12,
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: isUniform
                      ? Colors.blue[400]
                      : Colors.purple[400],
                ),
              ],
            ),
            SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildTraditionalTimetable(
                  dailySchedule,
                  workingDays,
                  isUniform,
                  timetableData,
                  classId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildTraditionalTimetable(
    List<Map<String, dynamic>> dailySchedule,
    List<String> workingDays,
    bool isUniform,
    Map<String, dynamic> timetableData,
    String classId,
  ) {
    return Table(
      border: TableBorder.all(color: Colors.grey[300]!),
      defaultColumnWidth: FixedColumnWidth(_isMobile ? 120 : 150),
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.blue[50]),
          children: [
            _buildDiagonalSplitCell(),
            ...dailySchedule.asMap().entries.map((entry) {
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
        ...workingDays.map((day) {
          return TableRow(
            decoration: BoxDecoration(
              color: workingDays.indexOf(day) % 2 == 0
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
              ...dailySchedule.asMap().entries.map((entry) {
                final index = entry.key;
                final periodData = isUniform
                    ? entry.value
                    : (timetableData[day.toLowerCase()] as List<dynamic>? ??
                              [])[index] ??
                          entry.value;

                return GestureDetector(
                  onTap: () => _editPeriodSlot(classId, index, day),
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

  String _getTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
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
