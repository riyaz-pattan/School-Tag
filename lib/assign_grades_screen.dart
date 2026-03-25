import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'teacher_dashboard_screen.dart';

class AssignGradesScreen extends StatefulWidget {
  final String schoolCode;
  final String userId;
  final String schoolName;
  final String teacherId;
  final String teacherName;

  const AssignGradesScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.teacherId,
    required this.teacherName,
  });

  @override
  State<AssignGradesScreen> createState() => _AssignGradesScreenState();
}

class _AssignGradesScreenState extends State<AssignGradesScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _assignedSubjects = [];
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;

  // Cache variables
  DateTime? _lastExamsFetchTime;
  DateTime? _lastClassesFetchTime;
  DateTime? _lastSubjectsFetchTime;
  static const int CACHE_DURATION_MINUTES = 10;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // Tab controller
  late TabController _tabController;

  // View Grades Section
  String? _selectedViewExamId;
  String? _selectedViewClassId;
  String? _selectedViewSubjectId;
  List<Map<String, dynamic>> _viewGrades = [];
  bool _isLoadingGrades = false;
  String _searchQuery = '';

  // Sidebar info page controller
  final PageController _infoPageController = PageController();
  int _currentInfoPage = 0;

  // Timer for auto-dismiss messages
  Timer? _messageTimer;

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
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

  Future<void> _loadInitialData() async {
    try {
      await Future.wait([
        _loadExams(),
        _loadClasses(),
        _loadSubjects(),
        _loadAssignedSubjects(),
      ]);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
        _isLoading = false;
      });
    }
  }

  // Cache management methods
  Map<String, dynamic> _convertToCacheSafe(Map<String, dynamic> data) {
    final Map<String, dynamic> safeData = Map.from(data);
    safeData.forEach((key, value) {
      if (value is Timestamp) {
        safeData[key] = {
          '_type': 'timestamp',
          'milliseconds': value.millisecondsSinceEpoch,
        };
      }
    });
    return safeData;
  }

  Map<String, dynamic> _convertFromCacheSafe(Map<String, dynamic> data) {
    final Map<String, dynamic> restoredData = Map.from(data);
    restoredData.forEach((key, value) {
      if (value is Map && value['_type'] == 'timestamp') {
        restoredData[key] = Timestamp.fromMillisecondsSinceEpoch(
          value['milliseconds'],
        );
      }
    });
    return restoredData;
  }

  Future<Map<String, dynamic>?> _loadCachedData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(
        '${key}_${widget.schoolCode}_${widget.teacherId}',
      );
      if (cachedData != null && cachedData.isNotEmpty) {
        return json.decode(cachedData);
      }
    } catch (e) {
      print('Error loading cached data: $e');
    }
    return null;
  }

  Future<void> _saveToCache(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheSafeData = data is List
          ? data.map((item) => _convertToCacheSafe(item)).toList()
          : _convertToCacheSafe(data);

      await prefs.setString(
        '${key}_${widget.schoolCode}_${widget.teacherId}',
        json.encode({
          'data': cacheSafeData,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      print('Error saving to cache: $e');
    }
  }

  bool _isCacheValid(DateTime? lastFetchTime) {
    if (lastFetchTime == null) return false;
    final difference = DateTime.now().difference(lastFetchTime);
    return difference.inMinutes < CACHE_DURATION_MINUTES;
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
      // Clear view grades to force reload
      _viewGrades = [];
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('exams_${widget.schoolCode}_${widget.teacherId}');
    await prefs.remove('classes_${widget.schoolCode}_${widget.teacherId}');
    await prefs.remove('subjects_${widget.schoolCode}_${widget.teacherId}');
    await prefs.remove(
      'assigned_subjects_${widget.schoolCode}_${widget.teacherId}',
    );

    // Reset cache timestamps to force fresh fetch
    _lastExamsFetchTime = null;
    _lastClassesFetchTime = null;
    _lastSubjectsFetchTime = null;

    try {
      await _loadInitialData();

      // Reload view grades if we have current selections
      if (_selectedViewExamId != null &&
          _selectedViewClassId != null &&
          _selectedViewSubjectId != null) {
        await _loadViewGrades();
      }

      _showMessage('Data refreshed successfully!');
    } catch (e) {
      _showMessage('Error refreshing data: $e', isError: true);
    }
  }

  Future<void> _loadExams() async {
    final cachedData = await _loadCachedData('exams');
    if (cachedData != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (_isCacheValid(timestamp)) {
        final cachedExams = (cachedData['data'] as List)
            .map((item) => _convertFromCacheSafe(item))
            .toList();
        setState(() {
          _exams = List<Map<String, dynamic>>.from(cachedExams);
        });
        return;
      }
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exams')
          .orderBy('created_at', descending: true)
          .get();

      final exams = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final subjectsMarksDynamic =
            data['subjects_marks'] as List<dynamic>? ?? [];
        final subjectsMarks = subjectsMarksDynamic.map((item) {
          return item as Map<String, dynamic>;
        }).toList();

        return {
          'id': doc.id,
          'exam_name': data['exam_name'],
          'subjects_marks': subjectsMarks,
        };
      }).toList();

      await _saveToCache('exams', exams);
      setState(() {
        _exams = exams;
        _lastExamsFetchTime = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading exams: $e';
      });
    }
  }

  Future<void> _loadClasses() async {
    final cachedData = await _loadCachedData('classes');
    if (cachedData != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (_isCacheValid(timestamp)) {
        final cachedClasses = (cachedData['data'] as List)
            .map((item) => _convertFromCacheSafe(item))
            .toList();
        setState(() {
          _classes = List<Map<String, dynamic>>.from(cachedClasses);
        });
        return;
      }
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .orderBy('grade')
          .get();

      final classes = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'grade': data['grade'],
          'sections': List<String>.from(data['sections'] ?? []),
          'className': _getClassName(data['grade'], data['sections'] ?? []),
        };
      }).toList();

      await _saveToCache('classes', classes);
      setState(() {
        _classes = classes;
        _lastClassesFetchTime = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading classes: $e';
      });
    }
  }

  Future<void> _loadSubjects() async {
    final cachedData = await _loadCachedData('subjects');
    if (cachedData != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (_isCacheValid(timestamp)) {
        final cachedSubjects = (cachedData['data'] as List)
            .map((item) => _convertFromCacheSafe(item))
            .toList();
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(cachedSubjects);
        });
        return;
      }
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
        };
      }).toList();

      await _saveToCache('subjects', subjects);
      setState(() {
        _subjects = subjects;
        _lastSubjectsFetchTime = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading subjects: $e';
      });
    }
  }

  Future<void> _loadAssignedSubjects() async {
    final cachedData = await _loadCachedData('assigned_subjects');
    if (cachedData != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (_isCacheValid(timestamp)) {
        final cachedAssignedSubjects = (cachedData['data'] as List)
            .map((item) => _convertFromCacheSafe(item))
            .toList();
        setState(() {
          _assignedSubjects = List<Map<String, dynamic>>.from(
            cachedAssignedSubjects,
          );
        });
        return;
      }
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('subjects')
          .get();

      final allSubjects = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'subject_id': data['subject_id'],
          'subject_name': data['subject_name'],
          'teacher_ids': List<String>.from(data['teacher_ids'] ?? []),
        };
      }).toList();

      final assignedSubjects = allSubjects.where((subject) {
        final teacherIds = List<String>.from(subject['teacher_ids'] ?? []);
        return teacherIds.contains(widget.teacherId);
      }).toList();

      await _saveToCache('assigned_subjects', assignedSubjects);
      setState(() {
        _assignedSubjects = assignedSubjects;
      });
    } catch (e) {
      print('Error loading assigned subjects: $e');
      setState(() {
        _assignedSubjects = _subjects;
      });
    }
  }

  Future<void> _loadViewGrades() async {
    if (_selectedViewExamId == null ||
        _selectedViewClassId == null ||
        _selectedViewSubjectId == null) {
      setState(() {
        _viewGrades = [];
      });
      return;
    }

    setState(() {
      _isLoadingGrades = true;
    });

    try {
      // 1. First, get all students in the selected class
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .where('class_id', isEqualTo: _selectedViewClassId)
          .get();

      final allStudents = studentsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'student_id': doc.id,
          'student_name': data['full_name'] ?? data['username'],
          'username': data['username'],
          'section': data['section'],
        };
      }).toList();

      // 2. Then, get existing grades for this exam, class, and subject
      Query query = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('grades')
          .where('teacher_id', isEqualTo: widget.teacherId)
          .where('class_id', isEqualTo: _selectedViewClassId)
          .where('subject_id', isEqualTo: _selectedViewSubjectId);

      if (_selectedViewExamId != null) {
        query = query.where('exam_id', isEqualTo: _selectedViewExamId);
      }

      final gradesSnapshot = await query.get();

      final existingGrades = gradesSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {'id': doc.id, ...data};
      }).toList();

      // 3. Get max marks for the subject from the exam
      final selectedExam = _exams.firstWhere(
        (exam) => exam['id'] == _selectedViewExamId,
        orElse: () => {},
      );

      int maxMarks = 0;
      if (selectedExam.isNotEmpty) {
        final subjectsMarks =
            (selectedExam['subjects_marks'] as List<dynamic>? ?? []);
        for (var subjectMark in subjectsMarks) {
          if (subjectMark['subject_id'] == _selectedViewSubjectId) {
            maxMarks =
                int.tryParse(subjectMark['max_marks']?.toString() ?? '0') ?? 0;
            break;
          }
        }
      }

      // 4. Merge: For each student, find their grade or create a placeholder
      final List<Map<String, dynamic>> mergedGrades = [];

      for (var student in allStudents) {
        final existingGrade = existingGrades.firstWhere(
          (grade) => grade['student_id'] == student['student_id'],
          orElse: () => {},
        );

        if (existingGrade.isNotEmpty) {
          // Student has existing grade
          mergedGrades.add(existingGrade);
        } else {
          // Student doesn't have grade - create placeholder
          final exam = _exams.firstWhere(
            (e) => e['id'] == _selectedViewExamId,
            orElse: () => {'exam_name': 'Unknown Exam'},
          );

          final subject = _subjects.firstWhere(
            (s) => s['id'] == _selectedViewSubjectId,
            orElse: () => {'subject_name': 'Unknown Subject'},
          );

          mergedGrades.add({
            'id': null, // No Firestore ID yet
            'student_id': student['student_id'],
            'student_name': student['student_name'],
            'exam_id': _selectedViewExamId,
            'exam_name': exam['exam_name'],
            'class_id': _selectedViewClassId,
            'subject_id': _selectedViewSubjectId,
            'subject_name': subject['subject_name'],
            'marks_obtained': null, // Not assigned yet
            'is_absent': false,
            'max_marks': maxMarks,
            'teacher_id': widget.teacherId,
            'teacher_name': widget.teacherName,
            'school_code': widget.schoolCode,
            'is_not_assigned': true, // Flag to identify ungraded students
          });
        }
      }

      setState(() {
        _viewGrades = mergedGrades;
        _isLoadingGrades = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading grades: $e';
        _isLoadingGrades = false;
      });
    }
  }

  Future<void> _updateGrade(
    String gradeId,
    int marks,
    bool isAbsent,
    Map<String, dynamic> gradeData,
  ) async {
    try {
      final gradesRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('grades');

      // If grade doesn't exist yet (new assignment), create it
      if (gradeId.isEmpty || gradeId == 'null') {
        // Create a new grade document with consistent ID format
        final newGradeId =
            '${gradeData['exam_id']}_${gradeData['subject_id']}_${gradeData['student_id']}';

        await gradesRef.doc(newGradeId).set({
          ...gradeData,
          'marks_obtained': isAbsent ? 0 : marks,
          'is_absent': isAbsent,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      } else {
        // Update existing grade
        await gradesRef.doc(gradeId).update({
          'marks_obtained': isAbsent ? 0 : marks,
          'is_absent': isAbsent,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      _showMessage(
        'Grade ${gradeId.isEmpty ? 'assigned' : 'updated'} successfully!',
      );

      await _loadViewGrades();
    } catch (e) {
      _showMessage(
        'Error ${gradeId.isEmpty ? 'assigning' : 'updating'} grade: $e',
        isError: true,
      );
    }
  }

  void _showEditGradeDialog(Map<String, dynamic> grade) {
    final maxMarks = grade['max_marks'] ?? 0;
    final currentMarks = grade['marks_obtained'] ?? 0;
    final isAbsent = grade['is_absent'] ?? false;

    final TextEditingController marksController = TextEditingController(
      text: isAbsent ? '' : currentMarks.toString(),
    );
    bool _isAbsent = isAbsent;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Grade'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Student: ${grade['student_name'] ?? 'Unknown'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Exam: ${grade['exam_name'] ?? 'Unknown'}'),
                  const SizedBox(height: 16),

                  // Absent Checkbox
                  Row(
                    children: [
                      Checkbox(
                        value: _isAbsent,
                        onChanged: (value) {
                          setDialogState(() {
                            _isAbsent = value ?? false;
                            if (_isAbsent) {
                              marksController.clear();
                            }
                          });
                        },
                      ),
                      const Text('Mark as Absent'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Marks Input (disabled when absent)
                  TextField(
                    controller: marksController,
                    keyboardType: TextInputType.number,
                    enabled: !_isAbsent,
                    decoration: InputDecoration(
                      labelText: _isAbsent ? 'Marks (Absent)' : 'Marks',
                      border: const OutlineInputBorder(),
                      hintText: _isAbsent
                          ? 'Student is absent'
                          : 'Enter marks (0-$maxMarks)',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      filled: _isAbsent,
                      fillColor: _isAbsent ? Colors.grey[200] : null,
                    ),
                    autofocus: !_isAbsent,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Maximum marks: $maxMarks',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),

                  if (_isAbsent) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.orange[700], size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Student will be marked as absent (0 marks)',
                              style: TextStyle(
                                color: Colors.orange[700],
                                fontSize: 12,
                              ),
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
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_isAbsent) {
                    _updateGrade(grade['id']?.toString() ?? '', 0, true, grade);
                    Navigator.pop(context);
                  } else {
                    final marks = int.tryParse(marksController.text);
                    if (marks != null && marks >= 0 && marks <= maxMarks) {
                      _updateGrade(
                        grade['id']?.toString() ?? '',
                        marks,
                        false,
                        grade,
                      );
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Please enter valid marks (0-$maxMarks)',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getClassName(String grade, List<dynamic> sections) {
    if (sections.isEmpty) return 'Grade $grade';
    return 'Grade $grade (${sections.join(', ')})';
  }

  // Helper method to get filtered subjects for an exam (teacher assigned subjects that are in the exam)
  List<Map<String, dynamic>> _getFilteredSubjectsForExam(
    Map<String, dynamic> exam,
  ) {
    if (exam['subjects_marks'] == null) return [];

    final examSubjectIds = (exam['subjects_marks'] as List<dynamic>)
        .map((subjectMark) => subjectMark['subject_id'] as String)
        .toList();

    return _assignedSubjects.where((subject) {
      return examSubjectIds.contains(subject['id']);
    }).toList();
  }

  // Helper method to get filtered subjects for view (teacher assigned subjects that are in the selected exam)
  List<Map<String, dynamic>> _getFilteredSubjectsForView() {
    if (_selectedViewExamId == null) return [];

    final selectedExam = _exams.firstWhere(
      (exam) => exam['id'] == _selectedViewExamId,
      orElse: () => {},
    );

    if (selectedExam.isEmpty) return [];

    return _getFilteredSubjectsForExam(selectedExam);
  }

  void _showAssignGradesDialog(Map<String, dynamic> exam) {
    final filteredSubjects = _getFilteredSubjectsForExam(exam);

    if (filteredSubjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No subjects assigned to you for ${exam['exam_name']}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _AssignGradesDialog(
        exam: exam,
        classes: _classes,
        subjects: filteredSubjects,
        schoolCode: widget.schoolCode,
        teacherId: widget.teacherId,
        teacherName: widget.teacherName,
        onSave: () {
          _showMessage('Grades assigned successfully!');
        },
      ),
    );
  }

  // Filter students based on search query
  List<Map<String, dynamic>> get _filteredViewGrades {
    if (_searchQuery.isEmpty) return _viewGrades;

    return _viewGrades.where((grade) {
      final studentName = grade['student_name']?.toString().toLowerCase() ?? '';
      return studentName.contains(_searchQuery.toLowerCase());
    }).toList();
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
              color: const Color(0xFFF3E5F5),
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                const Icon(Icons.grade, size: 48, color: Color(0xFF7E57C2)),
                const SizedBox(height: 12),
                const Text(
                  'Grade Management',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7E57C2),
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
                    _buildCompactStatItem(_exams.length.toString(), 'Exams'),
                    _buildCompactStatItem(
                      _classes.length.toString(),
                      'Classes',
                    ),
                    _buildCompactStatItem(
                      _assignedSubjects.length.toString(),
                      'Subjects',
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
            color: const Color(0xFF7E57C2).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF7E57C2),
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
            icon: const Icon(Icons.arrow_back, color: Color(0xFF7E57C2)),
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
            'Grade Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF7E57C2),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF7E57C2)),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
    );
  }

  Widget _buildAssignGradesTab() {
    if (_exams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'No Exams Available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Exams will appear here once created by admin',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _exams.length,
      itemBuilder: (context, index) {
        final exam = _exams[index];
        final subjectsMarksDynamic =
            exam['subjects_marks'] as List<dynamic>? ?? [];
        final subjectsMarks = subjectsMarksDynamic.map((item) {
          return item as Map<String, dynamic>;
        }).toList();

        final filteredSubjects = _getFilteredSubjectsForExam(exam);

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF7E57C2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.assignment,
                color: const Color(0xFF7E57C2),
                size: 28,
              ),
            ),
            title: Text(
              exam['exam_name'],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  '${subjectsMarks.length} subject${subjectsMarks.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your Subjects: ${filteredSubjects.length} available',
                  style: TextStyle(
                    fontSize: 12,
                    color: filteredSubjects.isEmpty
                        ? Colors.orange
                        : Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            trailing: ElevatedButton.icon(
              onPressed: filteredSubjects.isEmpty
                  ? null
                  : () => _showAssignGradesDialog(exam),
              icon: const Icon(Icons.grade, size: 18),
              label: const Text('Assign Grades'),
              style: ElevatedButton.styleFrom(
                backgroundColor: filteredSubjects.isEmpty
                    ? Colors.grey
                    : const Color(0xFF7E57C2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
          ),
        );
      },
    );
  }

  Widget _buildViewEditGradesTab() {
    final filteredViewSubjects = _getFilteredSubjectsForView();

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selection Card
          Card(
            elevation: 2,
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select Criteria to View Grades',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7E57C2),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // For mobile - always use column layout
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCompactDropdown(
                        value: _selectedViewExamId,
                        hint: 'Select Exam',
                        items: _exams,
                        onChanged: (String? value) {
                          setState(() {
                            _selectedViewExamId = value;
                            _selectedViewClassId = null;
                            _selectedViewSubjectId = null;
                            _viewGrades = [];
                            _searchQuery = '';
                          });
                        },
                        displayText: (item) => item['exam_name'],
                      ),
                      const SizedBox(height: 12),
                      _buildCompactDropdown(
                        value: _selectedViewClassId,
                        hint: 'Select Class',
                        items: _classes,
                        onChanged: (String? value) {
                          setState(() {
                            _selectedViewClassId = value;
                            _selectedViewSubjectId = null;
                            _viewGrades = [];
                            _searchQuery = '';
                          });
                        },
                        displayText: (item) => item['className'],
                      ),
                      const SizedBox(height: 12),
                      _buildCompactDropdown(
                        value: _selectedViewSubjectId,
                        hint: 'Select Subject',
                        items: filteredViewSubjects,
                        onChanged: filteredViewSubjects.isEmpty
                            ? null
                            : (String? value) {
                                setState(() {
                                  _selectedViewSubjectId = value;
                                  _searchQuery = '';
                                });
                                _loadViewGrades();
                              },
                        displayText: (item) => item['subject_name'],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _selectedViewExamId != null &&
                                  _selectedViewClassId != null &&
                                  _selectedViewSubjectId != null
                              ? _loadViewGrades
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7E57C2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _isLoadingGrades
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Load Grades'),
                        ),
                      ),
                    ],
                  ),

                  if (filteredViewSubjects.isEmpty &&
                      _selectedViewExamId != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.orange[700], size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No subjects assigned to you for this exam',
                              style: TextStyle(
                                color: Colors.orange[700],
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Grades List Area - Use flexible space with minimum height
          Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.3,
            ),
            child: _buildGradesContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildGradesContent() {
    if (_selectedViewExamId == null ||
        _selectedViewClassId == null ||
        _selectedViewSubjectId == null) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: _buildEmptyState(
          icon: Icons.assignment_outlined,
          title: 'Select Criteria',
          subtitle: 'Please select exam, class and subject to view grades',
        ),
      );
    }

    if (_isLoadingGrades) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                strokeWidth: 3,
                color: const Color(0xFF7E57C2),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading Grades...',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    if (_viewGrades.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: _buildEmptyState(
          icon: Icons.assignment_outlined,
          title: 'No Grades Found',
          subtitle: 'No grades found for the selected criteria',
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header with search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Assigned Grades (${_filteredViewGrades.length} student${_filteredViewGrades.length == 1 ? '' : 's'})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7E57C2),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search students...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),

        const SizedBox(height: 8),

        // Grades List
        _filteredViewGrades.isEmpty
            ? Container(
                padding: const EdgeInsets.all(32),
                child: _buildEmptyState(
                  icon: Icons.search_off,
                  title: 'No Students Found',
                  subtitle: 'No students match your search criteria',
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filteredViewGrades.length,
                itemBuilder: (context, index) {
                  return _buildGradeCard(_filteredViewGrades[index]);
                },
              ),
      ],
    );
  }

  // Helper method for compact dropdowns
  Widget _buildCompactDropdown({
    required String? value,
    required String hint,
    required List<Map<String, dynamic>> items,
    required void Function(String?)? onChanged,
    required String Function(Map<String, dynamic>) displayText,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        isDense: true,
      ),
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item['id'],
          child: Text(
            displayText(item),
            style: const TextStyle(fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: onChanged == null
          ? null
          : (String? newValue) {
              onChanged(newValue);
              // Load grades immediately when subject is selected in mobile
              if (hint == 'Select Subject' && newValue != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _loadViewGrades();
                  }
                });
              }
            },
    );
  }

  Widget _buildGradeCard(Map<String, dynamic> grade) {
    final maxMarks = grade['max_marks'] ?? 0;
    final currentMarks = grade['marks_obtained'];
    final isAbsent = grade['is_absent'] ?? false;
    final isNotAssigned = grade['is_not_assigned'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: isNotAssigned
                  ? Colors.grey.withOpacity(0.1)
                  : isAbsent
                  ? Colors.orange.withOpacity(0.1)
                  : const Color(0xFF7E57C2).withOpacity(0.1),
              child: Text(
                grade['student_name']
                        ?.toString()
                        .substring(0, 1)
                        .toUpperCase() ??
                    'S',
                style: TextStyle(
                  color: isNotAssigned
                      ? Colors.grey
                      : isAbsent
                      ? Colors.orange
                      : const Color(0xFF7E57C2),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grade['student_name'] ?? 'Unknown Student',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Exam: ${grade['exam_name'] ?? 'Unknown'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (isNotAssigned) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Not Graded Yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isNotAssigned
                    ? Colors.grey.withOpacity(0.1)
                    : isAbsent
                    ? Colors.orange.withOpacity(0.1)
                    : const Color(0xFF7E57C2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isNotAssigned
                      ? Colors.grey
                      : isAbsent
                      ? Colors.orange
                      : const Color(0xFF7E57C2).withOpacity(0.3),
                ),
              ),
              child: Text(
                isNotAssigned
                    ? 'NOT SET'
                    : isAbsent
                    ? 'ABSENT'
                    : '$currentMarks/$maxMarks',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isNotAssigned
                      ? Colors.grey
                      : isAbsent
                      ? Colors.orange
                      : const Color(0xFF7E57C2),
                  fontSize: isNotAssigned || isAbsent ? 12 : 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: Icon(
                Icons.edit,
                color: isNotAssigned ? Colors.green : Colors.blue,
                size: 24,
              ),
              onPressed: () => _showEditGradeDialog(grade),
              tooltip: isNotAssigned ? 'Assign Grade' : 'Edit Grade',
            ),
          ],
        ),
      ),
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
          Icon(icon, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
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
              color: Color(0xFF7E57C2),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.assignment,
            'Assign Grades',
            'Select an exam, class, and your assigned subject to enter marks for students',
          ),
          _buildInfoItem(
            Icons.visibility,
            'View & Edit Grades',
            'Review and modify grades you have previously assigned to students',
          ),
          _buildInfoItem(
            Icons.filter_alt,
            'Subject Filtering',
            'You can only see and assign grades for subjects assigned to you by admin',
          ),
          _buildInfoItem(
            Icons.save,
            'Auto Save',
            'Grades are automatically saved and can be edited later if needed',
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
              color: Color(0xFF7E57C2),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem('📝', 'Double-check marks before saving'),
          _buildTipItem(
            '🔄',
            'You can update grades anytime in the View/Edit section',
          ),
          _buildTipItem(
            '📊',
            'Ensure marks do not exceed maximum marks for the subject',
          ),
          _buildTipItem(
            '👥',
            'Only students in selected class will appear for grading',
          ),
          _buildTipItem(
            '🚫',
            'Mark students as absent if they missed the exam',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF7E57C2).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF7E57C2).withOpacity(0.3),
              ),
            ),
            child: const Text(
              'Need help? Contact your school administrator for assistance with grade management.',
              style: TextStyle(fontSize: 12, color: Color(0xFF7E57C2)),
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
          Icon(icon, size: 20, color: const Color(0xFF7E57C2)),
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
              ? const Color(0xFF7E57C2)
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
                            labelColor: const Color(0xFF7E57C2),
                            unselectedLabelColor: Colors.grey,
                            indicator: BoxDecoration(
                              color: const Color(0xFF7E57C2).withOpacity(0.1),
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
                                icon: Icon(Icons.assignment, size: 20),
                                text: 'Assign Grades',
                              ),
                              Tab(
                                icon: Icon(Icons.visibility, size: 20),
                                text: 'View/Edit Grades',
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
                              _buildAssignGradesTab(),
                              _buildViewEditGradesTab(),
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
          _isMobile ? 'Grades' : 'Grade Management - ${widget.schoolName}',
          style: TextStyle(
            fontSize: _isMobile ? 18 : 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFFF3E5F5),
        foregroundColor: const Color(0xFF7E57C2),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF7E57C2),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF7E57C2),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.assignment), text: 'Assign Grades'),
            Tab(icon: Icon(Icons.visibility), text: 'View/Edit Grades'),
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
          : Column(
              children: [
                // Messages - Fixed height section
                if (_errorMessage != null) _buildMessage(_errorMessage!, true),
                if (_successMessage != null)
                  _buildMessage(_successMessage!, false),

                // Compact Statistics - Fixed height section
                Card(
                  elevation: 2,
                  margin: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCompactStatItem(
                          _exams.length.toString(),
                          'Exams',
                        ),
                        _buildCompactStatItem(
                          _classes.length.toString(),
                          'Classes',
                        ),
                        _buildCompactStatItem(
                          _assignedSubjects.length.toString(),
                          'Subjects',
                        ),
                      ],
                    ),
                  ),
                ),

                // Tab Content - Expanded to take remaining space with proper scrolling
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAssignGradesTab(),
                      _buildViewEditGradesTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
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

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return _buildDesktopLayout();
    } else {
      return _buildMobileTabletLayout();
    }
  }
}

class _AssignGradesDialog extends StatefulWidget {
  final Map<String, dynamic> exam;
  final List<Map<String, dynamic>> classes;
  final List<Map<String, dynamic>> subjects;
  final String schoolCode;
  final String teacherId;
  final String teacherName;
  final VoidCallback onSave;

  const _AssignGradesDialog({
    required this.exam,
    required this.classes,
    required this.subjects,
    required this.schoolCode,
    required this.teacherId,
    required this.teacherName,
    required this.onSave,
  });

  @override
  State<_AssignGradesDialog> createState() => __AssignGradesDialogState();
}

class __AssignGradesDialogState extends State<_AssignGradesDialog> {
  String? _selectedClassId;
  String? _selectedSubjectId;
  List<Map<String, dynamic>> _students = [];
  Map<String, TextEditingController> _marksControllers = {};
  Map<String, bool> _absentStatus = {};
  bool _isLoading = false;
  bool _studentsLoading = false;
  String? _errorMessage;
  int? _maxMarks;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _marksControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _loadExistingGrades(String classId, String subjectId) async {
    if (widget.exam['id'] == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('grades')
          .where('exam_id', isEqualTo: widget.exam['id'])
          .where('teacher_id', isEqualTo: widget.teacherId)
          .where('class_id', isEqualTo: classId)
          .where('subject_id', isEqualTo: subjectId)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final studentId = data['student_id'];
        final marks = data['marks_obtained']?.toString() ?? '';
        final isAbsent = data['is_absent'] ?? false;

        if (_marksControllers.containsKey(studentId)) {
          _marksControllers[studentId]!.text = isAbsent ? '' : marks;
        }
        if (_absentStatus.containsKey(studentId)) {
          _absentStatus[studentId] = isAbsent;
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error loading existing grades: $e');
    }
  }

  Future<void> _loadStudents() async {
    if (_selectedClassId == null) return;

    setState(() {
      _studentsLoading = true;
      _errorMessage = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .where('class_id', isEqualTo: _selectedClassId)
          .get();

      setState(() {
        _students = snapshot.docs.map((doc) {
          final data = doc.data();
          final studentId = doc.id;

          if (!_marksControllers.containsKey(studentId)) {
            _marksControllers[studentId] = TextEditingController();
          }
          if (!_absentStatus.containsKey(studentId)) {
            _absentStatus[studentId] = false;
          }

          return {
            'id': studentId,
            'username': data['username'],
            'full_name':
                data['full_name'] ??
                data['username'], // Use full_name with fallback
            'section': data['section'],
          };
        }).toList();
        _studentsLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading students: $e';
        _studentsLoading = false;
      });
    }
  }

  void _onClassChanged(String? classId) {
    setState(() {
      _selectedClassId = classId;
      _selectedSubjectId = null;
      _students.clear();
      _maxMarks = null;
      _searchQuery = '';
      _marksControllers.clear();
      _absentStatus.clear();
    });
    if (classId != null) {
      _loadStudents();
    }
  }

  void _onSubjectChanged(String? subjectId) {
    setState(() {
      _selectedSubjectId = subjectId;
      if (subjectId != null) {
        final subjectsMarksDynamic =
            widget.exam['subjects_marks'] as List<dynamic>? ?? [];
        final subjectsMarks = subjectsMarksDynamic.map((item) {
          return item as Map<String, dynamic>;
        }).toList();

        final subject = subjectsMarks.firstWhere(
          (sm) => sm['subject_id'] == subjectId,
          orElse: () => <String, dynamic>{},
        );
        _maxMarks = int.tryParse(subject['max_marks']?.toString() ?? '0');

        if (_selectedClassId != null) {
          _loadExistingGrades(_selectedClassId!, subjectId);
        }
      } else {
        _maxMarks = null;
      }
    });
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_searchQuery.isEmpty) return _students;

    return _students.where((student) {
      final username = student['username']?.toString().toLowerCase() ?? '';
      final fullName = student['full_name']?.toString().toLowerCase() ?? '';
      return username.contains(_searchQuery.toLowerCase()) ||
          fullName.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  bool get _canSave {
    return _selectedClassId != null &&
        _selectedSubjectId != null &&
        _students.isNotEmpty;
  }

  Future<void> _saveGrades() async {
    if (!_canSave) return;

    bool hasAnyMarks = false;

    for (var student in _students) {
      final marksText = _marksControllers[student['id']]!.text.trim();
      final isAbsent = _absentStatus[student['id']] ?? false;

      if (marksText.isNotEmpty || isAbsent) {
        hasAnyMarks = true;

        if (!isAbsent) {
          final marks = int.tryParse(marksText);
          if (marks == null) {
            setState(() {
              _errorMessage = 'Please enter valid numbers for all marks';
            });
            return;
          }
          if (_maxMarks != null && marks > _maxMarks!) {
            setState(() {
              _errorMessage =
                  'Marks cannot exceed maximum marks ($_maxMarks) for ${student['full_name'] ?? student['username']}';
            });
            return;
          }
        }
      }
    }

    if (!hasAnyMarks) {
      setState(() {
        _errorMessage =
            'Please enter marks or mark absent for at least one student';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final gradesRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('grades');

      for (var student in _students) {
        final marksText = _marksControllers[student['id']]!.text.trim();
        final isAbsent = _absentStatus[student['id']] ?? false;

        if (marksText.isNotEmpty || isAbsent) {
          final marks = isAbsent ? 0 : int.parse(marksText);

          final gradeId =
              '${widget.exam['id']}_${_selectedSubjectId}_${student['id']}';

          final subject = widget.subjects.firstWhere(
            (s) => s['id'] == _selectedSubjectId,
            orElse: () => {'subject_name': 'Unknown Subject'},
          );

          final gradeData = {
            'exam_id': widget.exam['id'],
            'exam_name': widget.exam['exam_name'],
            'subject_id': _selectedSubjectId,
            'subject_name': subject['subject_name'],
            'class_id': _selectedClassId,
            'student_id': student['id'],
            'student_name':
                student['full_name'] ?? student['username'], // Use full_name
            'marks_obtained': marks,
            'is_absent': isAbsent,
            'max_marks': _maxMarks,
            'teacher_id': widget.teacherId,
            'teacher_name': widget.teacherName,
            'school_code': widget.schoolCode,
            'created_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
          };

          await gradesRef.doc(gradeId).set(gradeData);
        }
      }

      setState(() {
        _isLoading = false;
      });

      widget.onSave();
      Navigator.pop(context);
    } catch (e) {
      print('Error saving grades: $e');
      setState(() {
        _errorMessage = 'Error saving grades: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final isSmallScreen = MediaQuery.of(context).size.width < 400;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isDesktop
              ? MediaQuery.of(context).size.width *
                    0.6 // Smaller for web
              : MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7E57C2).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.grade,
                    color: const Color(0xFF7E57C2),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign Grades - ${widget.exam['exam_name']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select class and subject to assign marks',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Form content - Made scrollable
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Class Selection
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '1. Select Class',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedClassId,
                              decoration: const InputDecoration(
                                labelText: 'Class *',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                              ),
                              items: widget.classes.map((classData) {
                                return DropdownMenuItem<String>(
                                  value: classData['id'],
                                  child: Text(classData['className']),
                                );
                              }).toList(),
                              onChanged: _onClassChanged,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Subject Selection
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '2. Select Subject',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedSubjectId,
                              decoration: InputDecoration(
                                labelText: 'Subject *',
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                hintText: widget.subjects.isEmpty
                                    ? 'No subjects available'
                                    : null,
                              ),
                              items: widget.subjects.map((subject) {
                                return DropdownMenuItem<String>(
                                  value: subject['id'],
                                  child: Text(subject['subject_name']),
                                );
                              }).toList(),
                              onChanged: widget.subjects.isEmpty
                                  ? null
                                  : _onSubjectChanged,
                            ),
                            if (_maxMarks != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.info,
                                      color: Colors.blue[700],
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Maximum Marks: $_maxMarks',
                                      style: TextStyle(
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (widget.subjects.isEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.warning,
                                      color: Colors.orange[700],
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'No subjects assigned to you for this exam',
                                        style: TextStyle(
                                          color: Colors.orange[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Students List
                    if (_studentsLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (_students.isNotEmpty)
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '3. Enter Marks',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF7E57C2,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_filteredStudents.length} student${_filteredStudents.length == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        color: Color(0xFF7E57C2),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Search Bar
                              TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search students...',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),

                              // Students List - Fixed layout
                              ..._filteredStudents.map((student) {
                                final isAbsent =
                                    _absentStatus[student['id']] ?? false;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey[200]!,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      // Student Info Row
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: const Color(
                                              0xFF7E57C2,
                                            ).withOpacity(0.1),
                                            radius: 20,
                                            child: Text(
                                              (student['full_name'] ??
                                                      student['username'])
                                                  .toString()
                                                  .substring(0, 1)
                                                  .toUpperCase(),
                                              style: TextStyle(
                                                color: const Color(0xFF7E57C2),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  student['full_name'] ??
                                                      student['username'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  'Section: ${student['section'] ?? 'N/A'}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Marks and Absent Section - Better responsive layout
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Absent Checkbox
                                          Row(
                                            children: [
                                              Checkbox(
                                                value: isAbsent,
                                                onChanged: (value) {
                                                  setState(() {
                                                    _absentStatus[student['id']] =
                                                        value ?? false;
                                                    if (value == true) {
                                                      _marksControllers[student['id']]!
                                                          .clear();
                                                    }
                                                  });
                                                },
                                              ),
                                              const Text('Mark as Absent'),
                                            ],
                                          ),
                                          const SizedBox(height: 8),

                                          // Marks Input - Full width
                                          TextFormField(
                                            controller:
                                                _marksControllers[student['id']],
                                            enabled: !isAbsent,
                                            decoration: InputDecoration(
                                              labelText: isAbsent
                                                  ? 'Marks (Absent)'
                                                  : 'Marks',
                                              border:
                                                  const OutlineInputBorder(),
                                              suffixText:
                                                  _maxMarks != null && !isAbsent
                                                  ? '/$_maxMarks'
                                                  : null,
                                              filled: isAbsent,
                                              fillColor: isAbsent
                                                  ? Colors.grey[200]
                                                  : null,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                            ),
                                            keyboardType: TextInputType.number,
                                          ),
                                        ],
                                      ),

                                      if (isAbsent) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.orange[50],
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: Colors.orange,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.info,
                                                color: Colors.orange[700],
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Student will be marked as absent (0 marks)',
                                                  style: TextStyle(
                                                    color: Colors.orange[700],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      )
                    else if (_selectedClassId != null)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              'No students found in this class',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                      ),

                    // Error message
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading || !_canSave ? null : _saveGrades,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'Save Grades',
                            style: TextStyle(fontWeight: FontWeight.w600),
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
