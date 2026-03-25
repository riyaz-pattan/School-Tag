import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'student_assignments_screen.dart';

class StudentAssignmentSubmitScreen extends StatefulWidget {
  final String schoolName;
  final String userId;
  final String assignmentId;
  final String schoolCode;
  final String studentId;
  final String studentName;

  const StudentAssignmentSubmitScreen({
    super.key,
    required this.userId,
    required this.schoolName,
    required this.assignmentId,
    required this.schoolCode,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentAssignmentSubmitScreen> createState() =>
      _StudentAssignmentSubmitScreenState();
}

class _StudentAssignmentSubmitScreenState
    extends State<StudentAssignmentSubmitScreen> {
  Map<String, dynamic>? _assignment;
  Map<String, dynamic>? _submission;
  bool _isLoading = true;
  String? _errorMessage;
  PlatformFile? _selectedFile;
  bool _isSubmitting = false;
  final TextEditingController _textSubmissionController =
      TextEditingController();

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  @override
  void initState() {
    super.initState();
    _loadAssignmentAndSubmission();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  Future<void> _loadAssignmentAndSubmission() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Load assignment details
      final assignmentDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .get();

      if (assignmentDoc.exists) {
        final assignmentData = assignmentDoc.data();
        if (assignmentData != null && assignmentData['deleted'] != true) {
          setState(() {
            _assignment = assignmentData;
          });
        } else {
          setState(() {
            _errorMessage = 'Assignment not found or has been deleted';
            _isLoading = false;
          });
          _showErrorSnackbar('Assignment not found');
          return;
        }
      } else {
        setState(() {
          _errorMessage = 'Assignment not found';
          _isLoading = false;
        });
        _showErrorSnackbar('Assignment not found');
        return;
      }

      // Load student submission if exists
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
          _submission = submissionDoc.data();
          // FIXED: Don't pre-fill the text field with previous submission
          // This allows fresh input when resubmitting
          _textSubmissionController.text = '';
        });
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading assignment: ${e.toString()}';
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to load assignment');
    }
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

  Future<String?> _uploadFile(File file, String fileName) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(
        'schools/${widget.schoolCode}/assignments/${widget.assignmentId}/submissions/${widget.studentId}/$fileName',
      );

      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        final uploadTask = ref.putData(bytes);
        final snapshot = await uploadTask.whenComplete(() {});
        final downloadUrl = await snapshot.ref.getDownloadURL();
        return downloadUrl;
      } else {
        final uploadTask = ref.putFile(file);
        final snapshot = await uploadTask.whenComplete(() {});
        final downloadUrl = await snapshot.ref.getDownloadURL();
        return downloadUrl;
      }
    } catch (e) {
      _showErrorSnackbar('Error uploading file: ${e.toString()}');
      return null;
    }
  }

  Future<void> _submitAssignment() async {
    if (_selectedFile == null && _textSubmissionController.text.isEmpty) {
      _showErrorSnackbar(
        'Please either upload a file or write a text submission',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      String? fileUrl;
      String? fileName;

      if (_selectedFile != null) {
        if (kIsWeb) {
          final bytes = _selectedFile!.bytes;
          if (bytes != null) {
            fileName =
                '${DateTime.now().millisecondsSinceEpoch}_${_selectedFile!.name}';
            final ref = FirebaseStorage.instance.ref().child(
              'schools/${widget.schoolCode}/assignments/${widget.assignmentId}/submissions/${widget.studentId}/$fileName',
            );
            final uploadTask = ref.putData(bytes);
            final snapshot = await uploadTask.whenComplete(() {});
            fileUrl = await snapshot.ref.getDownloadURL();
          } else {
            throw Exception('File bytes are null');
          }
        } else {
          final file = File(_selectedFile!.path!);
          fileName =
              '${DateTime.now().millisecondsSinceEpoch}_${_selectedFile!.name}';
          fileUrl = await _uploadFile(file, fileName);
        }

        if (fileUrl == null) {
          setState(() {
            _isSubmitting = false;
          });
          return;
        }
      }

      final Map<String, dynamic> submissionData = {
        'student_id': widget.studentId,
        'student_name': widget.studentName,
        'submitted_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      };

      if (fileUrl != null) {
        submissionData['file_url'] = fileUrl;
      }
      if (fileName != null) {
        submissionData['file_name'] = fileName;
      } else if (_selectedFile?.name != null) {
        submissionData['file_name'] = _selectedFile!.name;
      }

      if (_textSubmissionController.text.isNotEmpty) {
        submissionData['submission_text'] = _textSubmissionController.text;
      }

      submissionData['marks'] = null;
      submissionData['teacher_comments'] = null;
      submissionData['graded_at'] = null;
      submissionData['teacher_grade'] = null;

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('submissions')
          .doc(widget.studentId)
          .set(submissionData);

      setState(() {
        _selectedFile = null;
        _textSubmissionController.clear();
        _isSubmitting = false;
      });

      _showSuccessSnackbar('Assignment submitted successfully!');
      await _loadAssignmentAndSubmission();
    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });
      _showErrorSnackbar('Error submitting assignment: ${e.toString()}');
    }
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
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'txt'],
      );
      if (result != null) {
        final file = result.files.first;
        final extension = file.extension?.toLowerCase();

        if (extension == null ||
            !['jpg', 'jpeg', 'png', 'pdf', 'txt'].contains(extension)) {
          _showErrorSnackbar(
            'File type not supported. Please select an image, PDF, or TXT file.',
          );
          return;
        }

        setState(() {
          _selectedFile = result.files.first;
        });
      }
    } catch (e) {
      _showErrorSnackbar('Error picking file: ${e.toString()}');
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
                    'Student',
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
            'Assignment Submission',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.upload_file,
            'File Upload',
            'Upload your assignment files in supported formats (PDF, Images, TXT)',
          ),
          _buildInfoItem(
            Icons.text_fields,
            'Text Submission',
            'Write your answers or notes directly in the text field',
          ),
          _buildInfoItem(
            Icons.schedule,
            'Due Date',
            'Make sure to submit before the due date to avoid late penalties',
          ),
          _buildInfoItem(
            Icons.visibility,
            'View Assignment',
            'Access assignment instructions and attached files anytime',
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
              'You can submit your assignment by uploading files or writing text. Make sure to review your work before submitting as you may need to resubmit if changes are required.',
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
                  builder: (context) => StudentAssignmentsScreen(
                    userId: widget.userId,
                    schoolCode: widget.schoolCode,
                    schoolName: widget
                        .schoolName, // You need to pass schoolName if available
                    studentId: widget.studentId,
                    studentName: widget.studentName,
                  ),
                ),
                (route) => false,
              );
            },
            tooltip: 'Back to My Assignments',
          ),
          const SizedBox(width: 16),
          Text(
            _assignment?['title'] ?? 'Assignment Submission',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
          if (_assignment?['due_date'] != null)
            Text(
              'Due: ${DateFormat('MMM dd, yyyy').format((_assignment!['due_date'] as Timestamp).toDate())}',
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

    if (_assignment == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Assignment not found',
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAssignmentAndSubmission,
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
          // Assignment Details Card
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
                    _assignment!['title'] ?? 'No Title',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_assignment!['description'] != null &&
                      _assignment!['description'].isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Description:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _assignment!['description'],
                          style: const TextStyle(fontSize: 16, height: 1.5),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _buildDetailItem(
                        Icons.person,
                        'Teacher: ${_assignment!['teacher_name'] ?? 'Unknown'}',
                      ),
                      _buildDetailItem(
                        Icons.class_,
                        'Class: ${_assignment!['grade'] ?? 'Unknown'}',
                      ),
                      if (_assignment!['section'] != null)
                        _buildDetailItem(
                          Icons.group,
                          'Section: ${_assignment!['section']}',
                        ),
                      if (_assignment!['due_date'] != null)
                        _buildDetailItem(
                          Icons.calendar_today,
                          'Due: ${DateFormat('MMM dd, yyyy').format((_assignment!['due_date'] as Timestamp).toDate())}',
                        ),
                    ],
                  ),

                  if (_assignment!['file_url'] != null) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _viewFile(
                        _assignment!['file_url'],
                        'Assignment File',
                      ),
                      icon: const Icon(Icons.visibility),
                      label: const Text('View Assignment File'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Submission Status Card
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
                    'Submission Status',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  if (_submission != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'Assignment Submitted',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Submitted on: ${DateFormat('MMM dd, yyyy HH:mm').format((_submission!['submitted_at'] as Timestamp).toDate())}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (_submission!['file_url'] != null) ...[
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => _viewFile(
                                _submission!['file_url'],
                                'Your Submission',
                              ),
                              icon: const Icon(Icons.visibility),
                              label: const Text('View Your Submission'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                          if (_submission!['submission_text'] != null &&
                              _submission!['submission_text'].isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Previous Text Submission:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _submission!['submission_text'],
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                          if (_submission!['marks'] != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Grading:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Marks: ${_submission!['marks']}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  if (_submission!['teacher_comments'] !=
                                      null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Comments: ${_submission!['teacher_comments']}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                  if (_submission!['graded_at'] != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Graded on: ${DateFormat('MMM dd, yyyy HH:mm').format((_submission!['graded_at'] as Timestamp).toDate())}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.pending_actions, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            'Assignment Not Submitted',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
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

          const SizedBox(height: 24),

          // Submission Form Card
          if (_submission == null || _submission!['marks'] == null)
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
                      _submission == null
                          ? 'Submit Your Work'
                          : 'Resubmit Your Work',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _textSubmissionController,
                      decoration: const InputDecoration(
                        labelText: 'Write your submission (optional)',
                        hintText: 'Type your answer or notes here...',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      maxLines: 5,
                      onChanged: (text) {
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _pickFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        _selectedFile == null
                            ? 'Upload File (optional)'
                            : 'Selected: ${_selectedFile!.name}',
                      ),
                    ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            (_selectedFile != null ||
                                    _textSubmissionController
                                        .text
                                        .isNotEmpty) &&
                                !_isSubmitting
                            ? _submitAssignment
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (_selectedFile != null ||
                                  _textSubmissionController.text.isNotEmpty)
                              ? Colors.green[700]
                              : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSubmitting
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Submitting...'),
                                ],
                              )
                            : Text(
                                _submission == null
                                    ? 'Submit Assignment'
                                    : 'Resubmit Assignment',
                                style: const TextStyle(fontSize: 16),
                              ),
                      ),
                    ),

                    if (_selectedFile == null &&
                        _textSubmissionController.text.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Please provide either a file upload or text submission',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_assignment?['title'] ?? 'Assignment Submission'),
        backgroundColor: Colors.blue[700],
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
