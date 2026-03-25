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
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pdf/widgets.dart' as pw;
import 'assignment_submissions_screen.dart';
import 'teacher_create_quiz_screen.dart';
import 'teacher_quiz_submissions_screen.dart';
import 'view_assignment_screen.dart';
import 'teacher_dashboard_screen.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:pdf/pdf.dart';

class TeacherAssignmentsScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String teacherId;
  final String teacherName;

  const TeacherAssignmentsScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.teacherId,
    required this.teacherName,
  });

  @override
  State<TeacherAssignmentsScreen> createState() =>
      _TeacherAssignmentsScreenState();
}

class _TeacherAssignmentsScreenState extends State<TeacherAssignmentsScreen> {
  List<Map<String, dynamic>> _assignedClasses = [];
  Map<String, dynamic>? _selectedClass;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _dueDate;
  PlatformFile? _selectedFile;
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _assignments = [];
  String _assignmentType = 'file';

  // AI Assignment Variables
  final TextEditingController _aiPromptController = TextEditingController();
  List<Map<String, dynamic>> _teacherSubjects = [];
  Map<String, dynamic>? _selectedSubject;
  bool _isGeneratingAI = false;

  // Font cache for PDF generation
  pw.Font? _cachedEnglishFont;
  pw.Font? _cachedTeluguFont;
  pw.Font? _cachedHindiFont;
  bool _fontsLoaded = false;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // TODO: Add your Google Gemini API key here
  // Get your free API key from: https://aistudio.google.com/app/apikey
  static const String _geminiApiKey = 'AIzaSyA814r7S0eV2xx97LjWANdkjzf54_LUfAc';

  @override
  void initState() {
    super.initState();
    print(
      '🎯 TeacherAssignmentsScreen initialized for teacher: ${widget.teacherId}',
    );
    _loadAssignedClasses();
    _loadAssignments();
    _loadTeacherSubjects();
    _loadPdfFonts(); // Load fonts early
  }

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  // Load PDF fonts for multi-language support
  Future<void> _loadPdfFonts() async {
    try {
      // Load English font
      final englishFontData = await rootBundle.load(
        'assets/fonts/NotoSans-VariableFont_wdth,wght.ttf',
      );
      _cachedEnglishFont = pw.Font.ttf(englishFontData);

      // Load Telugu font
      try {
        final teluguFontData = await rootBundle.load(
          'assets/fonts/NotoSansTelugu-VariableFont_wdth,wght.ttf',
        );
        _cachedTeluguFont = pw.Font.ttf(teluguFontData);
      } catch (e) {
        print('Telugu font not found, using fallback: $e');
        _cachedTeluguFont = _cachedEnglishFont;
      }

      // Load Hindi font
      try {
        final hindiFontData = await rootBundle.load(
          'assets/fonts/NotoSans-VariableFont_wdth,wghth.ttf',
        );
        _cachedHindiFont = pw.Font.ttf(hindiFontData);
      } catch (e) {
        print('Hindi font not found, using fallback: $e');
        _cachedHindiFont = _cachedEnglishFont;
      }

      setState(() {
        _fontsLoaded = true;
      });
      print('✅ PDF fonts loaded successfully');
    } catch (e) {
      print('❌ Error loading PDF fonts: $e');
      // Fallback to default fonts
      _cachedEnglishFont = pw.Font.helvetica();
      _cachedTeluguFont = pw.Font.helvetica();
      _cachedHindiFont = pw.Font.helvetica();
      _fontsLoaded = true;
    }
  }

  // Helper method to detect language and choose appropriate font
  pw.Font _getFontForText(String text) {
    // Check for Telugu characters (Unicode range: 0C00-0C7F)
    if (text.contains(RegExp(r'[\u0C00-\u0C7F]'))) {
      return _cachedTeluguFont ?? _cachedEnglishFont!;
    }
    // Check for Hindi/Devanagari characters (Unicode range: 0900-097F)
    if (text.contains(RegExp(r'[\u0900-\u097F]'))) {
      return _cachedHindiFont ?? _cachedEnglishFont!;
    }
    // Default to English font
    return _cachedEnglishFont!;
  }

  Future<void> _loadAssignedClasses() async {
    print('🔄 FETCHING classes from Firestore');
    setState(() {
      _isLoading = true;
    });

    try {
      final timetablesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .get();

      List<Map<String, dynamic>> assignedClasses = [];

      for (var timetableDoc in timetablesSnapshot.docs) {
        final classDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('classes')
            .doc(timetableDoc.id)
            .get();

        if (!classDoc.exists) {
          continue;
        }

        final timetableData = timetableDoc.data();
        final timetable =
            timetableData?['timetable'] as Map<String, dynamic>? ?? {};
        final grade = timetableData?['grade'] ?? 'Unknown';
        final sections = List<String>.from(timetableData?['sections'] ?? []);

        bool isAssigned = false;

        timetable.forEach((day, periods) {
          for (var period in periods) {
            if (period['teacher_id'] == widget.teacherId) {
              isAssigned = true;
              return;
            }
          }
          if (isAssigned) return;
        });

        if (isAssigned) {
          if (sections.isEmpty) {
            assignedClasses.add({
              'id': timetableDoc.id,
              'grade': grade,
              'section': null,
              'displayName': grade,
            });
          } else {
            for (var section in sections) {
              assignedClasses.add({
                'id': timetableDoc.id,
                'grade': grade,
                'section': section,
                'displayName': '$grade - $section',
              });
            }
          }
        }
      }

      setState(() {
        _assignedClasses = assignedClasses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading assigned classes: ${e.toString()}';
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to load classes');
    }
  }

  Future<void> _loadTeacherSubjects() async {
    try {
      final subjectsSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('subjects')
          .where('teacher_ids', arrayContains: widget.teacherId)
          .get();

      setState(() {
        _teacherSubjects = subjectsSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'subject_id': data['subject_id'],
            'subject_name': data['subject_name'],
            'teacher_ids': List<String>.from(data['teacher_ids'] ?? []),
            'teacher_names': List<String>.from(data['teacher_names'] ?? []),
          };
        }).toList();
      });
    } catch (e) {
      print('Error loading teacher subjects: $e');
    }
  }

  Future<void> _loadAssignments() async {
    print('🔄 FETCHING assignments from Firestore');

    try {
      final assignmentsSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .where('teacher_id', isEqualTo: widget.teacherId)
          .where('deleted', isNotEqualTo: true)
          .orderBy('created_at', descending: true)
          .get();

      print(
        '📥 Fetched ${assignmentsSnapshot.docs.length} assignments from Firestore',
      );

      List<Map<String, dynamic>> assignments = [];

      // Create futures for all submission count queries
      final submissionCountFutures = <Future<QuerySnapshot>>[];
      final assignmentDocs = assignmentsSnapshot.docs;

      for (var doc in assignmentDocs) {
        final submissionFuture = FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('assignments')
            .doc(doc.id)
            .collection('submissions')
            .get();

        submissionCountFutures.add(submissionFuture);
      }

      print(
        '⏳ Waiting for ${submissionCountFutures.length} submission count queries...',
      );
      final submissionSnapshots = await Future.wait(submissionCountFutures);
      print('✅ All submission count queries completed');

      for (int i = 0; i < assignmentDocs.length; i++) {
        final doc = assignmentDocs[i];
        final data = doc.data() as Map<String, dynamic>;

        final submissionCount = submissionSnapshots[i].docs.length;

        assignments.add({
          'id': doc.id,
          'title': data['title'] ?? 'No Title',
          'description': data['description'] ?? 'No Description',
          'due_date': (data['due_date'] as Timestamp?)?.toDate(),
          'class_id': data['class_id'],
          'grade': data['grade'] ?? 'Unknown',
          'section': data['section'],
          'file_url': data['file_url'],
          'assignment_type': data['assignment_type'] ?? 'file',
          'question_type': data['question_type'],
          'total_marks': data['total_marks'] ?? 0,
          'created_at': (data['created_at'] as Timestamp?)?.toDate(),
          'total_students': data['total_students'] ?? 0,
          'submitted_count': submissionCount,
        });
      }

      setState(() {
        _assignments = assignments;
      });
    } catch (e) {
      print('❌ ERROR loading assignments: $e');
      setState(() {
        _errorMessage = 'Error loading assignments: ${e.toString()}';
      });
      _showErrorSnackbar('Failed to load assignments');
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: 20,
          left: _isDesktop ? 320 : 16,
          right: 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: 20,
          left: _isDesktop ? 320 : 16,
          right: 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Future<String?> _uploadFile(
    PlatformFile platformFile,
    String assignmentId,
  ) async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${platformFile.name}';
      final ref = FirebaseStorage.instance.ref().child(
        'schools/${widget.schoolCode}/assignments/$assignmentId/$fileName',
      );

      if (kIsWeb) {
        if (platformFile.bytes != null) {
          final uploadTask = ref.putData(platformFile.bytes!);
          final snapshot = await uploadTask;

          if (snapshot.state == TaskState.success) {
            final downloadUrl = await snapshot.ref.getDownloadURL();
            return downloadUrl;
          } else {
            throw Exception('Upload failed with state: ${snapshot.state}');
          }
        } else {
          throw Exception('File bytes are null');
        }
      } else {
        final file = File(platformFile.path!);
        final uploadTask = ref.putFile(file);
        final snapshot = await uploadTask;

        if (snapshot.state == TaskState.success) {
          final downloadUrl = await snapshot.ref.getDownloadURL();
          return downloadUrl;
        } else {
          throw Exception('Upload failed with state: ${snapshot.state}');
        }
      }
    } catch (e) {
      _showErrorSnackbar('Error uploading file: ${e.toString()}');
      return null;
    }
  }

  Future<void> _createFileAssignment() async {
    if (_titleController.text.isEmpty ||
        _dueDate == null ||
        _selectedClass == null) {
      _showErrorSnackbar('Please fill all required fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get the count of students in this class-section
      Query studentsQuery = FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .where('class_id', isEqualTo: _selectedClass!['id']);

      if (_selectedClass!['section'] != null) {
        studentsQuery = studentsQuery.where(
          'section',
          isEqualTo: _selectedClass!['section'],
        );
      }

      final studentsSnapshot = await studentsQuery.get();
      final totalStudents = studentsSnapshot.docs.length;

      final assignmentRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc();

      String? fileUrl;
      if (_selectedFile != null) {
        fileUrl = await _uploadFile(_selectedFile!, assignmentRef.id);
        if (fileUrl == null) {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      await assignmentRef.set({
        'title': _titleController.text,
        'description': _descriptionController.text,
        'due_date': Timestamp.fromDate(_dueDate!),
        'class_id': _selectedClass!['id'],
        'grade': _selectedClass!['grade'],
        'section': _selectedClass!['section'],
        'teacher_id': widget.teacherId,
        'teacher_name': widget.teacherName,
        'file_url': fileUrl,
        'assignment_type': 'file',
        'created_at': Timestamp.now(),
        'total_students': totalStudents,
        'submitted_count': 0,
        'deleted': false,
      });

      setState(() {
        _titleController.clear();
        _descriptionController.clear();
        _dueDate = null;
        _selectedFile = null;
        _selectedClass = null;
        _isLoading = false;
      });

      _showSuccessSnackbar('Assignment created successfully!');
      _loadAssignments();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Error creating assignment: ${e.toString()}');
    }
  }

  // AI Assignment Generation
  Future<void> _generateAIAssignment() async {
    if (_selectedClass == null) {
      _showErrorSnackbar('Please select a class first');
      return;
    }

    if (_selectedSubject == null) {
      _showErrorSnackbar('Please select a subject');
      return;
    }

    if (_aiPromptController.text.isEmpty) {
      _showErrorSnackbar('Please enter assignment requirements');
      return;
    }

    if (_dueDate == null) {
      _showErrorSnackbar('Please select a due date');
      return;
    }

    // Wait for fonts to load
    if (!_fontsLoaded) {
      _showErrorSnackbar('Fonts are still loading, please wait a moment');
      return;
    }

    // Enhanced API key validation
    if (_geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE' ||
        _geminiApiKey.isEmpty ||
        _geminiApiKey.length < 20) {
      _showErrorSnackbar(
        'Gemini API key not configured. Please add your valid API key from https://aistudio.google.com/app/apikey',
      );
      return;
    }

    setState(() {
      _isGeneratingAI = true;
    });

    try {
      // Get the count of students in this class-section
      Query studentsQuery = FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .where('class_id', isEqualTo: _selectedClass!['id']);

      if (_selectedClass!['section'] != null) {
        studentsQuery = studentsQuery.where(
          'section',
          isEqualTo: _selectedClass!['section'],
        );
      }

      final studentsSnapshot = await studentsQuery.get();
      final totalStudents = studentsSnapshot.docs.length;

      // Generate assignment content using Gemini AI
      final assignmentContent = await _generateAssignmentWithGemini(
        _selectedSubject!['subject_name'],
        _aiPromptController.text,
      );

      // Create PDF from the generated content
      final pdfBytes = await _createAssignmentPDF(
        _selectedSubject!['subject_name'],
        assignmentContent,
      );

      // Upload PDF to Firebase Storage
      final assignmentRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc();

      final fileName =
          'AI_Assignment_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfRef = FirebaseStorage.instance.ref().child(
        'schools/${widget.schoolCode}/assignments/${assignmentRef.id}/$fileName',
      );

      final uploadTask = pdfRef.putData(pdfBytes);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Create assignment in Firestore
      await assignmentRef.set({
        'title':
            'AI Generated: ${_selectedSubject!['subject_name']} Assignment',
        'description':
            'AI Generated Assignment based on: ${_aiPromptController.text}',
        'due_date': Timestamp.fromDate(_dueDate!),
        'class_id': _selectedClass!['id'],
        'grade': _selectedClass!['grade'],
        'section': _selectedClass!['section'],
        'teacher_id': widget.teacherId,
        'teacher_name': widget.teacherName,
        'file_url': downloadUrl,
        'assignment_type': 'file',
        'created_at': Timestamp.now(),
        'total_students': totalStudents,
        'submitted_count': 0,
        'deleted': false,
        'ai_generated': true,
        'ai_prompt': _aiPromptController.text,
        'subject': _selectedSubject!['subject_name'],
      });

      setState(() {
        _aiPromptController.clear();
        _selectedSubject = null;
        _dueDate = null;
        _selectedClass = null;
        _isGeneratingAI = false;
      });

      _showSuccessSnackbar('AI Assignment generated and sent successfully!');
      _loadAssignments();
    } catch (e) {
      setState(() {
        _isGeneratingAI = false;
      });

      // Show detailed error
      String errorMessage = 'Failed to generate assignment';
      if (e.toString().contains('API key')) {
        errorMessage = 'Invalid API key. Please check your Gemini API key.';
      } else if (e.toString().contains('404')) {
        errorMessage =
            'API model not available. Please check if gemini-2.5-flash is available in your region.';
      } else if (e.toString().contains('quota')) {
        errorMessage = 'API quota exceeded. Try again later.';
      } else if (e.toString().contains('401')) {
        errorMessage = 'Unauthorized. Please check your API key.';
      } else if (e.toString().contains('MAX_TOKENS')) {
        errorMessage =
            'Assignment too long. Please try with simpler requirements.';
      } else {
        errorMessage = 'Error: ${e.toString()}';
      }

      _showErrorSnackbar(errorMessage);
    }
  }

  Future<void> _testGeminiAPI() async {
    if (_geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE' || _geminiApiKey.isEmpty) {
      _showErrorSnackbar('API key not configured');
      return;
    }

    setState(() {
      _isGeneratingAI = true;
    });

    try {
      // Test with gemini-2.5-flash
      final testUrl = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
      );

      final response = await http.post(
        testUrl,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': _geminiApiKey,
        },
        body: json.encode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      'Hello, say "API test successful" if you can read this.',
                },
              ],
            },
          ],
        }),
      );

      print('Test API Response: ${response.statusCode}');
      print('Test API Body: ${response.body}');

      if (response.statusCode == 200) {
        _showSuccessSnackbar(
          '✅ API key is working! Gemini 2.5 Flash is ready.',
        );
      } else {
        final errorData = json.decode(response.body);
        _showErrorSnackbar('API Error: ${errorData['error']?['message']}');
      }
    } catch (e) {
      _showErrorSnackbar('Test failed: $e');
    } finally {
      setState(() {
        _isGeneratingAI = false;
      });
    }
  }

  Future<String> _generateAssignmentWithGemini(
    String subject,
    String prompt,
  ) async {
    try {
      // Use gemini-2.5-flash model
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
      );

      final fullPrompt =
          """
Create a comprehensive educational assignment for $subject subject.

Teacher's specific requirements: $prompt

IMPORTANT INSTRUCTIONS:
1. Generate the assignment in PLAIN TEXT format only
2. Do NOT use any markdown, special formatting, or code blocks
3. Use simple text with clear sections
4. If generating in Telugu or Hindi, use proper Unicode characters
5. Keep the assignment concise but comprehensive (2-3 pages maximum)
6. Structure with clear headings and bullet points using regular characters

Please structure the assignment with:
1. A clear and engaging title
2. Learning objectives and goals  
3. Detailed instructions and guidelines
4. 5-8 main tasks, questions, or activities with appropriate difficulty level
5. Clear submission guidelines
6. Deadline information
7. Grading criteria or rubric (if applicable)

Make the assignment educational, engaging, age-appropriate, and aligned with curriculum standards.
Use simple text formatting with clear sections.
""";

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': _geminiApiKey,
        },
        body: json.encode({
          'contents': [
            {
              'parts': [
                {'text': fullPrompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.7,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 4096,
          },
          'safetySettings': [
            {
              'category': 'HARM_CATEGORY_HARASSMENT',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
            },
            {
              'category': 'HARM_CATEGORY_HATE_SPEECH',
              'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
            },
          ],
        }),
      );

      print('Gemini API Response Status: ${response.statusCode}');
      print('Gemini API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Enhanced response parsing
        if (data['candidates'] != null &&
            data['candidates'].isNotEmpty &&
            data['candidates'][0] != null) {
          final candidate = data['candidates'][0];

          // Check for MAX_TOKENS finish reason
          if (candidate['finishReason'] == 'MAX_TOKENS') {
            throw Exception(
              'MAX_TOKENS: Response too long. Please simplify your requirements.',
            );
          }

          if (candidate['content'] != null &&
              candidate['content']['parts'] != null &&
              candidate['content']['parts'].isNotEmpty &&
              candidate['content']['parts'][0]['text'] != null) {
            final generatedText = candidate['content']['parts'][0]['text'];
            print(
              'Successfully generated assignment content using gemini-2.5-flash',
            );
            return generatedText;
          }
        }
        throw Exception('Invalid response structure from Gemini API');
      } else {
        final errorData = json.decode(response.body);
        final errorMessage =
            errorData['error']?['message'] ?? 'Unknown API error';
        final errorCode = errorData['error']?['code'] ?? response.statusCode;

        throw Exception('API Error $errorCode: $errorMessage');
      }
    } catch (e) {
      print('Gemini API Exception: $e');
      rethrow;
    }
  }

  Future<Uint8List> _createAssignmentPDF(String subject, String content) async {
    final pdf = pw.Document();

    // Ensure fonts are loaded
    if (!_fontsLoaded || _cachedEnglishFont == null) {
      throw Exception('PDF fonts not loaded properly');
    }

    // Split content into pages if needed
    final pages = _splitContentIntoPages(content);

    for (int i = 0; i < pages.length; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header - Only on first page
                if (i == 0) ...[
                  pw.Header(
                    level: 0,
                    child: pw.Text(
                      'AI Generated Assignment - $subject',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        font: _cachedEnglishFont!,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                      font: _cachedEnglishFont!,
                    ),
                  ),
                  pw.Text(
                    'Teacher: ${widget.teacherName}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                      font: _cachedEnglishFont!,
                    ),
                  ),
                  pw.SizedBox(height: 25),
                ] else ...[
                  pw.Header(
                    level: 0,
                    child: pw.Text(
                      '$subject - Page ${i + 1}',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        font: _cachedEnglishFont!,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 20),
                ],

                // Content with dynamic font selection
                pw.Expanded(
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey600, width: 1),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8),
                      ),
                    ),
                    padding: const pw.EdgeInsets.all(20),
                    child: _buildMultilingualText(pages[i]),
                  ),
                ),

                // Footer - Only on last page
                if (i == pages.length - 1) ...[
                  pw.SizedBox(height: 20),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                    ),
                    child: pw.Text(
                      'This assignment was AI-generated to enhance learning. Review and modify as needed for your classroom context.',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontStyle: pw.FontStyle.italic,
                        color: PdfColors.grey600,
                        font: _cachedEnglishFont!,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );
    }

    return await pdf.save();
  }

  // Split content into multiple pages if too long
  List<String> _splitContentIntoPages(String content) {
    final lines = content.split('\n');
    final pages = <String>[];
    final currentPage = <String>[];
    int lineCount = 0;
    const int maxLinesPerPage = 40;

    for (final line in lines) {
      if (lineCount >= maxLinesPerPage && line.trim().isEmpty) {
        pages.add(currentPage.join('\n'));
        currentPage.clear();
        lineCount = 0;
      }
      currentPage.add(line);
      lineCount++;
    }

    if (currentPage.isNotEmpty) {
      pages.add(currentPage.join('\n'));
    }

    // If no pages were created (content was very short), return the original content
    return pages.isEmpty ? [content] : pages;
  }

  // Helper method to build multilingual text with proper fonts
  pw.Widget _buildMultilingualText(String content) {
    final paragraphs = content.split('\n\n');
    final widgets = <pw.Widget>[];

    for (final paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) continue;

      final lines = paragraph.split('\n');
      final paragraphWidgets = <pw.Widget>[];

      for (final line in lines) {
        if (line.trim().isEmpty) {
          paragraphWidgets.add(pw.SizedBox(height: 8));
          continue;
        }

        // Check if this line is a heading
        final bool isHeading =
            line.length < 60 ||
            line.toLowerCase().contains('title:') ||
            line.toLowerCase().contains('objective') ||
            line.toLowerCase().contains('instruction') ||
            line.toLowerCase().contains('question') ||
            line.toLowerCase().contains('task') ||
            line.toLowerCase().contains('part');

        // Split the line into words to handle mixed language content
        final words = line.split(' ');
        final textSpans = <pw.TextSpan>[];
        pw.Font? currentFont;
        String currentText = '';

        for (final word in words) {
          final wordFont = _getFontForText(word);

          if (currentFont == null) {
            currentFont = wordFont;
            currentText = word;
          } else if (currentFont == wordFont) {
            currentText += ' $word';
          } else {
            // Font changed, add the current span
            textSpans.add(
              pw.TextSpan(
                text: currentText,
                style: pw.TextStyle(
                  fontSize: isHeading ? 14 : 12,
                  fontWeight: isHeading
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  lineSpacing: 1.5,
                  font: currentFont,
                ),
              ),
            );
            currentFont = wordFont;
            currentText = ' $word';
          }
        }

        // Add the last span
        if (currentText.isNotEmpty && currentFont != null) {
          textSpans.add(
            pw.TextSpan(
              text: currentText,
              style: pw.TextStyle(
                fontSize: isHeading ? 14 : 12,
                fontWeight: isHeading
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                lineSpacing: 1.5,
                font: currentFont,
              ),
            ),
          );
        }

        if (textSpans.isNotEmpty) {
          paragraphWidgets.add(
            pw.RichText(text: pw.TextSpan(children: textSpans)),
          );
        }
        paragraphWidgets.add(pw.SizedBox(height: 4));
      }

      widgets.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: paragraphWidgets,
        ),
      );
      widgets.add(pw.SizedBox(height: 12));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Future<void> _deleteAssignment(String assignmentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(assignmentId)
          .update({'deleted': true, 'deleted_at': Timestamp.now()});

      _showSuccessSnackbar('Assignment deleted successfully!');
      _loadAssignments();
    } catch (e) {
      _showErrorSnackbar('Error deleting assignment: ${e.toString()}');
    }
  }

  void _showDeleteConfirmation(String assignmentId, String assignmentTitle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Assignment'),
        content: Text(
          'Are you sure you want to delete "$assignmentTitle"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAssignment(assignmentId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _navigateToCreateQuiz() {
    if (_selectedClass == null) {
      _showErrorSnackbar('Please select a class first');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeacherCreateQuizScreen(
          userId: widget.userId,
          schoolName: widget.schoolName,
          schoolCode: widget.schoolCode,
          teacherId: widget.teacherId,
          teacherName: widget.teacherName,
          selectedClass: _selectedClass!,
        ),
      ),
    ).then((_) {
      _loadAssignments();
    });
  }

  void _viewSubmissions(Map<String, dynamic> assignment) {
    if (assignment['assignment_type'] == 'quiz') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TeacherQuizSubmissionsScreen(
            userId: widget.userId,
            schoolName: widget.schoolName,
            assignmentId: assignment['id'],
            schoolCode: widget.schoolCode,
            assignmentTitle: assignment['title'],
            classGrade: assignment['grade'],
            section: assignment['section'],
          ),
        ),
      ).then((_) => _loadAssignments());
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AssignmentSubmissionsScreen(
            userId: widget.userId,
            schoolName: widget.schoolName,
            assignmentId: assignment['id'],
            schoolCode: widget.schoolCode,
            assignmentTitle: assignment['title'],
            classGrade: assignment['grade'],
            section: assignment['section'],
          ),
        ),
      ).then((_) => _loadAssignments());
    }
  }

  void _viewFile(String url, String fileName) {
    showDialog(
      context: context,
      builder: (context) =>
          AdvancedFileViewerDialog(fileUrl: url, fileName: fileName),
    );
  }

  void _viewAssignmentDetails(Map<String, dynamic> assignment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewAssignmentScreen(
          userId: widget.userId,
          assignmentTitle: assignment['title'],
          classGrade: assignment['grade'],
          schoolName: widget.schoolName,
          assignmentId: assignment['id'],
          schoolCode: widget.schoolCode,
          isTeacher: true,
        ),
      ),
    ).then((_) => _loadAssignments());
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
          _selectedFile = file;
        });
      }
    } catch (e) {
      _showErrorSnackbar('Error picking file: ${e.toString()}');
    }
  }

  String _getAssignmentTypeIcon(String assignmentType) {
    switch (assignmentType) {
      case 'quiz':
        return '📝';
      case 'file':
        return '📎';
      case 'ai':
        return '🤖';
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
      case 'ai':
        return 'AI Generated';
      default:
        return 'Assignment';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _aiPromptController.dispose();
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
                      widget.teacherName.isNotEmpty
                          ? widget.teacherName[0].toUpperCase()
                          : 'T',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 22, 105, 200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.teacherName,
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
            'Assignments Management',
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
            'Create assignments with descriptions, due dates, and optional file attachments',
          ),
          _buildInfoItem(
            Icons.quiz,
            'Quiz Assignments',
            'Create interactive quizzes with multiple question types and auto-grading',
          ),
          _buildInfoItem(
            Icons.auto_awesome,
            'AI Assignments',
            'Generate assignments automatically using AI based on your subject and requirements',
          ),
          _buildInfoItem(
            Icons.visibility,
            'View Submissions',
            'Monitor student submissions and provide feedback',
          ),
          _buildInfoItem(
            Icons.analytics,
            'Track Progress',
            'View submission rates and student performance',
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
              'Create engaging assignments and quizzes to track student understanding and progress throughout the academic year.',
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
            'Assignments Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
          if (_assignedClasses.isNotEmpty)
            Text(
              '${_assignedClasses.length} assigned classes',
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
          // Create Assignment Section
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
                    'Create New Assignment',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Assignment Type Selection - Improved Layout
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assignment Type:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_isDesktop)
                        Row(
                          children: [
                            _buildAssignmentTypeChip(
                              'file',
                              'File Assignment',
                              Icons.assignment,
                            ),
                            const SizedBox(width: 12),
                            _buildAssignmentTypeChip(
                              'quiz',
                              'Quiz Assignment',
                              Icons.quiz,
                            ),
                            const SizedBox(width: 12),
                            _buildAssignmentTypeChip(
                              'ai',
                              'AI Assignment',
                              Icons.auto_awesome,
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            _buildAssignmentTypeChip(
                              'file',
                              'File Assignment',
                              Icons.assignment,
                            ),
                            const SizedBox(height: 8),
                            _buildAssignmentTypeChip(
                              'quiz',
                              'Quiz Assignment',
                              Icons.quiz,
                            ),
                            const SizedBox(height: 8),
                            _buildAssignmentTypeChip(
                              'ai',
                              'AI Assignment',
                              Icons.auto_awesome,
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<Map<String, dynamic>>(
                    decoration: const InputDecoration(
                      labelText: 'Select Class (Grade + Section)',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    value: _selectedClass,
                    items: _assignedClasses.map((cls) {
                      return DropdownMenuItem<Map<String, dynamic>>(
                        value: cls,
                        child: Text(cls['displayName'] ?? 'Unknown Class'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedClass = value;
                      });
                    },
                  ),

                  if (_assignmentType == 'file') ..._buildFileAssignmentForm(),
                  if (_assignmentType == 'quiz') ..._buildQuizAssignmentForm(),
                  if (_assignmentType == 'ai') ..._buildAIAssignmentForm(),
                ],
              ),
            ),
          ),

          // My Assignments Section
          const SizedBox(height: 32),
          const Text(
            'My Assignments',
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

  Widget _buildAssignmentTypeChip(String value, String label, IconData icon) {
    final isSelected = _assignmentType == value;
    final color = isSelected ? Colors.blue[700] : Colors.grey[400];

    return InkWell(
      onTap: () {
        setState(() {
          _assignmentType = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color!, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: _isMobile ? 14 : 16,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 14, color: color)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFileAssignmentForm() {
    return [
      const SizedBox(height: 16),
      TextField(
        controller: _titleController,
        decoration: const InputDecoration(
          labelText: 'Assignment Title *',
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _descriptionController,
        decoration: const InputDecoration(
          labelText: 'Description *',
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        maxLines: 3,
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  setState(() {
                    _dueDate = date;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _dueDate == null
                    ? 'Select Due Date *'
                    : 'Due: ${DateFormat('yyyy-MM-dd').format(_dueDate!)}',
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _pickFile,
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedFile == null
                    ? Colors.blue[700]
                    : Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _selectedFile == null
                    ? 'Upload File (Optional)'
                    : 'File: ${_selectedFile?.name ?? "Unknown"}',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _createFileAssignment,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isLoading ? Colors.grey : Colors.green[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isLoading
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
                    Text('Creating Assignment...'),
                  ],
                )
              : const Text(
                  'Create File Assignment',
                  style: TextStyle(fontSize: 16),
                ),
        ),
      ),
    ];
  }

  List<Widget> _buildQuizAssignmentForm() {
    return [
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _navigateToCreateQuiz,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text(
            'Create Quiz Assignment',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAIAssignmentForm() {
    return [
      const SizedBox(height: 16),

      // Subject Selection
      DropdownButtonFormField<Map<String, dynamic>>(
        decoration: const InputDecoration(
          labelText: 'Select Subject *',
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        value: _selectedSubject,
        items: _teacherSubjects.map((subject) {
          return DropdownMenuItem<Map<String, dynamic>>(
            value: subject,
            child: Text(subject['subject_name'] ?? 'Unknown Subject'),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedSubject = value;
          });
        },
      ),

      const SizedBox(height: 16),

      // Due Date Selection
      ElevatedButton(
        onPressed: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (date != null) {
            setState(() {
              _dueDate = date;
            });
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(
          _dueDate == null
              ? 'Select Due Date *'
              : 'Due: ${DateFormat('yyyy-MM-dd').format(_dueDate!)}',
        ),
      ),

      const SizedBox(height: 16),

      // AI Prompt
      TextField(
        controller: _aiPromptController,
        decoration: const InputDecoration(
          labelText: 'Assignment Requirements/Prompt *',
          hintText:
              'e.g., Create a math assignment about algebra for grade 10 with 5 problems of varying difficulty...',
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        maxLines: 4,
      ),

      const SizedBox(height: 16),

      // Generate Button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isGeneratingAI ? null : _generateAIAssignment,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isGeneratingAI ? Colors.grey : Colors.orange[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isGeneratingAI
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
                    Text('Generating AI Assignment...'),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome),
                    SizedBox(width: 8),
                    Text(
                      'Generate AI Assignment',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
        ),
      ),

      const SizedBox(height: 8),
      const Text(
        'The AI will generate a comprehensive assignment based on your subject and requirements, then automatically send it to all students in the selected class.',
        style: TextStyle(fontSize: 12, color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    ];
  }

  Widget _buildAssignmentsList() {
    if (_assignments.isEmpty) {
      return const Center(
        child: Column(
          children: [
            Icon(Icons.assignment, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No assignments created yet',
              style: TextStyle(fontSize: 16, color: Colors.grey),
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
        return _isMobile
            ? _buildMobileAssignmentItem(assignment)
            : _buildDesktopAssignmentItem(assignment);
      },
    );
  }

  Widget _buildDesktopAssignmentItem(Map<String, dynamic> assignment) {
    final isOverdue =
        assignment['due_date'] != null &&
        assignment['due_date']!.isBefore(DateTime.now());
    final submittedCount = assignment['submitted_count'] ?? 0;
    final totalStudents = assignment['total_students'] ?? 0;
    final assignmentType = assignment['assignment_type'] ?? 'file';
    final isQuiz = assignmentType == 'quiz';
    final isAI = assignment['ai_generated'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: isAI
              ? Colors.orange[700]
              : (isQuiz ? Colors.purple[700] : Colors.blue[700]),
          child: Text(
            isAI ? '🤖' : _getAssignmentTypeIcon(assignmentType),
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
            Text(
              'Class: ${assignment['grade'] ?? 'Unknown'}${assignment['section'] != null ? ' - ${assignment['section']}' : ''}',
            ),
            Text(
              'Type: ${isAI ? 'AI Generated' : _getAssignmentTypeText(assignmentType)}${isQuiz ? ' - ${assignment['total_marks'] ?? 0} marks' : ''}',
            ),
            if (isAI && assignment['subject'] != null)
              Text(
                'Subject: ${assignment['subject']}',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            Text(
              'Submissions: $submittedCount/$totalStudents',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // View Assignment File Button
            if (assignment['file_url'] != null)
              IconButton(
                icon: const Icon(Icons.visibility),
                onPressed: () =>
                    _viewFile(assignment['file_url']!, 'Assignment File'),
                tooltip: 'View Assignment File',
              ),
            // View Assignment Details Button
            IconButton(
              icon: const Icon(Icons.info),
              onPressed: () => _viewAssignmentDetails(assignment),
              tooltip: 'View Assignment Details',
            ),
            ElevatedButton(
              onPressed: () {
                _viewSubmissions(assignment);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isAI
                    ? Colors.orange[700]
                    : (isQuiz ? Colors.purple[700] : Colors.blue[700]),
                foregroundColor: Colors.white,
              ),
              child: Text(isQuiz ? 'View Results' : 'View Submissions'),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                _showDeleteConfirmation(
                  assignment['id']!,
                  assignment['title']!,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileAssignmentItem(Map<String, dynamic> assignment) {
    final isOverdue =
        assignment['due_date'] != null &&
        assignment['due_date']!.isBefore(DateTime.now());
    final submittedCount = assignment['submitted_count'] ?? 0;
    final totalStudents = assignment['total_students'] ?? 0;
    final assignmentType = assignment['assignment_type'] ?? 'file';
    final isQuiz = assignmentType == 'quiz';
    final isAI = assignment['ai_generated'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isAI
                      ? Color(0xFFFF9800)
                      : (isQuiz ? Color(0xFF7E57C2) : Color(0xFF1976D2)),
                  child: Icon(
                    isAI
                        ? Icons.auto_awesome
                        : (isQuiz ? Icons.quiz : Icons.assignment),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment['title'] ?? 'No Title',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${assignment['grade'] ?? 'Unknown'}${assignment['section'] != null ? ' - ${assignment['section']}' : ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Details Row - Compact layout for mobile
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildDetailChip(
                  Icons.calendar_today,
                  assignment['due_date'] != null
                      ? DateFormat('MMM dd').format(assignment['due_date'])
                      : 'No due date',
                  isOverdue ? Color(0xFFD32F2F) : Color(0xFF1976D2),
                ),
                _buildDetailChip(
                  isAI
                      ? Icons.auto_awesome
                      : (isQuiz ? Icons.quiz : Icons.assignment),
                  isAI ? 'AI' : _getAssignmentTypeText(assignmentType),
                  isAI
                      ? Color(0xFFFF9800)
                      : (isQuiz ? Color(0xFF7E57C2) : Color(0xFF1976D2)),
                ),
                if (isQuiz)
                  _buildDetailChip(
                    Icons.grade,
                    '${assignment['total_marks'] ?? 0} marks',
                    Color(0xFFF57C00),
                  ),
                if (isAI && assignment['subject'] != null)
                  _buildDetailChip(
                    Icons.subject,
                    assignment['subject'],
                    Color(0xFFFF9800),
                  ),
                _buildDetailChip(
                  Icons.people,
                  '$submittedCount/$totalStudents',
                  submittedCount == totalStudents
                      ? Color(0xFF388E3C)
                      : Color(0xFF1976D2),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Action Buttons - Horizontal scroll for mobile
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (assignment['file_url'] != null)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        icon: Icon(
                          Icons.visibility,
                          size: 20,
                          color: Color(0xFF1976D2),
                        ),
                        onPressed: () => _viewFile(
                          assignment['file_url']!,
                          'Assignment File',
                        ),
                        tooltip: 'View File',
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      icon: Icon(
                        Icons.info,
                        size: 20,
                        color: Color(0xFF1976D2),
                      ),
                      onPressed: () => _viewAssignmentDetails(assignment),
                      tooltip: 'Details',
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      onPressed: () {
                        _viewSubmissions(assignment);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAI
                            ? Color(0xFFFF9800)
                            : (isQuiz ? Color(0xFF7E57C2) : Color(0xFF1976D2)),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        isQuiz ? 'Results' : 'Submissions',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    child: IconButton(
                      icon: Icon(
                        Icons.delete,
                        size: 20,
                        color: Color(0xFFD32F2F),
                      ),
                      onPressed: () {
                        _showDeleteConfirmation(
                          assignment['id']!,
                          assignment['title']!,
                        );
                      },
                      tooltip: 'Delete',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignments'),
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
  pdfx.PdfController? _pdfController;
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
        _pdfController = pdfx.PdfController(
          document: pdfx.PdfDocument.openData(
            await _downloadFile(widget.fileUrl),
          ),
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
            child: pdfx.PdfView(
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
