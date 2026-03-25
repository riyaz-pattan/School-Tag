import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:student_app/teacher_assignments_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'view_assignment_screen.dart';
import 'teacher_assignments_screen.dart';

class AssignmentSubmissionsScreen extends StatefulWidget {
  final String assignmentId;
  final String userId;
  final String schoolName;
  final String schoolCode;
  final String assignmentTitle;
  final String classGrade;
  final String? section;

  const AssignmentSubmissionsScreen({
    super.key,
    required this.userId,
    required this.schoolName,
    required this.assignmentId,
    required this.schoolCode,
    required this.assignmentTitle,
    required this.classGrade,
    this.section,
  });

  @override
  State<AssignmentSubmissionsScreen> createState() =>
      _AssignmentSubmissionsScreenState();
}

class _AssignmentSubmissionsScreenState
    extends State<AssignmentSubmissionsScreen> {
  List<Map<String, dynamic>> _submissions = [];
  bool _isLoading = false;
  String? _errorMessage;
  final Map<String, TextEditingController> _marksControllers = {};
  final Map<String, TextEditingController> _commentsControllers = {};

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
    _loadSubmissions();
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

  Future<void> _loadSubmissions() async {
    setState(() {
      _isLoading = true;
    });
    try {
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

          // Initialize controllers for each submission
          _marksControllers[doc.id] = TextEditingController(
            text: data['marks']?.toString() ?? '',
          );
          _commentsControllers[doc.id] = TextEditingController(
            text: data['teacher_comments'] ?? '',
          );

          return {
            'id': doc.id,
            'student_id': doc.id,
            'student_name': data['student_name'] ?? 'Unknown Student',
            'submitted_at': (data['submitted_at'] as Timestamp?)?.toDate(),
            'file_url': data['file_url'],
            'file_name': data['file_name'],
            'submission_text': data['submission_text'],
            'marks': data['marks'],
            'teacher_comments': data['teacher_comments'],
            'graded_at': (data['graded_at'] as Timestamp?)?.toDate(),
          };
        }).toList();
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

  Future<void> _updateMarks(String submissionId) async {
    final marks = _marksControllers[submissionId]?.text;
    final comments = _commentsControllers[submissionId]?.text;

    if (marks == null || marks.isEmpty) {
      _showErrorSnackbar('Please enter marks');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('submissions')
          .doc(submissionId)
          .update({
            'marks': int.tryParse(marks) ?? 0,
            'teacher_comments': comments,
            'graded_at': Timestamp.now(),
          });

      setState(() {
        _isLoading = false;
      });

      _showSuccessSnackbar('Marks updated successfully!');
      _loadSubmissions();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Error updating marks: ${e.toString()}');
    }
  }

  void _viewSubmission(Map<String, dynamic> submission) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewAssignmentScreen(
          assignmentId: widget.assignmentId,
          assignmentTitle: widget.assignmentTitle,
          classGrade: widget.classGrade,
          schoolName: widget.schoolName,
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          isTeacher: true,
          studentId: submission['id'],
          studentName: submission['student_name'],
          submissionData: submission,
        ),
      ),
    ).then((_) => _loadSubmissions());
  }

  void _viewFile(String url, String fileName) {
    showDialog(
      context: context,
      builder: (context) =>
          AdvancedFileViewerDialog(fileUrl: url, fileName: fileName),
    );
  }

  @override
  void dispose() {
    _marksControllers.forEach((key, controller) => controller.dispose());
    _commentsControllers.forEach((key, controller) => controller.dispose());
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
    final gradedCount = _submissions.where((s) => s['marks'] != null).length;
    final pendingCount = _submissions.length - gradedCount;

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
                      Icons.assignment_turned_in,
                      size: 40,
                      color: Color.fromARGB(255, 0, 128, 0),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Assignment Submissions',
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
            Expanded(child: _buildSidebarInfo(gradedCount, pendingCount)),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarInfo(int gradedCount, int pendingCount) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Submissions Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 0, 128, 0),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.people,
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
            '$pendingCount awaiting grading',
          ),
          _buildInfoItem(
            Icons.class_,
            'Class',
            '${widget.classGrade}${widget.section != null ? ' - ${widget.section}' : ''}',
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
              'Review student submissions, provide grades and constructive feedback to help students improve their work.',
              style: TextStyle(fontSize: 12, color: Colors.green),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Grading Tips:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _buildTipItem('⚖️', 'Be consistent with grading standards'),
          _buildTipItem('💬', 'Provide constructive feedback'),
          _buildTipItem('⏱️', 'Grade submissions promptly'),
          _buildTipItem('📊', 'Use clear grading criteria'),
          _buildTipItem('🔍', 'Review submissions thoroughly'),
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
    final gradedCount = _submissions.where((s) => s['marks'] != null).length;

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
          Text(
            widget.assignmentTitle,
            style: const TextStyle(
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
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildInfoChip(
                        Icons.class_,
                        '${widget.classGrade}${widget.section != null ? ' - ${widget.section}' : ''}',
                      ),
                      _buildInfoChip(
                        Icons.people,
                        '${_submissions.length} submissions',
                      ),
                      _buildInfoChip(Icons.assignment, 'File Assignment'),
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
                    'Students haven\'t submitted this assignment yet',
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
        final isGraded = submission['marks'] != null;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Student Info Row
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isGraded
                          ? Colors.green[100]
                          : Colors.blue[100],
                      child: Text(
                        submission['student_name'] != null &&
                                submission['student_name'].isNotEmpty
                            ? submission['student_name'][0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: isGraded
                              ? Colors.green[700]
                              : Colors.blue[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            submission['student_name'] ?? 'Unknown Student',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Submitted: ${DateFormat('MMM dd, yyyy HH:mm').format(submission['submitted_at'])}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
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

                const SizedBox(height: 12),

                // Submission Content
                if (submission['file_url'] != null ||
                    (submission['submission_text'] != null &&
                        submission['submission_text'].isNotEmpty))
                  Wrap(
                    spacing: 8,
                    children: [
                      if (submission['file_url'] != null)
                        ElevatedButton.icon(
                          onPressed: () => _viewFile(
                            submission['file_url'],
                            'Submission from ${submission['student_name']}',
                          ),
                          icon: const Icon(Icons.visibility, size: 16),
                          label: const Text('View File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[50],
                            foregroundColor: Colors.blue[700],
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                        ),
                      if (submission['submission_text'] != null &&
                          submission['submission_text'].isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange[100]!),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.text_fields,
                                size: 14,
                                color: Colors.orange,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Text Submission',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                // Grading Results (if graded)
                if (isGraded) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Grading Results',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Marks: ${submission['marks']}'),
                        if (submission['teacher_comments'] != null &&
                            submission['teacher_comments'].isNotEmpty)
                          Text('Comments: ${submission['teacher_comments']}'),
                      ],
                    ),
                  ),
                ],

                // Grading Form (if not graded)
                if (!isGraded) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text(
                    'Grade Submission',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _marksControllers[submission['id']],
                          decoration: const InputDecoration(
                            labelText: 'Marks',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _commentsControllers[submission['id']],
                          decoration: const InputDecoration(
                            labelText: 'Comments (Optional)',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _updateMarks(submission['id']),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.grade, size: 16),
                      label: Text(_isLoading ? 'Saving...' : 'Save Grade'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],

                // View Details Button
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _viewSubmission(submission),
                    icon: const Icon(Icons.visibility),
                    label: const Text('View Submission Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[700],
                      side: BorderSide(color: Colors.blue[700]!),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignment Submissions'),
        backgroundColor: Colors.green[700],
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

class AdvancedFileViewerDialog extends StatefulWidget {
  final String fileUrl;
  final String fileName;

  const AdvancedFileViewerDialog({
    super.key,
    required this.fileUrl,
    required this.fileName,
  });

  @override
  State<AdvancedFileViewerDialog> createState() =>
      _AdvancedFileViewerDialogState();
}

class _AdvancedFileViewerDialogState extends State<AdvancedFileViewerDialog> {
  bool _isExpanded = false;
  bool _isFileLoading = false;
  PdfController? _pdfController;
  late final String _fileType;
  String? _textContent;

  @override
  void initState() {
    super.initState();
    _fileType = _getFileType();
    _initializeViewer();
  }

  String _getFileType() {
    final url = widget.fileUrl.toLowerCase();
    if (url.contains('.pdf')) return 'PDF';
    if (url.contains('.jpg') || url.contains('.jpeg') || url.contains('.png'))
      return 'Image';
    if (url.contains('.txt')) return 'Text File';
    return 'Unsupported File';
  }

  Future<void> _initializeViewer() async {
    setState(() {
      _isFileLoading = true;
    });

    try {
      if (_fileType == 'PDF' && !kIsWeb) {
        // For mobile PDF viewer only
        _pdfController = PdfController(
          document: PdfDocument.openData(await _downloadFile(widget.fileUrl)),
        );
      } else if (_fileType == 'Text File' && !kIsWeb) {
        // For mobile text files only - load text content
        final bytes = await _downloadFile(widget.fileUrl);
        _textContent = String.fromCharCodes(bytes);
      }
    } catch (e) {
      print('Error loading file: $e');
    } finally {
      setState(() {
        _isFileLoading = false;
      });
    }
  }

  Future<Uint8List> _downloadFile(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('Failed to download file: ${response.statusCode}');
      }
    } catch (e) {
      print('Download error: $e');
      rethrow;
    }
  }

  // Method to open URL in browser (for web)
  Future<void> _openInBrowser() async {
    try {
      final uri = Uri.parse(widget.fileUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showError('Could not open the file in browser');
      }
    } catch (e) {
      _showError('Error opening file: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _buildMobileFileContent() {
    if (_fileType == 'Image') {
      return Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.1,
              maxScale: 5.0,
              child: Image.network(
                widget.fileUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultView();
                },
              ),
            ),
          ),
        ],
      );
    } else if (_fileType == 'PDF' && _pdfController != null) {
      return Column(
        children: [
          Expanded(
            child: PdfView(
              controller: _pdfController!,
              scrollDirection: Axis.vertical,
            ),
          ),
        ],
      );
    } else if (_fileType == 'Text File' && _textContent != null) {
      return Column(children: [Expanded(child: _buildTextView())]);
    } else {
      return _buildUnsupportedView();
    }
  }

  Widget _buildWebFileContent() {
    // For web, always show the file type information and browser option
    return _buildWebFileOptions();
  }

  Widget _buildWebFileOptions() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_getFileIcon(), size: 80, color: _getFileColor()),
            const SizedBox(height: 20),
            Text(
              '$_fileType File',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              widget.fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            _buildOpenInBrowserButton(),
            const SizedBox(height: 10),
            const Text(
              'The file will open in a new browser tab',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenInBrowserButton() {
    return SizedBox(
      width: 250, // Fixed width to prevent stretching
      child: ElevatedButton.icon(
        onPressed: _openInBrowser,
        icon: const Icon(Icons.open_in_browser),
        label: const Text('Open File in Browser'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildTextView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: SelectableText(
          _textContent!,
          style: const TextStyle(fontSize: 16, fontFamily: 'Monospace'),
        ),
      ),
    );
  }

  Widget _buildUnsupportedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 80, color: Colors.orange[700]),
            const SizedBox(height: 20),
            const Text(
              'Unsupported File Type',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'This file type is not supported for preview.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 5),
            const Text(
              'Supported formats: PDF, Images (JPG, PNG), Text files',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_getFileIcon(), size: 80, color: _getFileColor()),
          const SizedBox(height: 20),
          Text(
            '$_fileType File',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              widget.fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon() {
    switch (_fileType) {
      case 'PDF':
        return Icons.picture_as_pdf;
      case 'Image':
        return Icons.image;
      case 'Text File':
        return Icons.text_snippet;
      default:
        return Icons.block;
    }
  }

  Color _getFileColor() {
    switch (_fileType) {
      case 'PDF':
        return Colors.red;
      case 'Image':
        return Colors.green;
      case 'Text File':
        return Colors.orange;
      default:
        return Colors.orange;
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width,
          maxHeight: _isExpanded
              ? MediaQuery.of(context).size.height * 0.9
              : MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[700],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fileType,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        if (_fileType == 'Unsupported File') ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Format not supported',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Full screen toggle for images and PDFs on mobile
                  if (!kIsWeb && (_fileType == 'Image' || _fileType == 'PDF'))
                    IconButton(
                      icon: Icon(
                        _isExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() => _isExpanded = !_isExpanded);
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _isFileLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading file...'),
                        ],
                      ),
                    )
                  : kIsWeb
                  ? _buildWebFileContent()
                  : _buildMobileFileContent(),
            ),
          ],
        ),
      ),
    );
  }
}
