import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'quiz_models.dart';
import 'teacher_assignments_screen.dart';

class TeacherQuizSubmissionsScreen extends StatefulWidget {
  final String assignmentId;
  final String userId;
  final String schoolName;
  final String schoolCode;
  final String assignmentTitle;
  final String classGrade;
  final String? section;

  const TeacherQuizSubmissionsScreen({
    super.key,
    required this.assignmentId,
    required this.userId,
    required this.schoolName,
    required this.schoolCode,
    required this.assignmentTitle,
    required this.classGrade,
    this.section,
  });

  @override
  State<TeacherQuizSubmissionsScreen> createState() =>
      _TeacherQuizSubmissionsScreenState();
}

class _TeacherQuizSubmissionsScreenState
    extends State<TeacherQuizSubmissionsScreen> {
  QuizAssignment? _assignment;
  List<StudentQuizSubmission> _submissions = [];
  bool _isLoading = true;
  String? _errorMessage;

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
    _loadAssignmentAndSubmissions();
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

  Future<void> _loadAssignmentAndSubmissions() async {
    try {
      // Load assignment
      final assignmentDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .get();

      if (assignmentDoc.exists) {
        setState(() {
          _assignment = QuizAssignment.fromMap({
            'id': assignmentDoc.id,
            ...assignmentDoc.data()!,
          });
        });
      } else {
        throw Exception('Assignment not found');
      }

      // Load submissions
      final submissionsSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('submissions')
          .get();

      setState(() {
        _submissions = submissionsSnapshot.docs
            .map(
              (doc) =>
                  StudentQuizSubmission.fromMap({'id': doc.id, ...doc.data()}),
            )
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading submissions: ${e.toString()}';
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to load submissions');
    }
  }

  void _showSubmissionDetails(StudentQuizSubmission submission) {
    if (_assignment == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeacherQuizSubmissionDetailScreen(
          assignment: _assignment!,
          submission: submission,
          schoolCode: widget.schoolCode,
          assignmentId: widget.assignmentId,
          onGradeUpdated: _onGradeUpdatedFromDetail,
        ),
      ),
    );
  }

  Future<void> _onGradeUpdatedFromDetail() async {
    // Refresh the submissions list when returning from detail screen
    await _loadAssignmentAndSubmissions();
    _showSuccessSnackbar('Grading updated successfully');
  }

  Future<void> _updateGrading(
    StudentQuizSubmission submission,
    int teacherGrade,
    String comments,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('submissions')
          .doc(submission.studentId)
          .update({
            'teacher_grade': teacherGrade,
            'teacher_comments': comments,
            'graded_at': Timestamp.now(),
          });

      await _loadAssignmentAndSubmissions();
    } catch (e) {
      _showErrorSnackbar('Error updating grade: ${e.toString()}');
      rethrow;
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
                    backgroundColor: Colors.green[100],
                    child: const Icon(
                      Icons.quiz,
                      size: 40,
                      color: Color.fromARGB(255, 0, 128, 0),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Quiz Submissions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromARGB(255, 0, 128, 0),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    widget.schoolCode,
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
    final gradedCount = _submissions
        .where((s) => s.teacherGrade != null)
        .length;
    final pendingCount = _submissions.length - gradedCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quiz Grading Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 0, 128, 0),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.assignment_turned_in,
            'Total Submissions',
            '${_submissions.length} students submitted',
          ),
          _buildInfoItem(
            Icons.grade,
            'Graded',
            '$gradedCount submissions reviewed',
          ),
          _buildInfoItem(
            Icons.pending_actions,
            'Pending',
            '$pendingCount awaiting review',
          ),
          _buildInfoItem(
            Icons.auto_awesome,
            'Auto-Grading',
            'Multiple choice and matching questions are auto-graded',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[100]!),
            ),
            child: const Text(
              'Review student submissions, provide final grades, and add comments for feedback. Auto-graded scores are provided as a reference.',
              style: TextStyle(fontSize: 12, color: Colors.green),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Grading Tips:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _buildTipItem('📝', 'Review auto-grading before final scoring'),
          _buildTipItem('💬', 'Provide constructive comments for improvement'),
          _buildTipItem('⚖️', 'Be consistent with grading across all students'),
          _buildTipItem('⏱️', 'Grade submissions in a timely manner'),
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
          Icon(icon, size: 20, color: Colors.green[700]),
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
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
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

  Widget _buildDesktopTopBar() {
    final gradedCount = _submissions
        .where((s) => s.teacherGrade != null)
        .length;

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
              color: Color.fromARGB(255, 0, 128, 0),
            ),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => TeacherAssignmentsScreen(
                    userId: widget.userId,
                    schoolCode: widget.schoolCode,
                    schoolName: widget.schoolName,
                    teacherId: widget.userId,
                    teacherName: widget.userId,
                  ),
                ),
                (route) => false,
              );
            },
            tooltip: 'Back to Dashboard',
          ),
          const Text(
            'Quiz Submissions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 0, 128, 0),
            ),
          ),
          const Spacer(),
          Text(
            '${gradedCount}/${_submissions.length} graded',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error loading submissions',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAssignmentAndSubmissions,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 24 : 16,
        vertical: _isDesktop ? 20 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Assignment Info Card
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
                  Text(
                    widget.assignmentTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _buildInfoChip(
                        Icons.class_,
                        '${widget.classGrade}${widget.section != null ? ' - ${widget.section}' : ''}',
                      ),
                      _buildInfoChip(
                        Icons.grade,
                        '${_assignment?.totalMarks ?? 0} marks',
                      ),
                      _buildInfoChip(
                        Icons.people,
                        '${_submissions.length} submissions',
                      ),
                      if (_assignment != null)
                        _buildInfoChip(
                          Icons.quiz,
                          _assignment!.questionType.replaceAll('_', ' '),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Submissions List
          if (_submissions.isNotEmpty) ...[
            const Text(
              'Student Submissions',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 105, 105, 105),
              ),
            ),
            const SizedBox(height: 16),
            _buildSubmissionsList(),
          ],

          if (_submissions.isEmpty && !_isLoading) ...[
            Center(
              child: Column(
                children: [
                  const Icon(Icons.assignment, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No submissions yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Students haven\'t submitted this quiz yet',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green[100]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.green[700]),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.green[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionsList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _submissions.length,
      itemBuilder: (context, index) {
        final submission = _submissions[index];
        final isGraded = submission.teacherGrade != null;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: isGraded ? Colors.green[100] : Colors.blue[100],
              child: Text(
                submission.studentName.isNotEmpty
                    ? submission.studentName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: isGraded ? Colors.green[700] : Colors.blue[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              submission.studentName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Submitted: ${DateFormat('MMM dd, yyyy HH:mm').format(submission.submittedAt)}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Auto Grade: ${submission.autoGrade}/${_assignment!.totalMarks}',
                  style: const TextStyle(fontSize: 14),
                ),
                if (submission.teacherGrade != null)
                  Text(
                    'Final Grade: ${submission.teacherGrade}/${_assignment!.totalMarks}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isGraded ? Colors.green : Colors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isGraded ? 'Graded' : 'Pending',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () => _showSubmissionDetails(submission),
          ),
        );
      },
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Submissions'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: _buildMainContent(),
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

/// Full screen for submission details and grading
class TeacherQuizSubmissionDetailScreen extends StatefulWidget {
  final QuizAssignment assignment;
  final StudentQuizSubmission submission;
  final String schoolCode;
  final String assignmentId;
  final VoidCallback onGradeUpdated;

  const TeacherQuizSubmissionDetailScreen({
    super.key,
    required this.assignment,
    required this.submission,
    required this.schoolCode,
    required this.assignmentId,
    required this.onGradeUpdated,
  });

  @override
  State<TeacherQuizSubmissionDetailScreen> createState() =>
      _TeacherQuizSubmissionDetailScreenState();
}

class _TeacherQuizSubmissionDetailScreenState
    extends State<TeacherQuizSubmissionDetailScreen> {
  final _gradeController = TextEditingController();
  final _commentsController = TextEditingController();
  final _scrollController = ScrollController();

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
    _gradeController.text = widget.submission.teacherGrade?.toString() ?? '';
    _commentsController.text = widget.submission.teacherComments ?? '';
  }

  @override
  void dispose() {
    _gradeController.dispose();
    _commentsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _updateGrading() async {
    try {
      final grade = int.tryParse(_gradeController.text) ?? 0;
      if (grade > widget.assignment.totalMarks) {
        _showErrorSnackbar(
          'Grade cannot exceed ${widget.assignment.totalMarks}',
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('submissions')
          .doc(widget.submission.studentId)
          .update({
            'teacher_grade': grade,
            'teacher_comments': _commentsController.text,
            'graded_at': Timestamp.now(),
          });

      widget.onGradeUpdated();
      Navigator.pop(context);
    } catch (e) {
      _showErrorSnackbar('Error updating grade: ${e.toString()}');
    }
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

  /// Resolve a single student match entry to an index in `question.pairs`.
  int? _resolveSingleMatch(MatchFollowingQuestion question, dynamic raw) {
    try {
      if (raw == null) return null;
      if (raw is int) {
        if (raw >= 0 && raw < question.pairs.length) return raw;
        return null;
      }
      if (raw is String) {
        // try numeric string first
        final parsed = int.tryParse(raw);
        if (parsed != null) {
          if (parsed >= 0 && parsed < question.pairs.length) return parsed;
        }
        // otherwise try matching right-side text exactly
        for (int i = 0; i < question.pairs.length; i++) {
          if (question.pairs[i].right == raw) return i;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Normalize any of the shapes we accept into a List<int?> of length == totalPairs
  List<int?> _normalizeMatchAnswer(
    MatchFollowingQuestion question,
    dynamic studentAnswer,
  ) {
    final total = question.pairs.length;
    final resolved = List<int?>.filled(total, null);

    if (studentAnswer == null) {
      return resolved;
    }

    // Case A: List-like (List<dynamic>) — assume ordered by left index
    if (studentAnswer is List) {
      for (int i = 0; i < total; i++) {
        final raw = (i < studentAnswer.length) ? studentAnswer[i] : null;
        resolved[i] = _resolveSingleMatch(question, raw);
      }
      return resolved;
    }

    // Case B: Map-like — keys may be left indices (int or numeric string) or left text.
    if (studentAnswer is Map) {
      studentAnswer.forEach((k, v) {
        int? leftIndex;
        // try parse key as int
        if (k is int) {
          leftIndex = k;
        } else if (k is String) {
          final pk = int.tryParse(k);
          if (pk != null)
            leftIndex = pk;
          else {
            // try match left-side text to find leftIndex
            for (int i = 0; i < total; i++) {
              if (question.pairs[i].left == k) {
                leftIndex = i;
                break;
              }
            }
          }
        }
        if (leftIndex != null && leftIndex >= 0 && leftIndex < total) {
          resolved[leftIndex] = _resolveSingleMatch(question, v);
        }
      });
      return resolved;
    }

    // Case C: Maybe it's a JSON-encoded string that represents list or map
    if (studentAnswer is String) {
      for (int i = 0; i < total; i++) {
        final maybe = _resolveSingleMatch(question, studentAnswer);
        if (maybe != null) {
          // assign to first unresolved left (best-effort)
          for (int j = 0; j < total; j++) {
            if (resolved[j] == null) {
              resolved[j] = maybe;
              break;
            }
          }
        }
      }
      return resolved;
    }

    // Fallback: unknown type => return all nulls
    return resolved;
  }

  Widget _buildMCQReview(
    MultipleChoiceQuestion question,
    dynamic studentAnswer,
    int index,
  ) {
    final isCorrect = studentAnswer == question.correctAnswerIndex;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isCorrect ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Q${index + 1}: ${question.questionText}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            ...question.options.asMap().entries.map((entry) {
              final optionIndex = entry.key;
              final option = entry.value;
              final isSelected = studentAnswer == optionIndex;
              final isRightAnswer = optionIndex == question.correctAnswerIndex;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected && isRightAnswer
                      ? Colors.green[100]
                      : isSelected
                      ? Colors.red[100]
                      : isRightAnswer
                      ? Colors.green[50]
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected || isRightAnswer
                        ? Colors.grey[400]!
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    if (isSelected)
                      Icon(
                        Icons.radio_button_checked,
                        size: 18,
                        color: isRightAnswer ? Colors.green : Colors.red,
                      )
                    else
                      const Icon(
                        Icons.radio_button_unchecked,
                        size: 18,
                        color: Colors.grey,
                      ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(option)),
                    if (isRightAnswer)
                      const Icon(Icons.check, size: 18, color: Colors.green),
                    if (isSelected && !isRightAnswer)
                      const Icon(Icons.close, size: 18, color: Colors.red),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 10),
            Text(
              'Marks: ${isCorrect ? question.marks : 0}/${question.marks}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isCorrect ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFillBlankReview(
    FillBlankQuestion question,
    dynamic studentAnswer,
    int index,
  ) {
    final studentAnswerText = studentAnswer?.toString() ?? '';
    final isCorrect =
        studentAnswerText.toLowerCase().trim() ==
        question.correctAnswer.toLowerCase().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isCorrect ? Colors.green[50] : Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Q${index + 1}: ${question.questionText}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Student Answer: $studentAnswerText',
                    style: TextStyle(
                      color: isCorrect ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Correct Answer: ${question.correctAnswer}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Marks: ${isCorrect ? question.marks : 0}/${question.marks}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isCorrect ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchReview(
    MatchFollowingQuestion question,
    dynamic studentAnswer,
    int index,
  ) {
    final resolvedList = _normalizeMatchAnswer(question, studentAnswer);
    final total = question.pairs.length;

    int correctMatches = 0;
    for (int i = 0; i < total; i++) {
      if (resolvedList[i] != null && resolvedList[i] == i) correctMatches++;
    }

    final awardAll = (correctMatches == total);
    final score = awardAll ? question.marks : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: awardAll ? Colors.green[50] : Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Q${index + 1}: ${question.questionText}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            ...question.pairs.asMap().entries.map((entry) {
              final leftIndex = entry.key;
              final pair = entry.value;
              final resolved = resolvedList[leftIndex];
              final isCorrect = (resolved != null && resolved == leftIndex);
              final displayedRight =
                  (resolved != null && resolved >= 0 && resolved < total)
                  ? question.pairs[resolved].right
                  : 'Not matched';

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCorrect ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        pair.left,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.arrow_forward,
                      color: Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        displayedRight,
                        style: TextStyle(
                          color: isCorrect ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isCorrect)
                      const Icon(Icons.check, size: 18, color: Colors.green)
                    else
                      const Icon(Icons.close, size: 18, color: Colors.red),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 10),
            Text(
              'Marks: ${score}/${question.marks}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: awardAll ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrueFalseReview(
    TrueFalseQuestion question,
    dynamic studentAnswer,
    int index,
  ) {
    final isCorrect = studentAnswer == question.correctAnswer;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isCorrect ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Q${index + 1}: ${question.questionText}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: studentAnswer == true
                          ? (question.correctAnswer == true
                              ? Colors.green[200]
                              : Colors.red[200])
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: question.correctAnswer == true
                          ? Border.all(color: Colors.green, width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: const Text('True',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: studentAnswer == false
                          ? (question.correctAnswer == false
                              ? Colors.green[200]
                              : Colors.red[200])
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: question.correctAnswer == false
                          ? Border.all(color: Colors.green, width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: const Text('False',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Marks: ${isCorrect ? question.marks : 0}/${question.marks}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isCorrect ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderingReview(
    OrderingQuestion question,
    dynamic studentAnswer,
    int index,
  ) {
    final userOrder =
        studentAnswer is List ? List<String>.from(studentAnswer) : null;
    bool isCorrect = false;
    if (userOrder != null && userOrder.length == question.correctOrder.length) {
      isCorrect = true;
      for (int i = 0; i < question.correctOrder.length; i++) {
        if (userOrder[i] != question.correctOrder[i]) {
          isCorrect = false;
          break;
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isCorrect ? Colors.green[50] : Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Q${index + 1}: ${question.questionText}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ordering / Sequencing',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (userOrder != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Student Order:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...userOrder.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    final correctItem = question.correctOrder[i];
                    final match = item == correctItem;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      decoration: BoxDecoration(
                        color: match ? Colors.green[100] : Colors.red[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Text('${i + 1}. $item'),
                          if (!match) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.arrow_right_alt,
                                size: 16, color: Colors.grey[700]),
                            const SizedBox(width: 8),
                            Text(correctItem,
                                style: TextStyle(
                                    color: Colors.green[800],
                                    fontWeight: FontWeight.bold)),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              )
            else
              const Text('No answer provided',
                  style: TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            Text(
              'Marks: ${isCorrect ? question.marks : 0}/${question.marks}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isCorrect ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionReview(
    Question question,
    dynamic studentAnswer,
    int index,
  ) {
    switch (question.type) {
      case 'multiple_choice':
        return _buildMCQReview(
          question as MultipleChoiceQuestion,
          studentAnswer,
          index,
        );
      case 'fill_blank':
        return _buildFillBlankReview(
          question as FillBlankQuestion,
          studentAnswer,
          index,
        );
      case 'match_following':
        return _buildMatchReview(
          question as MatchFollowingQuestion,
          studentAnswer,
          index,
        );
      case 'true_false':
        return _buildTrueFalseReview(
          question as TrueFalseQuestion,
          studentAnswer,
          index,
        );
      case 'ordering':
        return _buildOrderingReview(
          question as OrderingQuestion,
          studentAnswer,
          index,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Questions Review Section
        Expanded(flex: 2, child: _buildQuestionsReviewSection()),
        // Grading Section
        Expanded(flex: 1, child: _buildGradingSection()),
      ],
    );
  }

  Widget _buildQuestionsReviewSection() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Submission Review - ${widget.submission.studentName}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Student: ${widget.submission.studentName}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Submitted: ${DateFormat('MMM dd, yyyy HH:mm').format(widget.submission.submittedAt)}',
                          style: const TextStyle(fontSize: 14),
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
                      color: widget.submission.teacherGrade != null
                          ? Colors.green
                          : Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.submission.teacherGrade != null
                          ? 'Graded'
                          : 'Pending',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Auto Grade: ${widget.submission.autoGrade}/${widget.assignment.totalMarks}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 24),
          ...widget.assignment.questions.asMap().entries.map((entry) {
            final idx = entry.key;
            final question = entry.value;
            final studentAnswer = widget.submission.answers[question.id];
            return _buildQuestionReview(question, studentAnswer, idx);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildGradingSection() {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'Final Grading',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _gradeController,
            decoration: InputDecoration(
              labelText: 'Final Grade',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
              suffixText: '/${widget.assignment.totalMarks}',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentsController,
            decoration: const InputDecoration(
              labelText: 'Comments (Optional)',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
              alignLabelWithHint: true,
            ),
            maxLines: 4,
            textAlignVertical: TextAlignVertical.top,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _updateGrading,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Save Grading', style: TextStyle(fontSize: 16)),
            ),
          ),
          if (widget.submission.teacherGrade != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Already Graded',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Current Grade: ${widget.submission.teacherGrade}/${widget.assignment.totalMarks}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (widget.submission.teacherComments?.isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Previous Comments:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(widget.submission.teacherComments!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Submission - ${widget.submission.studentName}'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.quiz), text: 'Questions'),
              Tab(icon: Icon(Icons.grade), text: 'Grading'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Questions Tab
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            widget.submission.studentName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Text(
                                'Submitted: ${DateFormat('MMM dd, yyyy HH:mm').format(widget.submission.submittedAt)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.submission.teacherGrade != null
                                      ? Colors.green
                                      : Colors.blue,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  widget.submission.teacherGrade != null
                                      ? 'Graded'
                                      : 'Pending',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Auto Grade: ${widget.submission.autoGrade}/${widget.assignment.totalMarks}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...widget.assignment.questions.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final question = entry.value;
                    final studentAnswer =
                        widget.submission.answers[question.id];
                    return _buildQuestionReview(question, studentAnswer, idx);
                  }).toList(),
                ],
              ),
            ),
            // Grading Tab
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _gradeController,
                    decoration: InputDecoration(
                      labelText: 'Final Grade',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      suffixText: '/${widget.assignment.totalMarks}',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _commentsController,
                    decoration: const InputDecoration(
                      labelText: 'Comments (Optional)',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    textAlignVertical: TextAlignVertical.top,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _updateGrading,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Save Grading',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  if (widget.submission.teacherGrade != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.green[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Text(
                              'Already Graded',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Current Grade: ${widget.submission.teacherGrade}/${widget.assignment.totalMarks}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            if (widget.submission.teacherComments?.isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Previous Comments:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(widget.submission.teacherComments!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Submission - ${widget.submission.studentName}'),
      ),
      body: Row(
        children: [
          // Questions Review
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            widget.submission.studentName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Text(
                                'Submitted: ${DateFormat('MMM dd, yyyy HH:mm').format(widget.submission.submittedAt)}',
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.submission.teacherGrade != null
                                      ? Colors.green
                                      : Colors.blue,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  widget.submission.teacherGrade != null
                                      ? 'Graded'
                                      : 'Pending',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Auto Grade: ${widget.submission.autoGrade}/${widget.assignment.totalMarks}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...widget.assignment.questions.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final question = entry.value;
                    final studentAnswer =
                        widget.submission.answers[question.id];
                    return _buildQuestionReview(question, studentAnswer, idx);
                  }).toList(),
                ],
              ),
            ),
          ),
          // Grading Section
          Container(
            width: 300,
            color: Colors.grey[50],
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Final Grading',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _gradeController,
                  decoration: InputDecoration(
                    labelText: 'Final Grade',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    suffixText: '/${widget.assignment.totalMarks}',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TextField(
                    controller: _commentsController,
                    decoration: const InputDecoration(
                      labelText: 'Comments (Optional)',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      alignLabelWithHint: true,
                    ),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _updateGrading,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Save Grading'),
                  ),
                ),
              ],
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
    } else if (_isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildMobileLayout();
    }
  }
}
