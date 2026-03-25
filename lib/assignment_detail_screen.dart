import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'view_assignment_screen.dart';
import 'assignment_submissions_screen.dart';

class AssignmentDetailScreen extends StatefulWidget {
  final String assignmentTitle;
  final String classGrade;
  final String userId;
  final String schoolName;
  final String assignmentId;
  final String schoolCode;
  final bool isTeacher;
  final String? studentId;
  final String? studentName;

  const AssignmentDetailScreen({
    super.key,
    required this.userId,
    required this.assignmentTitle,
    required this.classGrade,
    required this.schoolName,
    required this.assignmentId,
    required this.schoolCode,
    required this.isTeacher,
    this.studentId,
    this.studentName,
  });

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  Map<String, dynamic>? _assignment;
  List<Map<String, dynamic>> _submissions = [];
  Map<String, dynamic>? _studentSubmission;
  bool _isLoading = true;
  String? _errorMessage;
  PlatformFile? _selectedSubmissionFile;
  final _marksController = TextEditingController();
  final _feedbackController = TextEditingController();

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
    _loadAssignmentDetails();
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: _isDesktop ? 300 : 20,
          right: 20,
        ),
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
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: _isDesktop ? 300 : 20,
          right: 20,
        ),
      ),
    );
  }

  Future<void> _loadAssignmentDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final assignmentDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .get();

      if (assignmentDoc.exists) {
        setState(() {
          _assignment = assignmentDoc.data();
        });
      } else {
        throw Exception('Assignment not found');
      }

      if (widget.isTeacher) {
        final submissionsSnapshot = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('assignments')
            .doc(widget.assignmentId)
            .collection('submissions')
            .get();

        setState(() {
          _submissions = submissionsSnapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'student_id': doc.id,
              'file_url': data['file_url'],
              'submitted_at': (data['submitted_at'] as Timestamp?)?.toDate(),
              'marks': data['marks'],
              'feedback': data['feedback'],
              'teacher_comments': data['teacher_comments'],
              'student_name': data['student_name'] ?? 'Unknown Student',
              'submission_text': data['submission_text'],
            };
          }).toList();
        });
      } else {
        final submissionDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('assignments')
            .doc(widget.assignmentId)
            .collection('submissions')
            .doc(widget.studentId)
            .get();

        if (submissionDoc.exists) {
          setState(() {
            _studentSubmission = submissionDoc.data();
          });
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading details: ${e.toString()}';
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to load assignment details');
    }
  }

  Future<String?> _uploadSubmissionFile(PlatformFile platformFile) async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${platformFile.name}';
      final ref = FirebaseStorage.instance.ref().child(
        'schools/${widget.schoolCode}/assignments/${widget.assignmentId}/submissions/${widget.studentId}/$fileName',
      );

      if (kIsWeb) {
        if (platformFile.bytes != null) {
          final uploadTask = ref.putData(platformFile.bytes!);
          final snapshot = await uploadTask.whenComplete(() {});
          return await snapshot.ref.getDownloadURL();
        } else {
          throw Exception('File bytes are null');
        }
      } else {
        if (platformFile.bytes != null) {
          final uploadTask = ref.putData(platformFile.bytes!);
          final snapshot = await uploadTask.whenComplete(() {});
          return await snapshot.ref.getDownloadURL();
        } else {
          throw Exception('File bytes are null');
        }
      }
    } catch (e) {
      _showErrorSnackbar('Error uploading submission: ${e.toString()}');
      return null;
    }
  }

  Future<void> _submitAssignment() async {
    if (_selectedSubmissionFile == null) {
      _showErrorSnackbar('Please select a file to submit');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fileUrl = await _uploadSubmissionFile(_selectedSubmissionFile!);
      if (fileUrl == null) return;

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('submissions')
          .doc(widget.studentId)
          .set({
            'file_url': fileUrl,
            'submitted_at': Timestamp.now(),
            'student_name': widget.studentName,
            'file_name': _selectedSubmissionFile!.name,
          });

      setState(() {
        _selectedSubmissionFile = null;
        _isLoading = false;
      });

      _showSuccessSnackbar('Assignment submitted successfully!');
      _loadAssignmentDetails();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Error submitting assignment: ${e.toString()}');
    }
  }

  Future<void> _gradeSubmission(String studentId) async {
    final marks = _marksController.text;
    final feedback = _feedbackController.text;

    if (marks.isEmpty) {
      _showErrorSnackbar('Please enter marks');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('submissions')
          .doc(studentId)
          .update({
            'marks': int.tryParse(marks) ?? 0,
            'feedback': feedback,
            'teacher_comments': feedback,
            'graded_at': Timestamp.now(),
          });

      setState(() {
        _marksController.clear();
        _feedbackController.clear();
        _isLoading = false;
      });

      _showSuccessSnackbar('Submission graded successfully!');
      _loadAssignmentDetails();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Error grading submission: ${e.toString()}');
    }
  }

  void _viewSubmission(Map<String, dynamic> submission) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewAssignmentScreen(
          userId: widget.userId,
          assignmentTitle: widget.assignmentTitle,
          classGrade: widget.classGrade,
          schoolName: widget.schoolName,
          assignmentId: widget.assignmentId,
          schoolCode: widget.schoolCode,
          isTeacher: widget.isTeacher,
          studentId: submission['student_id'],
          studentName: submission['student_name'],
          submissionData: submission,
        ),
      ),
    ).then((_) => _loadAssignmentDetails());
  }

  void _viewFile(String url, String fileName) {
    showDialog(
      context: context,
      builder: (context) =>
          AdvancedFileViewerDialog(fileUrl: url, fileName: fileName),
    );
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'txt', 'doc', 'docx'],
      );
      if (result != null) {
        final file = result.files.first;
        final extension = file.extension?.toLowerCase();

        if (extension == null ||
            ![
              'jpg',
              'jpeg',
              'png',
              'pdf',
              'txt',
              'doc',
              'docx',
            ].contains(extension)) {
          _showErrorSnackbar(
            'File type not supported. Please select an image, PDF, or text file.',
          );
          return;
        }

        setState(() {
          _selectedSubmissionFile = result.files.first;
        });
      }
    } catch (e) {
      _showErrorSnackbar('Error picking file: ${e.toString()}');
    }
  }

  @override
  void dispose() {
    _marksController.dispose();
    _feedbackController.dispose();
    super.dispose();
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
    final submittedCount = _submissions.length;
    final gradedCount = _submissions.where((s) => s['marks'] != null).length;
    final pendingCount = submittedCount - gradedCount;

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
                    child: const Icon(
                      Icons.assignment,
                      size: 40,
                      color: Color.fromARGB(255, 21, 101, 192),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Assignment Details',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromARGB(255, 21, 101, 192),
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
            Expanded(
              child: _buildSidebarInfo(
                submittedCount,
                gradedCount,
                pendingCount,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarInfo(
    int submittedCount,
    int gradedCount,
    int pendingCount,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Assignment Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.isTeacher) ...[
            _buildInfoItem(
              Icons.people,
              'Total Submissions',
              '$submittedCount students submitted',
            ),
            _buildInfoItem(
              Icons.grade,
              'Graded',
              '$gradedCount submissions reviewed',
            ),
            _buildInfoItem(
              Icons.pending_actions,
              'Pending',
              '$pendingCount awaiting grading',
            ),
          ] else ...[
            _buildInfoItem(
              Icons.assignment_turned_in,
              'Your Status',
              _studentSubmission != null ? 'Submitted' : 'Not Submitted',
            ),
            if (_studentSubmission != null)
              _buildInfoItem(
                Icons.grade,
                'Grading Status',
                _studentSubmission!['marks'] != null
                    ? 'Graded'
                    : 'Pending Review',
              ),
          ],
          _buildInfoItem(
            Icons.calendar_today,
            'Due Date',
            _assignment?['due_date'] != null
                ? DateFormat(
                    'MMM dd, yyyy',
                  ).format((_assignment!['due_date'] as Timestamp).toDate())
                : 'No due date',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[100]!),
            ),
            child: Text(
              widget.isTeacher
                  ? 'Review student submissions, provide grades and feedback to help students improve their work.'
                  : 'Submit your assignment before the due date and check back for teacher feedback and grades.',
              style: const TextStyle(fontSize: 12, color: Colors.blue),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isTeacher ? 'Grading Tips:' : 'Submission Tips:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (widget.isTeacher) ...[
            _buildTipItem('⚖️', 'Be consistent with grading standards'),
            _buildTipItem('💬', 'Provide constructive feedback'),
            _buildTipItem('⏱️', 'Grade submissions promptly'),
            _buildTipItem('📊', 'Use rubrics for objective grading'),
          ] else ...[
            _buildTipItem('📁', 'Submit supported file types only'),
            _buildTipItem('⏰', 'Submit before the due date'),
            _buildTipItem('📝', 'Check assignment requirements carefully'),
            _buildTipItem('🔍', 'Review your work before submitting'),
          ],
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
                  builder: (context) => AssignmentSubmissionsScreen(
                    userId: widget.userId,
                    assignmentId: widget.assignmentId,
                    assignmentTitle: widget.assignmentTitle,
                    classGrade: widget.classGrade,
                    schoolCode: widget.schoolCode,
                    schoolName: widget.schoolName,
                  ),
                ),
                (route) => false,
              );
            },
            tooltip: 'Back to Dashboard',
          ),

          Text(
            widget.isTeacher ? 'Assignment Submissions' : 'Assignment Details',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
          if (_assignment != null)
            Text(
              'Due: ${_assignment!['due_date'] != null ? DateFormat('MMM dd, yyyy').format((_assignment!['due_date'] as Timestamp).toDate()) : 'No due date'}',
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
          // Assignment Information Card
          if (_assignment != null) ...[
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
                      _assignment!['title'] ?? 'Untitled Assignment',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_assignment!['description'] != null &&
                        _assignment!['description'].isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Description:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _assignment!['description'],
                            style: const TextStyle(fontSize: 16, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _buildInfoChip(
                          Icons.person,
                          'Teacher: ${_assignment!['teacher_name'] ?? 'Unknown'}',
                        ),
                        _buildInfoChip(
                          Icons.calendar_today,
                          'Due: ${_assignment!['due_date'] != null ? DateFormat('MMM dd, yyyy').format((_assignment!['due_date'] as Timestamp).toDate()) : 'No due date'}',
                        ),
                        if (_assignment!['assignment_type'] != null)
                          _buildInfoChip(
                            Icons.category,
                            'Type: ${_assignment!['assignment_type']}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_assignment!['file_url'] != null)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _viewFile(
                            _assignment!['file_url'],
                            'Assignment File',
                          ),
                          icon: const Icon(Icons.visibility),
                          label: const Text('View Assignment File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Teacher Section - Student Submissions
          if (widget.isTeacher) ..._buildTeacherSection(),

          // Student Section - Submission Status
          if (!widget.isTeacher) ..._buildStudentSection(),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.blue[700]),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTeacherSection() {
    return [
      const Text(
        'Student Submissions',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Color.fromARGB(255, 105, 105, 105),
        ),
      ),
      const SizedBox(height: 16),
      _submissions.isEmpty
          ? Center(
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
                    'Students haven\'t submitted this assignment yet',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : _buildSubmissionsList(),
    ];
  }

  List<Widget> _buildStudentSection() {
    return [
      const Text(
        'Your Submission',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Color.fromARGB(255, 105, 105, 105),
        ),
      ),
      const SizedBox(height: 16),
      if (_studentSubmission != null) ..._buildStudentSubmissionCard(),
      if (_studentSubmission == null) ..._buildSubmissionForm(),
    ];
  }

  List<Widget> _buildStudentSubmissionCard() {
    return [
      Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.assignment_turned_in, color: Colors.green),
                  const SizedBox(width: 8),
                  const Text(
                    'Assignment Submitted',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _studentSubmission!['marks'] != null
                          ? Colors.green
                          : Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _studentSubmission!['marks'] != null
                          ? 'Graded'
                          : 'Pending Review',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Submitted on: ${DateFormat('MMM dd, yyyy HH:mm').format((_studentSubmission!['submitted_at'] as Timestamp).toDate())}',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              if (_studentSubmission!['file_url'] != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _viewFile(
                      _studentSubmission!['file_url'],
                      'Your Submission',
                    ),
                    icon: const Icon(Icons.visibility),
                    label: const Text('View Your Submission'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              if (_studentSubmission!['marks'] != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Grading Results',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Marks: ${_studentSubmission!['marks']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_studentSubmission!['feedback'] != null ||
                            _studentSubmission!['teacher_comments'] !=
                                null) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Feedback:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _studentSubmission!['feedback'] ??
                                _studentSubmission!['teacher_comments'],
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                        if (_studentSubmission!['graded_at'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Graded on: ${DateFormat('MMM dd, yyyy HH:mm').format((_studentSubmission!['graded_at'] as Timestamp).toDate())}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildSubmissionForm() {
    return [
      Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Submit Your Assignment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select a file to submit:',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _selectedSubmissionFile == null
                        ? 'Choose File'
                        : 'Selected: ${_selectedSubmissionFile!.name}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Supported files: Images, PDF, Text, Word documents',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submitAssignment,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _isLoading ? 'Submitting...' : 'Submit Assignment',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLoading
                        ? Colors.grey
                        : Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildSubmissionsList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _submissions.length,
      itemBuilder: (context, index) {
        final submission = _submissions[index];
        final isGraded = submission['marks'] != null;

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
                submission['student_name'] != null &&
                        submission['student_name'].isNotEmpty
                    ? submission['student_name'][0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: isGraded ? Colors.green[700] : Colors.blue[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              submission['student_name'] ?? 'Unknown Student',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (submission['submitted_at'] != null)
                  Text(
                    'Submitted: ${DateFormat('MMM dd, yyyy HH:mm').format(submission['submitted_at'])}',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (submission['marks'] != null)
                  Text(
                    'Marks: ${submission['marks']}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (submission['file_url'] != null)
                  IconButton(
                    icon: const Icon(Icons.visibility, color: Colors.blue),
                    onPressed: () => _viewFile(
                      submission['file_url'],
                      'Submission from ${submission['student_name']}',
                    ),
                    tooltip: 'View Submission',
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
              ],
            ),
            onTap: () => _viewSubmission(submission),
          ),
        );
      },
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isTeacher ? 'Assignment Submissions' : 'Assignment Details',
        ),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildMainContent(),
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

class AdvancedFileViewerDialog extends StatelessWidget {
  final String fileUrl;
  final String fileName;

  const AdvancedFileViewerDialog({
    super.key,
    required this.fileUrl,
    required this.fileName,
  });

  Future<void> _launchFile() async {
    final Uri url = Uri.parse(fileUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      throw 'Could not launch $fileUrl';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fileName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'This file can be downloaded or opened in a browser.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _launchFile,
                  child: const Text('Open in Browser'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
