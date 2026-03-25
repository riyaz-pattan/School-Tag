import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'student_assignment_submit_screen.dart';
import 'student_quiz_screen.dart';
import 'student_dashboard_screen.dart';

class StudentAssignmentsScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String studentId;
  final String studentName;

  const StudentAssignmentsScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentAssignmentsScreen> createState() =>
      _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState extends State<StudentAssignmentsScreen> {
  List<Map<String, dynamic>> _assignments = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _studentClassId;
  String? _studentSection;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  @override
  void initState() {
    super.initState();
    print(
      '🎯 StudentAssignmentsScreen initialized for student: ${widget.studentId}',
    );
    _loadStudentInfo();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  Future<void> _loadStudentInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.studentId)
          .get();

      if (studentDoc.exists) {
        final studentData = studentDoc.data() as Map<String, dynamic>? ?? {};
        setState(() {
          _studentClassId = studentData['class_id'];
          _studentSection = studentData['section'];
        });

        await _loadAssignments();
      } else {
        setState(() {
          _errorMessage = 'Student information not found';
          _isLoading = false;
        });
        _showErrorSnackbar('Failed to load student information');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading student info: ${e.toString()}';
        _isLoading = false;
      });
      _showErrorSnackbar('Error loading student information');
    }
  }

  Future<void> _loadAssignments() async {
    if (_studentClassId == null) {
      setState(() {
        _errorMessage = 'Student not assigned to any class';
        _isLoading = false;
      });
      _showErrorSnackbar('Student not assigned to any class');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get assignments for the class
      final assignmentsSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .where('class_id', isEqualTo: _studentClassId)
          .where('deleted', isNotEqualTo: true)
          .orderBy('created_at', descending: true)
          .get();

      List<Map<String, dynamic>> assignmentsWithStatus = [];

      // Create futures for all submission queries
      final submissionFutures = <Future<DocumentSnapshot>>[];
      final assignmentDocs = assignmentsSnapshot.docs;

      for (final doc in assignmentDocs) {
        final submissionFuture = FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('assignments')
            .doc(doc.id)
            .collection('submissions')
            .doc(widget.studentId)
            .get();

        submissionFutures.add(submissionFuture);
      }

      // Wait for all submission queries to complete
      final submissionSnapshots = await Future.wait(submissionFutures);

      for (int i = 0; i < assignmentDocs.length; i++) {
        final doc = assignmentDocs[i];
        final data = doc.data() as Map<String, dynamic>;

        // Filter by section if specified
        final assignmentSection = data['section'];
        if (assignmentSection != null && assignmentSection != _studentSection) {
          continue;
        }

        final submissionSnapshot = submissionSnapshots[i];
        final hasSubmitted = submissionSnapshot.exists;
        final submissionData =
            submissionSnapshot.data() as Map<String, dynamic>?;
        final marks = submissionData?['marks'];
        final teacherComments = submissionData?['teacher_comments'];
        final autoGrade = submissionData?['auto_grade'];
        final teacherGrade = submissionData?['teacher_grade'];

        final finalGrade = teacherGrade ?? autoGrade ?? marks;

        assignmentsWithStatus.add({
          'id': doc.id,
          'title': data['title'] ?? 'No Title',
          'description': data['description'] ?? 'No Description',
          'due_date': (data['due_date'] as Timestamp?)?.toDate(),
          'file_url': data['file_url'],
          'teacher_name': data['teacher_name'] ?? 'Unknown',
          'grade': data['grade'] ?? 'Unknown',
          'section': data['section'] ?? '',
          'assignment_type': data['assignment_type'] ?? 'file',
          'question_type': data['question_type'],
          'total_marks': data['total_marks'] ?? 0,
          'has_submitted': hasSubmitted,
          'submitted_at': submissionData?['submitted_at'] != null
              ? (submissionData!['submitted_at'] as Timestamp).toDate()
              : null,
          'marks': finalGrade,
          'teacher_comments': teacherComments,
          'submission_file_url': submissionData?['file_url'],
          'submission_file_name': submissionData?['file_name'],
          'submission_text': submissionData?['submission_text'],
        });
      }

      setState(() {
        _assignments = assignmentsWithStatus;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading assignments: ${e.toString()}';
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to load assignments');
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  void _viewAssignmentDetails(Map<String, dynamic> assignment) {
    final assignmentType = assignment['assignment_type'] ?? 'file';

    if (assignmentType == 'quiz') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StudentQuizScreen(
            userId: widget.userId,
            schoolName: widget.schoolName,
            assignmentId: assignment['id'],
            schoolCode: widget.schoolCode,
            studentId: widget.studentId,
            studentName: widget.studentName,
          ),
        ),
      ).then((_) {
        _loadAssignments();
      });
    } else {
      // FIXED LOGIC: Always open StudentAssignmentSubmitScreen for file assignments
      // This ensures resubmit option is available when assignment is not graded
      // and due date hasn't passed
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StudentAssignmentSubmitScreen(
            userId: widget.userId,
            schoolName: widget.schoolName,
            assignmentId: assignment['id'],
            schoolCode: widget.schoolCode,
            studentId: widget.studentId,
            studentName: widget.studentName,
          ),
        ),
      ).then((_) {
        _loadAssignments();
      });
    }
  }

  Color _getStatusColor(Map<String, dynamic> assignment) {
    if (assignment['has_submitted'] == true) {
      if (assignment['marks'] != null) {
        return Colors.green;
      }
      return Colors.blue;
    }

    final dueDate = assignment['due_date'];
    if (dueDate != null && dueDate.isBefore(DateTime.now())) {
      return Colors.red;
    }

    return Colors.orange;
  }

  String _getStatusText(Map<String, dynamic> assignment) {
    if (assignment['has_submitted'] == true) {
      if (assignment['marks'] != null) {
        final assignmentType = assignment['assignment_type'] ?? 'file';
        if (assignmentType == 'quiz') {
          return 'Graded: ${assignment['marks']}/${assignment['total_marks']}';
        }
        return 'Graded: ${assignment['marks']}';
      }
      return 'Submitted';
    }

    final dueDate = assignment['due_date'];
    if (dueDate != null && dueDate.isBefore(DateTime.now())) {
      return 'Overdue';
    }

    return 'Pending';
  }

  String _getAssignmentTypeIcon(String assignmentType) {
    switch (assignmentType) {
      case 'quiz':
        return '📝';
      case 'file':
        return '📎';
      default:
        return '📄';
    }
  }

  String _getAssignmentTypeText(String assignmentType) {
    switch (assignmentType) {
      case 'quiz':
        return 'Quiz';
      case 'file':
        return 'File';
      default:
        return 'Assignment';
    }
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar
        _buildDesktopSidebar(),
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
                    child: Text(
                      widget.studentName.isNotEmpty
                          ? widget.studentName[0].toUpperCase()
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
                    widget.studentName,
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
                  if (_studentClassId != null && _studentSection != null)
                    Text(
                      'Class: $_studentClassId - $_studentSection',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildSidebarInfo()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Assignments',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.assignment,
            'File Assignments',
            'Submit assignments by uploading files or providing text responses before the due date',
          ),
          _buildInfoItem(
            Icons.quiz,
            'Quiz Assignments',
            'Take interactive quizzes with multiple question types and get instant results',
          ),
          _buildInfoItem(
            Icons.visibility,
            'View Submissions',
            'Check your submitted work, grades, and teacher feedback',
          ),
          _buildInfoItem(
            Icons.track_changes,
            'Track Progress',
            'Monitor your assignment status and academic performance',
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
              'Stay on top of your academic work by regularly checking for new assignments and submitting them before the due dates to maintain good academic standing.',
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
              color: Color.fromARGB(255, 21, 101, 192),
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
            'My Assignments',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
          if (_assignments.isNotEmpty)
            Text(
              '${_assignments.length} assignments',
              style: const TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 24 : 16,
        vertical: _isDesktop ? 20 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Assignment Status Summary Card
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assignment Status',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildStatusSummary(),
                ],
              ),
            ),
          ),

          // Assignments List Section
          const SizedBox(height: 32),
          const Text(
            'All Assignments',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 105, 105, 105),
            ),
          ),
          const SizedBox(height: 16),
          _buildAssignmentsList(),
        ],
      ),
    );
  }

  Widget _buildStatusSummary() {
    if (_assignments.isEmpty) {
      return const Text(
        'No assignments available',
        style: TextStyle(color: Colors.grey),
      );
    }

    final pendingCount = _assignments
        .where((a) => a['has_submitted'] != true)
        .where(
          (a) =>
              a['due_date'] == null || !a['due_date']!.isBefore(DateTime.now()),
        )
        .length;

    final submittedCount = _assignments
        .where((a) => a['has_submitted'] == true)
        .length;

    final gradedCount = _assignments
        .where((a) => a['has_submitted'] == true && a['marks'] != null)
        .length;

    final overdueCount = _assignments
        .where(
          (a) =>
              a['has_submitted'] != true &&
              a['due_date'] != null &&
              a['due_date']!.isBefore(DateTime.now()),
        )
        .length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatusItem('Pending', pendingCount, Colors.orange),
        _buildStatusItem('Submitted', submittedCount, Colors.blue),
        _buildStatusItem('Graded', gradedCount, Colors.green),
        _buildStatusItem('Overdue', overdueCount, Colors.red),
      ],
    );
  }

  Widget _buildStatusItem(String title, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildAssignmentsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStudentInfo,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_assignments.isEmpty) {
      return const Center(
        child: Column(
          children: [
            Icon(Icons.assignment, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No assignments found',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Assignments will appear here when your teacher creates them',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _assignments.length,
      itemBuilder: (context, index) {
        final assignment = _assignments[index];
        final statusColor = _getStatusColor(assignment);
        final statusText = _getStatusText(assignment);
        final isOverdue =
            assignment['due_date'] != null &&
            assignment['due_date']!.isBefore(DateTime.now()) &&
            !assignment['has_submitted'];
        final assignmentType = assignment['assignment_type'] ?? 'file';
        final isQuiz = assignmentType == 'quiz';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: isQuiz ? Colors.purple[700] : statusColor,
              child: Text(
                _getAssignmentTypeIcon(assignmentType),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            title: Text(
              assignment['title'] ?? 'No Title',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Due: ${assignment['due_date'] != null ? DateFormat('MMM dd, yyyy').format(assignment['due_date']) : 'No due date'}',
                  style: TextStyle(
                    color: isOverdue ? Colors.red : Colors.grey[600],
                    fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                Text('Teacher: ${assignment['teacher_name']}'),
                Text(
                  'Type: ${_getAssignmentTypeText(assignmentType)}${isQuiz ? ' - ${assignment['total_marks']} marks' : ''}',
                ),
                if (assignment['marks'] != null)
                  Text(
                    isQuiz
                        ? 'Score: ${assignment['marks']}/${assignment['total_marks']}'
                        : 'Marks: ${assignment['marks']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                if (assignment['teacher_comments'] != null)
                  Text(
                    'Comments: ${assignment['teacher_comments']}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getAssignmentTypeText(assignmentType),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            onTap: () => _viewAssignmentDetails(assignment),
          ),
        );
      },
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Assignments'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadAssignments(),
        child: _buildMainContent(),
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
