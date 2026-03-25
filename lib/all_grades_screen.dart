import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'admin_dashboard_screen.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:universal_html/html.dart' as html;
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class AllGradesScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;

  const AllGradesScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<AllGradesScreen> createState() => _AllGradesScreenState();
}

class _AllGradesScreenState extends State<AllGradesScreen> {
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  List<Map<String, dynamic>> _grades = [];

  String? _selectedExamId;
  String? _selectedClassId;
  String? _selectedSubjectId;
  String _searchQuery = '';
  String _statusFilter = 'all';

  bool _isLoading = true;
  bool _loadingGrades = false;
  bool _exportingPdf = false;
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

  // Sidebar info page controller
  final PageController _infoPageController = PageController();
  int _currentInfoPage = 0;

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _infoPageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      await Future.wait([_loadExams(), _loadClasses(), _loadSubjects()]);
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

  // Cache utility methods
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
      final cachedData = prefs.getString('${key}_${widget.schoolCode}');
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
        '${key}_${widget.schoolCode}',
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
      // Reset all selections and data
      _selectedExamId = null;
      _selectedClassId = null;
      _selectedSubjectId = null;
      _students.clear();
      _filteredStudents.clear();
      _grades.clear();
      _searchQuery = '';
      _statusFilter = 'all';
    });

    // Clear cache to force refresh
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('exams_${widget.schoolCode}');
    await prefs.remove('classes_${widget.schoolCode}');
    await prefs.remove('subjects_${widget.schoolCode}');

    // Also clear student and grade caches
    final keys = await prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('students_') && key.contains(widget.schoolCode)) {
        await prefs.remove(key);
      }
      if (key.startsWith('grades_') && key.contains(widget.schoolCode)) {
        await prefs.remove(key);
      }
    }

    await _loadInitialData();
  }

  Future<void> _loadExams() async {
    // Try to load from cache first
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

    // Fetch from Firestore if cache is invalid
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exams')
          .orderBy('created_at', descending: true)
          .get();

      final exams = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'exam_name': data['exam_name'],
          'subjects_marks': List<Map<String, dynamic>>.from(
            data['subjects_marks'] ?? [],
          ),
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
    // Try to load from cache first
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
    // Try to load from cache first
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

  Future<void> _loadStudents() async {
    if (_selectedClassId == null) return;

    // Try to load students from cache for this class
    final cachedData = await _loadCachedData('students_${_selectedClassId}');
    if (cachedData != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (_isCacheValid(timestamp)) {
        final cachedStudents = (cachedData['data'] as List)
            .map((item) => _convertFromCacheSafe(item))
            .toList();
        setState(() {
          _students = List<Map<String, dynamic>>.from(cachedStudents);
          _sortStudentsByRollNumber();
          _filteredStudents = List.from(_students);
        });
        return;
      }
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .where('class_id', isEqualTo: _selectedClassId)
          .get();

      final students = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'username': data['username'],
          'full_name': data['full_name'],
          'section': data['section'],
          'roll_number': data['roll_number'],
        };
      }).toList();

      await _saveToCache('students_${_selectedClassId}', students);

      setState(() {
        _students = students;
        _sortStudentsByRollNumber();
        _filteredStudents = List.from(_students);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading students: $e';
      });
    }
  }

  // New method to sort students by roll number in ascending order
  void _sortStudentsByRollNumber() {
    _students.sort((a, b) {
      final rollA = a['roll_number']?.toString() ?? '';
      final rollB = b['roll_number']?.toString() ?? '';

      // Try to parse as numbers for natural sorting
      final numA = int.tryParse(rollA);
      final numB = int.tryParse(rollB);

      if (numA != null && numB != null) {
        return numA.compareTo(numB);
      } else {
        // Fallback to string comparison if not numbers
        return rollA.compareTo(rollB);
      }
    });
  }

  Future<void> _loadGrades() async {
    if (_selectedExamId == null || _selectedSubjectId == null) return;

    setState(() {
      _loadingGrades = true;
    });

    // Try to load grades from cache for this exam and subject
    final cachedData = await _loadCachedData(
      'grades_${_selectedExamId}_${_selectedSubjectId}',
    );
    if (cachedData != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (_isCacheValid(timestamp)) {
        final cachedGrades = (cachedData['data'] as List)
            .map((item) => _convertFromCacheSafe(item))
            .toList();
        setState(() {
          _grades = List<Map<String, dynamic>>.from(cachedGrades);
          _loadingGrades = false;
        });
        return;
      }
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('grades')
          .where('exam_id', isEqualTo: _selectedExamId)
          .where('subject_id', isEqualTo: _selectedSubjectId)
          .get();

      final grades = snapshot.docs.map((doc) {
        return doc.data();
      }).toList();

      await _saveToCache(
        'grades_${_selectedExamId}_${_selectedSubjectId}',
        grades,
      );

      setState(() {
        _grades = grades;
        _loadingGrades = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading grades: $e';
        _loadingGrades = false;
      });
    }
  }

  String _getClassName(String grade, List<dynamic> sections) {
    if (sections.isEmpty) return 'Grade $grade';
    return 'Grade $grade (${sections.join(', ')})';
  }

  void _onExamChanged(String? examId) {
    setState(() {
      _selectedExamId = examId;
      _selectedSubjectId = null; // Reset subject when exam changes
      _grades.clear();
    });
  }

  void _onClassChanged(String? classId) {
    setState(() {
      _selectedClassId = classId;
      _students.clear();
      _filteredStudents.clear();
      _grades.clear();
    });
    if (classId != null) {
      _loadStudents();
    }
  }

  void _onSubjectChanged(String? subjectId) {
    setState(() {
      _selectedSubjectId = subjectId;
      _grades.clear();
    });
    if (subjectId != null) {
      _loadGrades();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  void _onStatusFilterChanged(String status) {
    setState(() {
      _statusFilter = status;
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_students);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((student) {
        final username = student['username']?.toString().toLowerCase() ?? '';
        final fullName = student['full_name']?.toString().toLowerCase() ?? '';
        final rollNumber =
            student['roll_number']?.toString().toLowerCase() ?? '';
        return username.contains(_searchQuery.toLowerCase()) ||
            fullName.contains(_searchQuery.toLowerCase()) ||
            rollNumber.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Apply status filter if grades are loaded
    if (_statusFilter != 'all' && _grades.isNotEmpty) {
      filtered = filtered.where((student) {
        final studentGrade = _grades.firstWhere(
          (grade) => grade['student_id'] == student['id'],
          orElse: () => {},
        );

        if (studentGrade.isEmpty) return _statusFilter == 'pending';

        final isAbsent = studentGrade['is_absent'] == true;
        if (isAbsent) return _statusFilter == 'absent';

        final marksObtained = _safeParseInt(studentGrade['marks_obtained']);
        final subjectDetails = _getCurrentSubjectDetails();
        final passMarks = _safeParseInt(subjectDetails?['pass_marks']);
        final isPass = marksObtained >= passMarks;

        if (_statusFilter == 'pass') return isPass;
        if (_statusFilter == 'fail') return !isPass && !isAbsent;
        if (_statusFilter == 'absent') return isAbsent;
        if (_statusFilter == 'pending') return false;

        return true;
      }).toList();
    }

    setState(() {
      _filteredStudents = filtered;
    });
  }

  Map<String, dynamic>? _getCurrentSubjectDetails() {
    if (_selectedExamId == null) return null;

    final exam = _exams.firstWhere(
      (exam) => exam['id'] == _selectedExamId,
      orElse: () => {},
    );

    if (exam.isEmpty) return null;

    final subjectsMarks = List<Map<String, dynamic>>.from(
      exam['subjects_marks'] ?? [],
    );

    return subjectsMarks.firstWhere(
      (subject) => subject['subject_id'] == _selectedSubjectId,
      orElse: () => {},
    );
  }

  int _safeParseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }

  // PDF Export functionality - FIXED VERSION
  Future<void> _exportToPdf() async {
    if (_selectedExamId == null ||
        _selectedClassId == null ||
        _selectedSubjectId == null) {
      setState(() {
        _errorMessage = 'Please select exam, class, and subject first';
      });
      return;
    }

    if (_students.isEmpty) {
      setState(() {
        _errorMessage = 'No students data available to export';
      });
      return;
    }

    setState(() {
      _exportingPdf = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Get current data for PDF
      final exam = _exams.firstWhere((e) => e['id'] == _selectedExamId);
      final classData = _classes.firstWhere((c) => c['id'] == _selectedClassId);
      final subject = _subjects.firstWhere(
        (s) => s['id'] == _selectedSubjectId,
      );
      final subjectDetails = _getCurrentSubjectDetails();

      // Create PDF document
      final pdf = pw.Document();

      // Add header with school info
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (context) =>
              _buildPdfHeader(exam, classData, subject, subjectDetails),
          build: (context) => [
            _buildPdfStatistics(),
            pw.SizedBox(height: 20),
            _buildPdfGradesTable(),
          ],
        ),
      );

      // Generate file name
      final fileName =
          '${exam['exam_name']}_${classData['className']}_${subject['subject_name']}_Grades.pdf'
              .replaceAll(' ', '_')
              .replaceAll('/', '_')
              .replaceAll('(', '')
              .replaceAll(')', '');

      // Get PDF bytes
      final pdfBytes = await pdf.save();

      // Use different methods for web vs mobile
      await _downloadPdf(pdfBytes, fileName);

      setState(() {
        _successMessage = 'PDF exported successfully!';
        _exportingPdf = false;
      });

      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _successMessage = null;
          });
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error exporting PDF: $e';
        _exportingPdf = false;
      });
    }
  }

  // Platform-specific PDF download
  Future<void> _downloadPdf(Uint8List pdfBytes, String fileName) async {
    // For web platform
    if (_isWebPlatform()) {
      _downloadPdfForWeb(pdfBytes, fileName);
    } else {
      // For mobile platforms - use file system
      await _downloadPdfForMobile(pdfBytes, fileName);
    }
  }

  bool _isWebPlatform() {
    return identical(0, 0.0); // Simple way to detect web platform
  }

  void _downloadPdfForWeb(Uint8List pdfBytes, String fileName) {
    // Create a blob and download link for web
    final blob = html.Blob([pdfBytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..download = fileName
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _downloadPdfForMobile(
    Uint8List pdfBytes,
    String fileName,
  ) async {
    try {
      // STEP 1: Request MANAGE_EXTERNAL_STORAGE (works on Android 11+)
      if (Platform.isAndroid) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }

        // Fallback to old storage permission if needed
        if (!status.isGranted) {
          status = await Permission.storage.status;
          if (!status.isGranted) {
            await Permission.storage.request();
          }
        }
      }

      // STEP 2: Save directly to PUBLIC Downloads folder (VISIBLE IN FILE MANAGER)
      Directory? downloadsDir;

      // Method 1: Standard Downloads path (works on 99% devices)
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          // Method 2: Fallback using path_provider
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            final downloadPath =
                '${externalDir.path.split('Android').first}Download';
            downloadsDir = Directory(downloadPath);
          }
        }
      }

      // Method 3: Final fallback (app documents - hidden)
      if (downloadsDir == null || !await downloadsDir.exists()) {
        final appDir = await getApplicationDocumentsDirectory();
        downloadsDir = Directory('${appDir.path}/Downloads');
      }

      // Create directory if not exists
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // Save file
      final file = File('${downloadsDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      // SUCCESS MESSAGE WITH PATH
      setState(() {
        _successMessage = 'PDF saved to Downloads!\n${file.path}';
      });

      // Refresh gallery so it appears immediately
      if (Platform.isAndroid) {
        await Process.run('am', [
          'broadcast',
          '-a',
          'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
          '-d',
          'file://${file.path}',
        ]);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save PDF: $e';
      });
      rethrow;
    }
  }

  pw.Widget _buildPdfHeader(
    Map<String, dynamic> exam,
    Map<String, dynamic> classData,
    Map<String, dynamic> subject,
    Map<String, dynamic>? subjectDetails,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue, width: 1),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Grade Report - ${widget.schoolName}',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Exam: ${exam['exam_name']}'),
                  pw.Text('Class: ${classData['className']}'),
                  pw.Text('Subject: ${subject['subject_name']}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Max Marks: ${subjectDetails?['max_marks'] ?? 'N/A'}',
                  ),
                  pw.Text(
                    'Pass Marks: ${subjectDetails?['pass_marks'] ?? 'N/A'}',
                  ),
                  pw.Text('Date: ${DateTime.now().toString().split(' ')[0]}'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfStatistics() {
    final totalStudents = _students.length;
    final gradedStudents = _grades.length;
    final pendingStudents = totalStudents - gradedStudents;

    final subjectDetails = _getCurrentSubjectDetails();
    final passMarks = _safeParseInt(subjectDetails?['pass_marks']);

    int passedStudents = 0;
    int failedStudents = 0;
    int absentStudents = 0;

    for (var student in _students) {
      final studentGrade = _grades.firstWhere(
        (grade) => grade['student_id'] == student['id'],
        orElse: () => {},
      );

      if (studentGrade.isNotEmpty) {
        final isAbsent = studentGrade['is_absent'] == true;
        if (isAbsent) {
          absentStudents++;
        } else {
          final marksObtained = _safeParseInt(studentGrade['marks_obtained']);
          if (marksObtained >= passMarks) {
            passedStudents++;
          } else {
            failedStudents++;
          }
        }
      }
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildPdfStatItem('Total', totalStudents.toString(), PdfColors.blue),
          _buildPdfStatItem(
            'Graded',
            gradedStudents.toString(),
            PdfColors.orange,
          ),
          _buildPdfStatItem(
            'Pending',
            pendingStudents.toString(),
            PdfColors.grey,
          ),
          _buildPdfStatItem(
            'Passed',
            passedStudents.toString(),
            PdfColors.green,
          ),
          _buildPdfStatItem('Failed', failedStudents.toString(), PdfColors.red),
          _buildPdfStatItem(
            'Absent',
            absentStudents.toString(),
            PdfColors.orange,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfStatItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColor(color.red, color.green, color.blue, 0.1),
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: color),
          ),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
      ],
    );
  }

  pw.Widget _buildPdfGradesTable() {
    final subjectDetails = _getCurrentSubjectDetails();
    final maxMarks = _safeParseInt(subjectDetails?['max_marks']);
    final passMarks = _safeParseInt(subjectDetails?['pass_marks']);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        // Header row - Removed Section column
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'Roll No',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'Student Name',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'Marks',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'Status',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
        // Data rows - Removed Section column
        for (var student in _students)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(student['roll_number']?.toString() ?? 'N/A'),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(_getStudentDisplayName(student)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(_getStudentMarks(student['id'])),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  _getStudentStatus(student['id'], passMarks),
                  style: pw.TextStyle(
                    color: _getStudentStatusColor(student['id'], passMarks),
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _getStudentDisplayName(Map<String, dynamic> student) {
    // Use full_name if available, otherwise fall back to username
    final fullName = student['full_name']?.toString().trim();
    final username = student['username']?.toString().trim();

    if (fullName != null && fullName.isNotEmpty) {
      return fullName;
    } else if (username != null && username.isNotEmpty) {
      return username;
    } else {
      return 'Unknown';
    }
  }

  String _getStudentMarks(String studentId) {
    final studentGrade = _grades.firstWhere(
      (grade) => grade['student_id'] == studentId,
      orElse: () => {},
    );

    if (studentGrade.isEmpty) return 'Not Graded';

    final isAbsent = studentGrade['is_absent'] == true;
    if (isAbsent) return 'ABSENT';

    final marksObtained = _safeParseInt(studentGrade['marks_obtained']);
    final subjectDetails = _getCurrentSubjectDetails();
    final maxMarks = _safeParseInt(subjectDetails?['max_marks']);

    return '$marksObtained/$maxMarks';
  }

  String _getStudentStatus(String studentId, int passMarks) {
    final studentGrade = _grades.firstWhere(
      (grade) => grade['student_id'] == studentId,
      orElse: () => {},
    );

    if (studentGrade.isEmpty) return 'PENDING';

    final isAbsent = studentGrade['is_absent'] == true;
    if (isAbsent) return 'ABSENT';

    final marksObtained = _safeParseInt(studentGrade['marks_obtained']);
    return marksObtained >= passMarks ? 'PASS' : 'FAIL';
  }

  PdfColor _getStudentStatusColor(String studentId, int passMarks) {
    final studentGrade = _grades.firstWhere(
      (grade) => grade['student_id'] == studentId,
      orElse: () => {},
    );

    if (studentGrade.isEmpty) return PdfColors.orange;

    final isAbsent = studentGrade['is_absent'] == true;
    if (isAbsent) return PdfColors.orange;

    final marksObtained = _safeParseInt(studentGrade['marks_obtained']);
    return marksObtained >= passMarks ? PdfColors.green : PdfColors.red;
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
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.filter_alt,
            'Select Filters',
            'Choose Exam, Class, and Subject to view specific grades',
          ),
          _buildInfoItem(
            Icons.search,
            'Search Students',
            'Use the search bar to find students by name or roll number',
          ),
          _buildInfoItem(
            Icons.analytics,
            'View Statistics',
            'Check the statistics card for pass/fail rates and grading progress',
          ),
          _buildInfoItem(
            Icons.download,
            'Export PDF',
            'Download grades as PDF report for sharing or printing',
          ),
          _buildInfoItem(
            Icons.refresh,
            'Refresh Data',
            'Use the refresh button to get the latest grades and student data',
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
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem('📊', 'Complete all filters for accurate statistics'),
          _buildTipItem(
            '🔍',
            'Use status filters to quickly identify students needing attention',
          ),
          _buildTipItem(
            '📝',
            'Ensure all students are graded before finalizing results',
          ),
          _buildTipItem(
            '📄',
            'Export PDF reports for parent meetings and record keeping',
          ),
          _buildTipItem(
            '🔄',
            'Regularly refresh data when new grades are added',
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
              'Need help? Contact your system administrator for assistance with grade management.',
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

  Widget _buildDesktopSidebar() {
    return Container(
      width: 300,
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(bottom: BorderSide(color: Colors.blue[100]!)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.analytics,
                  size: 40,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Grade Reports',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.schoolName,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
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
              ? const Color.fromARGB(255, 21, 101, 192)
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
                  builder: (context) => AdminDashboardScreen(
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
          SizedBox(width: 8),
          Text(
            'View Grade Reports',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 103, 195),
            ),
          ),
          const Spacer(),
          // Export PDF Button
          if (_selectedExamId != null &&
              _selectedClassId != null &&
              _selectedSubjectId != null &&
              _grades.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 12),
              child: _buildExportButton(),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton() {
    return ElevatedButton.icon(
      onPressed: _exportingPdf ? null : _exportToPdf,
      icon: _exportingPdf
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download, size: 20),
      label: Text(
        _exportingPdf ? 'Exporting...' : 'Export PDF',
        style: const TextStyle(fontSize: 14),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildFiltersSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(_isDesktop ? 24 : 16),
        child: Column(
          children: [
            if (!_isDesktop) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Grade Filters',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 21, 101, 192),
                    ),
                  ),
                  // Export button for mobile/tablet
                  if (_selectedExamId != null &&
                      _selectedClassId != null &&
                      _selectedSubjectId != null &&
                      _grades.isNotEmpty)
                    _buildExportButton(),
                ],
              ),
              const SizedBox(height: 16),
            ],
            // Exam Selection
            DropdownButtonFormField<String>(
              value: _selectedExamId,
              decoration: InputDecoration(
                labelText: 'Select Exam *',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              items: _exams.map((exam) {
                return DropdownMenuItem<String>(
                  value: exam['id'],
                  child: Text(exam['exam_name']),
                );
              }).toList(),
              onChanged: _onExamChanged,
            ),
            const SizedBox(height: 16),

            // Class Selection
            DropdownButtonFormField<String>(
              value: _selectedClassId,
              decoration: InputDecoration(
                labelText: 'Select Class *',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              items: _classes.map((classData) {
                return DropdownMenuItem<String>(
                  value: classData['id'],
                  child: Text(classData['className']),
                );
              }).toList(),
              onChanged: _onClassChanged,
            ),
            const SizedBox(height: 16),

            // Subject Selection
            DropdownButtonFormField<String>(
              value: _selectedSubjectId,
              decoration: InputDecoration(
                labelText: 'Select Subject *',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              items: _getFilteredSubjects().map((subject) {
                return DropdownMenuItem<String>(
                  value: subject['id'],
                  child: Text(subject['subject_name']),
                );
              }).toList(),
              onChanged: _onSubjectChanged,
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get filtered subjects for the selected exam
  List<Map<String, dynamic>> _getFilteredSubjects() {
    if (_selectedExamId == null) return [];

    // Find the selected exam
    final selectedExam = _exams.firstWhere(
      (exam) => exam['id'] == _selectedExamId,
      orElse: () => {},
    );

    if (selectedExam.isEmpty) return [];

    // Get subject IDs from the exam
    final subjectsMarks = List<Map<String, dynamic>>.from(
      selectedExam['subjects_marks'] ?? [],
    );

    final examSubjectIds = subjectsMarks.map((subjectMark) {
      return subjectMark['subject_id'] as String;
    }).toList();

    // Filter subjects to only include those that are in the exam
    return _subjects.where((subject) {
      return examSubjectIds.contains(subject['id']);
    }).toList();
  }

  Widget _buildSearchAndFilterSection() {
    if (_selectedClassId == null || _students.isEmpty) return const SizedBox();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(_isDesktop ? 24 : 16),
        child: Column(
          children: [
            // Search Bar
            TextField(
              decoration: InputDecoration(
                labelText: 'Search Students',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 16),

            // Status Filter
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filter by Status:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildStatusChip('All', 'all'),
                    _buildStatusChip('Pass', 'pass'),
                    _buildStatusChip('Fail', 'fail'),
                    _buildStatusChip('Absent', 'absent'),
                    _buildStatusChip('Pending', 'pending'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _statusFilter == value,
      onSelected: (selected) => _onStatusFilterChanged(value),
      selectedColor: value == 'pass'
          ? Colors.green[100]
          : value == 'fail'
          ? Colors.red[100]
          : value == 'absent'
          ? Colors.orange[100]
          : value == 'pending'
          ? Colors.blue[100]
          : Colors.grey[100],
      labelStyle: TextStyle(
        color: _statusFilter == value ? Colors.black87 : Colors.grey[700],
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildStatisticsCard() {
    if (_selectedClassId == null || _students.isEmpty) {
      return const SizedBox();
    }

    final totalStudents = _students.length;
    final gradedStudents = _grades.length;
    final pendingStudents = totalStudents - gradedStudents;

    final subjectDetails = _getCurrentSubjectDetails();
    final passMarks = _safeParseInt(subjectDetails?['pass_marks']);

    int passedStudents = 0;
    int failedStudents = 0;
    int absentStudents = 0;

    for (var student in _students) {
      final studentGrade = _grades.firstWhere(
        (grade) => grade['student_id'] == student['id'],
        orElse: () => {},
      );

      if (studentGrade.isNotEmpty) {
        final isAbsent = studentGrade['is_absent'] == true;
        if (isAbsent) {
          absentStudents++;
        } else {
          final marksObtained = _safeParseInt(studentGrade['marks_obtained']);
          if (marksObtained >= passMarks) {
            passedStudents++;
          } else {
            failedStudents++;
          }
        }
      }
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(_isDesktop ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Grade Statistics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 21, 101, 192),
              ),
            ),
            const SizedBox(height: 16),
            _isDesktop
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        'Total',
                        totalStudents.toString(),
                        Colors.blue,
                      ),
                      _buildStatItem(
                        'Graded',
                        gradedStudents.toString(),
                        Colors.orange,
                      ),
                      _buildStatItem(
                        'Pending',
                        pendingStudents.toString(),
                        Colors.grey,
                      ),
                      _buildStatItem(
                        'Passed',
                        passedStudents.toString(),
                        Colors.green,
                      ),
                      _buildStatItem(
                        'Failed',
                        failedStudents.toString(),
                        Colors.red,
                      ),
                      _buildStatItem(
                        'Absent',
                        absentStudents.toString(),
                        Colors.orange,
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        'Total',
                        totalStudents.toString(),
                        Colors.blue,
                      ),
                      _buildStatItem(
                        'Graded',
                        gradedStudents.toString(),
                        Colors.orange,
                      ),
                      _buildStatItem(
                        'Pending',
                        pendingStudents.toString(),
                        Colors.grey,
                      ),
                      _buildStatItem(
                        'Passed',
                        passedStudents.toString(),
                        Colors.green,
                      ),
                      _buildStatItem(
                        'Failed',
                        failedStudents.toString(),
                        Colors.red,
                      ),
                      _buildStatItem(
                        'Absent',
                        absentStudents.toString(),
                        Colors.orange,
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: _isDesktop ? 18 : 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: _isDesktop ? 14 : 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStudentsList() {
    if (_selectedClassId == null) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.school, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'Please select a class to view students',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_students.isEmpty) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No students found in this class',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_filteredStudents.isEmpty) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No students match your search criteria',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                      _statusFilter = 'all';
                      _filteredStudents = List.from(_students);
                    });
                  },
                  child: const Text('Clear Filters'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final subjectDetails = _getCurrentSubjectDetails();
    final maxMarks = _safeParseInt(subjectDetails?['max_marks']);
    final passMarks = _safeParseInt(subjectDetails?['pass_marks']);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredStudents.length,
      itemBuilder: (context, index) {
        final student = _filteredStudents[index];
        final studentGrade = _grades.firstWhere(
          (grade) => grade['student_id'] == student['id'],
          orElse: () => {},
        );

        final hasGrade = studentGrade.isNotEmpty;
        final isAbsent = hasGrade && studentGrade['is_absent'] == true;
        final marksObtained = _safeParseInt(studentGrade['marks_obtained']);
        final isPass = marksObtained >= passMarks;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: !hasGrade
                  ? Colors.grey[100]
                  : isAbsent
                  ? Colors.orange[100]
                  : isPass
                  ? Colors.green[100]
                  : Colors.red[100],
              child: Icon(
                !hasGrade
                    ? Icons.person
                    : isAbsent
                    ? Icons.person_off
                    : isPass
                    ? Icons.check
                    : Icons.close,
                color: !hasGrade
                    ? Colors.grey
                    : isAbsent
                    ? Colors.orange
                    : isPass
                    ? Colors.green
                    : Colors.red,
              ),
            ),
            title: Text(
              _getStudentDisplayName(student),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (student['roll_number'] != null)
                  Text('Roll No: ${student['roll_number']}'),
                if (hasGrade && isAbsent)
                  const Text(
                    'Status: Absent',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  )
                else if (hasGrade)
                  Text(
                    'Marks: $marksObtained/$maxMarks',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isPass ? Colors.green : Colors.red,
                    ),
                  )
                else
                  const Text(
                    'No grade assigned',
                    style: TextStyle(color: Colors.orange),
                  ),
              ],
            ),
            trailing: !hasGrade
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Text(
                      'PENDING',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  )
                : isAbsent
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Text(
                      'ABSENT',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isPass ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isPass ? Colors.green : Colors.red,
                      ),
                    ),
                    child: Text(
                      isPass ? 'PASS' : 'FAIL',
                      style: TextStyle(
                        color: isPass ? Colors.green[700] : Colors.red[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar with info pages
        _buildDesktopSidebar(),
        // Main Content
        Expanded(
          child: Column(
            children: [
              _buildDesktopTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Success Message
                      if (_successMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_successMessage!)),
                            ],
                          ),
                        ),

                      // Error Message
                      if (_errorMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error, color: Colors.red),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_errorMessage!)),
                              IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _errorMessage = null;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                      // Filters Section
                      _buildFiltersSection(),
                      const SizedBox(height: 24),

                      // Statistics Card
                      _buildStatisticsCard(),
                      const SizedBox(height: 24),

                      // Search and Filter Section
                      _buildSearchAndFilterSection(),
                      const SizedBox(height: 24),

                      // Loading indicator for grades
                      if (_loadingGrades)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),

                      // Students List
                      _buildStudentsList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isMobile ? 'Grades' : 'Grade Reports - ${widget.schoolName}',
          style: TextStyle(fontSize: _isMobile ? 18 : 20),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color.fromARGB(255, 21, 101, 192),
        elevation: 0,
        actions: [
          if (_selectedExamId != null &&
              _selectedClassId != null &&
              _selectedSubjectId != null &&
              _grades.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: _exportingPdf
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                onPressed: _exportingPdf ? null : _exportToPdf,
                tooltip: 'Export PDF',
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(_isMobile ? 16 : 20),
              child: Column(
                children: [
                  // Success Message
                  if (_successMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_successMessage!)),
                        ],
                      ),
                    ),

                  // Error Message
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_errorMessage!)),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              setState(() {
                                _errorMessage = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                  // Filters Section
                  _buildFiltersSection(),
                  const SizedBox(height: 20),

                  // Statistics Card
                  _buildStatisticsCard(),
                  const SizedBox(height: 20),

                  // Search and Filter Section
                  _buildSearchAndFilterSection(),
                  const SizedBox(height: 20),

                  // Loading indicator for grades
                  if (_loadingGrades)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),

                  // Students List
                  _buildStudentsList(),
                ],
              ),
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
