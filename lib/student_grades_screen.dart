import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'student_dashboard_screen.dart';

class StudentGradesScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String studentId;
  final String studentName;
  final String userId;

  const StudentGradesScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.studentId,
    required this.studentName,
    required this.userId,
  });

  @override
  State<StudentGradesScreen> createState() => _StudentGradesScreenState();
}

class _StudentGradesScreenState extends State<StudentGradesScreen> {
  List<Map<String, dynamic>> _availableExams = [];
  Map<String, dynamic>? _selectedExam;
  List<Map<String, dynamic>> _examGrades = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isRefreshing = false;

  // Cache management
  final Map<String, dynamic> _gradesCache = {};
  late SharedPreferences _prefs;

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
    _initSharedPreferences();
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    await Future.wait([_loadCachedGrades(), _loadAvailableExams()]);
  }

  Future<void> _loadCachedGrades() async {
    final cachedGrades = _prefs.getString(
      'cachedGrades_${widget.schoolCode}_${widget.studentId}',
    );
    final cachedGradesTimestamp = _prefs.getInt(
      'cachedGradesTimestamp_${widget.schoolCode}_${widget.studentId}',
    );

    if (cachedGrades != null && cachedGradesTimestamp != null) {
      final cacheAge =
          DateTime.now().millisecondsSinceEpoch - cachedGradesTimestamp;
      if (cacheAge < 10 * 60 * 1000) {
        // 10 minutes cache
        try {
          final decodedData = jsonDecode(cachedGrades);
          setState(() {
            _gradesCache['data'] = decodedData;
            _gradesCache['timestamp'] = cachedGradesTimestamp;
          });
        } catch (e) {
          print('Error decoding grades cache: $e');
        }
      }
    }
  }

  Future<void> _loadAvailableExams() async {
    try {
      // Load exams that have grades for this student
      final gradesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('grades')
          .where('student_id', isEqualTo: widget.studentId)
          .get();

      if (gradesSnapshot.docs.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get unique exam IDs from grades
      final examIds = gradesSnapshot.docs
          .map((doc) => doc.data()['exam_id'] as String)
          .toSet()
          .toList();

      // Load exam details with subjects_marks
      List<Map<String, dynamic>> exams = [];
      for (var examId in examIds) {
        final examDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('exams')
            .doc(examId)
            .get();

        if (examDoc.exists) {
          final examData = examDoc.data()!;
          exams.add({
            'id': examId,
            'exam_name': examData['exam_name'],
            'exam_description': examData['exam_description'] ?? '',
            'created_at': examData['created_at'],
            'subjects_marks':
                examData['subjects_marks'] ?? [], // Make sure this is included
          });
        }
      }

      setState(() {
        _availableExams = exams;
        _isLoading = false;
      });

      // Cache the data
      await _cacheGradesData();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading exams: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _onExamSelected(Map<String, dynamic>? exam) async {
    if (exam == null) {
      setState(() {
        _selectedExam = null;
        _examGrades = [];
      });
      return;
    }

    setState(() {
      _selectedExam = exam;
    });

    await _loadGradesForExam(exam['id']);
  }

  Future<void> _loadGradesForExam(String examId) async {
    try {
      // First, get the exam details to know which subjects are scheduled
      final exam = _availableExams.firstWhere(
        (exam) => exam['id'] == examId,
        orElse: () => {},
      );

      if (exam.isEmpty) {
        setState(() {
          _errorMessage = 'Exam details not found';
          _examGrades = [];
        });
        return;
      }

      // Get the list of subject IDs from the exam schedule
      final subjectsInExam = List<Map<String, dynamic>>.from(
        exam['subjects_marks'] ?? [],
      );
      final subjectIdsInExam = subjectsInExam
          .map((subject) => subject['subject_id'] as String)
          .toSet();

      // Load all grades for this student and exam
      final gradesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('grades')
          .where('student_id', isEqualTo: widget.studentId)
          .where('exam_id', isEqualTo: examId)
          .get();

      // Filter grades to only include subjects that are in the exam schedule
      final filteredGrades = gradesSnapshot.docs
          .where((doc) {
            final gradeData = doc.data();
            final subjectId = gradeData['subject_id'] as String;
            return subjectIdsInExam.contains(subjectId);
          })
          .map((doc) => doc.data())
          .toList();

      setState(() {
        _examGrades = filteredGrades;
      });

      // Cache the selected exam grades
      await _prefs.setString(
        'cachedExamGrades_${widget.schoolCode}_${widget.studentId}_$examId',
        jsonEncode(_convertToSerializable({'grades': _examGrades})),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading grades for selected exam: $e';
      });
    }
  }

  Future<void> _cacheGradesData() async {
    final cacheData = {'exams': _availableExams};

    await _prefs.setString(
      'cachedGrades_${widget.schoolCode}_${widget.studentId}',
      jsonEncode(_convertToSerializable(cacheData)),
    );
    await _prefs.setInt(
      'cachedGradesTimestamp_${widget.schoolCode}_${widget.studentId}',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  // Convert data to serializable format
  Map<String, dynamic> _convertToSerializable(Map<String, dynamic> data) {
    final converted = Map<String, dynamic>.from(data);

    converted.forEach((key, value) {
      if (value is Timestamp) {
        converted[key] = value.millisecondsSinceEpoch;
      } else if (value is List) {
        converted[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _convertToSerializable(item);
          }
          return item;
        }).toList();
      } else if (value is Map<String, dynamic>) {
        converted[key] = _convertToSerializable(value);
      }
    });

    return converted;
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
    });

    try {
      // Clear cache
      await _prefs.remove(
        'cachedGrades_${widget.schoolCode}_${widget.studentId}',
      );
      await _prefs.remove(
        'cachedGradesTimestamp_${widget.schoolCode}_${widget.studentId}',
      );
      if (_selectedExam != null) {
        await _prefs.remove(
          'cachedExamGrades_${widget.schoolCode}_${widget.studentId}_${_selectedExam!['id']}',
        );
      }

      setState(() {
        _gradesCache.clear();
        _availableExams.clear();
        _selectedExam = null;
        _examGrades.clear();
      });

      await _loadAvailableExams();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error refreshing data: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Map<String, dynamic>? _getSubjectDetails(String examId, String subjectId) {
    // First try to find the exam in available exams
    final exam = _availableExams.firstWhere(
      (exam) => exam['id'] == examId,
      orElse: () => {},
    );

    if (exam.isEmpty) return null;

    // Get subjects_marks from the exam
    final subjectsMarks = List<Map<String, dynamic>>.from(
      exam['subjects_marks'] ?? [],
    );

    // Find the specific subject
    try {
      return subjectsMarks.firstWhere(
        (subject) => subject['subject_id'] == subjectId,
      );
    } catch (e) {
      return null;
    }
  }

  // Helper method to safely convert to int
  int _safeParseInt(dynamic value) {
    if (value == null) return -1; // Use -1 to indicate "not graded"
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed ?? -1; // Return -1 if parsing fails
    }
    if (value is double) return value.toInt();
    return -1; // Default to -1 for unknown types
  }

  // Desktop Layout
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar with auto-slide
        _GradesInfoSidebar(
          schoolName: widget.schoolName,
          studentName: widget.studentName,
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
              color: Color.fromARGB(255, 156, 39, 176),
            ),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => StudentDashboardScreen(
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
            'My Grades & Results',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 156, 39, 176),
            ),
          ),
          const Spacer(),
          if (_isRefreshing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color.fromARGB(255, 156, 39, 176),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.purple),
              onPressed: _refreshData,
              tooltip: 'Refresh Grades',
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
            Icon(Icons.grade, color: Colors.white),
            SizedBox(width: 12),
            Text(
              '${widget.schoolName} - Grades',
              style: TextStyle(fontSize: _isDesktop ? 20 : 18),
            ),
          ],
        ),
        backgroundColor: Color.fromARGB(255, 156, 39, 176),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh Grades',
          ),
        ],
      ),
      body: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    return Column(
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
                      backgroundColor: Colors.purple[100],
                      child: Icon(Icons.person, color: Colors.purple[700]),
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
                            '${_availableExams.length} exam${_availableExams.length == 1 ? '' : 's'} available',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
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

        // Exam Selection Dropdown
        Padding(
          padding: _isDesktop
              ? const EdgeInsets.fromLTRB(24, 16, 24, 16)
              : const EdgeInsets.symmetric(horizontal: 16),
          child: _buildExamSelectionDropdown(),
        ),

        const SizedBox(height: 16),

        // Grades Display
        if (_selectedExam == null)
          _buildNoExamSelected()
        else if (_examGrades.isEmpty)
          _buildNoGradesAvailable()
        else
          Expanded(child: _buildGradesList()),
      ],
    );
  }

  Widget _buildExamSelectionDropdown() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.search,
                  color: Color.fromARGB(255, 156, 39, 176),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Select Exam',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color.fromARGB(255, 156, 39, 176),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: DropdownButton<Map<String, dynamic>>(
                value: _selectedExam,
                hint: Text(
                  'Choose an exam to view grades',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                iconSize: 24,
                elevation: 16,
                style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                underline: const SizedBox(),
                onChanged: _onExamSelected,
                items: _availableExams.map((exam) {
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: exam,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          exam['exam_name'] ?? 'Unknown Exam',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (exam['exam_description'] != null &&
                            exam['exam_description'].isNotEmpty)
                          Text(
                            exam['exam_description'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            if (_availableExams.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'No exams with grades available',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoExamSelected() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Select an Exam',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                'Choose an exam from the dropdown above to view your grades',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color.fromARGB(255, 158, 157, 157),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoGradesAvailable() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grade_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Grades Available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                'Grades for the selected exam will appear here once published',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color.fromARGB(255, 158, 157, 157),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradesList() {
    return ListView.builder(
      padding: _isDesktop
          ? const EdgeInsets.fromLTRB(24, 0, 24, 24)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _examGrades.length,
      itemBuilder: (context, index) {
        final grade = _examGrades[index];

        // Get subject details from the exam to get max_marks and pass_marks
        final subjectDetails = _getSubjectDetails(
          _selectedExam!['id'],
          grade['subject_id'],
        );

        // Use safe parsing to handle different data types
        final maxMarks = _safeParseInt(subjectDetails?['max_marks']);
        final passMarks = _safeParseInt(subjectDetails?['pass_marks']);
        final marksObtained = _safeParseInt(grade['marks_obtained']);
        final isAbsent = grade['is_absent'] == true;

        // Check if the subject has been graded (marksObtained >= 0)
        final isGraded = marksObtained >= 0;

        // Determine status, color, and icon
        String status;
        Color statusColor;
        IconData statusIcon;

        if (isAbsent) {
          status = 'ABSENT';
          statusColor = Colors.orange;
          statusIcon = Icons.person_off;
        } else if (!isGraded) {
          status = 'NOT GRADED';
          statusColor = Colors.grey;
          statusIcon = Icons.pending;
        } else {
          final isPass = marksObtained >= passMarks;
          status = isPass ? 'PASS' : 'FAIL';
          statusColor = isPass ? Colors.green : Colors.red;
          statusIcon = isPass ? Icons.check_circle : Icons.cancel;
        }

        return Card(
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject header
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: isAbsent
                            ? const LinearGradient(
                                colors: [Colors.orange, Colors.deepOrange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : const LinearGradient(
                                colors: [Colors.purple, Colors.deepPurple],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isAbsent ? Icons.person_off : Icons.subject,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            grade['subject_name'] ?? 'Unknown Subject',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Exam: ${_selectedExam?['exam_name'] ?? 'Unknown Exam'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (isAbsent) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Status: Marked as Absent',
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
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Grade details
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildGradeDetail(
                      'Marks Obtained',
                      isAbsent
                          ? 'ABSENT'
                          : (isGraded ? '$marksObtained' : 'N/A'),
                      Icons.score,
                      isAbsent
                          ? Colors.orange
                          : (isGraded ? Colors.blue : Colors.grey),
                    ),
                    _buildGradeDetail(
                      'Total Marks',
                      maxMarks >= 0 ? '$maxMarks' : 'N/A',
                      Icons.assessment,
                      maxMarks >= 0 ? Colors.green : Colors.grey,
                    ),
                    _buildGradeDetail(
                      'Pass Marks',
                      passMarks >= 0 ? '$passMarks' : 'N/A',
                      Icons.assignment_turned_in,
                      passMarks >= 0 ? Colors.orange : Colors.grey,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Status
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        status,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Additional info for absent students
                if (isAbsent) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange[700],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You were marked as absent for this subject. Marks: 0/${maxMarks >= 0 ? maxMarks : "N/A"}',
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
        );
      },
    );
  }

  Widget _buildGradeDetail(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            color: Color.fromARGB(255, 156, 39, 176),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading Grades...',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String message, bool isError) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: _isDesktop ? 24 : 16),
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
class _GradesInfoSidebar extends StatefulWidget {
  final String schoolName;
  final String studentName;

  const _GradesInfoSidebar({
    required this.schoolName,
    required this.studentName,
  });

  @override
  State<_GradesInfoSidebar> createState() => _GradesInfoSidebarState();
}

class _GradesInfoSidebarState extends State<_GradesInfoSidebar> {
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
            'Understanding Your Grades',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 156, 39, 176),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.assignment,
            'Select Exam First',
            'Choose an exam from the dropdown to view your grades',
          ),
          _buildInfoItem(
            Icons.grade,
            'Subject-wise Grades',
            'View marks, total marks, and grade for each subject',
          ),
          _buildInfoItem(
            Icons.person_off,
            'Absent Status',
            'Orange ABSENT status means you were marked absent for that subject',
          ),
          _buildInfoItem(
            Icons.assessment,
            'Performance Status',
            'See pass/fail status for each subject',
          ),
          _buildInfoItem(
            Icons.timeline,
            'Progress Tracking',
            'Monitor your academic performance across exams',
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
            'Grade Interpretation',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 156, 39, 176),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            '📊',
            'Select an exam first to view your detailed grades',
          ),
          _buildTipItem(
            '✅',
            'Green PASS status indicates successful completion',
          ),
          _buildTipItem('❌', 'Red FAIL status means you need improvement'),
          _buildTipItem(
            '🚫',
            'Orange ABSENT status means you were marked absent',
          ),
          _buildTipItem(
            '📈',
            'Compare marks obtained vs total marks for each subject',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.fromARGB(255, 156, 39, 176).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Color.fromARGB(255, 156, 39, 176).withOpacity(0.3),
              ),
            ),
            child: const Text(
              'Regularly check your grades to track your academic progress and identify areas that need improvement.',
              style: TextStyle(
                fontSize: 12,
                color: Color.fromARGB(255, 156, 39, 176),
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
          Icon(icon, size: 20, color: Color.fromARGB(255, 156, 39, 176)),
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
              color: Color.fromARGB(255, 156, 39, 176).withOpacity(0.1),
              border: Border(
                bottom: BorderSide(
                  color: Color.fromARGB(255, 156, 39, 176).withOpacity(0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.grade,
                  size: 40,
                  color: Color.fromARGB(255, 156, 39, 176),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Grades & Results',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 156, 39, 176),
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
                    color: Color.fromARGB(255, 156, 39, 176),
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
