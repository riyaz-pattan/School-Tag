import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

class ManageExamsScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;

  const ManageExamsScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<ManageExamsScreen> createState() => _ManageExamsScreenState();
}

class _ManageExamsScreenState extends State<ManageExamsScreen> {
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _subjects = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;

  // Cache variables
  DateTime? _lastExamsFetchTime;
  DateTime? _lastSubjectsFetchTime;
  static const int CACHE_DURATION_MINUTES = 10;

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
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadSubjects();
    await _loadExams();
  }

  // Convert to cache-safe format
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

  // Convert from cache-safe format
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

  // Load cached data
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

  // Save data to cache
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

  // Check if cache is valid
  bool _isCacheValid(DateTime? lastFetchTime) {
    if (lastFetchTime == null) return false;
    final difference = DateTime.now().difference(lastFetchTime);
    return difference.inMinutes < CACHE_DURATION_MINUTES;
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

    // Fetch from Firestore if cache is invalid
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
          _isLoading = false;
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
          'created_at': data['created_at'],
        };
      }).toList();

      await _saveToCache('exams', exams);

      setState(() {
        _exams = exams;
        _isLoading = false;
        _lastExamsFetchTime = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading exams: $e';
        _isLoading = false;
      });
    }
  }

  // Refresh data manually
  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Clear cache to force refresh
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('exams_${widget.schoolCode}');
    await prefs.remove('subjects_${widget.schoolCode}');

    await _loadSubjects();
    await _loadExams();
  }

  void _showAddExamDialog() {
    _errorMessage = null;
    _successMessage = null;

    showDialog(
      context: context,
      builder: (context) => _ExamDialog(subjects: _subjects, onSave: _saveExam),
    );
  }

  void _showEditExamDialog(Map<String, dynamic> exam) {
    _errorMessage = null;
    _successMessage = null;

    showDialog(
      context: context,
      builder: (context) => _ExamDialog(
        subjects: _subjects,
        onSave: (examName, subjectsMarks) =>
            _updateExam(exam['id'], examName, subjectsMarks),
        exam: exam,
      ),
    );
  }

  Future<void> _saveExam(
    String examName,
    List<Map<String, dynamic>> subjectsMarks,
  ) async {
    if (examName.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter exam name';
      });
      return;
    }

    if (subjectsMarks.isEmpty) {
      setState(() {
        _errorMessage = 'Please add at least one subject';
      });
      return;
    }

    // Check for empty fields
    for (var subjectMark in subjectsMarks) {
      if (subjectMark['max_marks'] == null ||
          subjectMark['max_marks'].isEmpty) {
        setState(() {
          _errorMessage = 'Please fill all maximum marks fields';
        });
        return;
      }
      if (subjectMark['pass_marks'] == null ||
          subjectMark['pass_marks'].isEmpty) {
        setState(() {
          _errorMessage = 'Please fill all pass marks fields';
        });
        return;
      }
    }

    // Check for duplicate subjects
    final subjectIds = subjectsMarks.map((sm) => sm['subject_id']).toList();
    if (subjectIds.toSet().length != subjectIds.length) {
      setState(() {
        _errorMessage = 'Duplicate subjects are not allowed';
      });
      return;
    }

    try {
      final examData = {
        'exam_name': examName,
        'subjects_marks': subjectsMarks,
        'school_code': widget.schoolCode,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exams')
          .add(examData);

      // Invalidate cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('exams_${widget.schoolCode}');

      setState(() {
        _successMessage = 'Exam created successfully';
      });

      _loadExams();
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving exam: $e';
      });
    }
  }

  Future<void> _updateExam(
    String examId,
    String examName,
    List<Map<String, dynamic>> subjectsMarks,
  ) async {
    if (examName.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter exam name';
      });
      return;
    }

    if (subjectsMarks.isEmpty) {
      setState(() {
        _errorMessage = 'Please add at least one subject';
      });
      return;
    }

    // Check for empty fields
    for (var subjectMark in subjectsMarks) {
      if (subjectMark['max_marks'] == null ||
          subjectMark['max_marks'].isEmpty) {
        setState(() {
          _errorMessage = 'Please fill all maximum marks fields';
        });
        return;
      }
      if (subjectMark['pass_marks'] == null ||
          subjectMark['pass_marks'].isEmpty) {
        setState(() {
          _errorMessage = 'Please fill all pass marks fields';
        });
        return;
      }
    }

    // Check for duplicate subjects
    final subjectIds = subjectsMarks.map((sm) => sm['subject_id']).toList();
    if (subjectIds.toSet().length != subjectIds.length) {
      setState(() {
        _errorMessage = 'Duplicate subjects are not allowed';
      });
      return;
    }

    try {
      final examData = {
        'exam_name': examName,
        'subjects_marks': subjectsMarks,
        'updated_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exams')
          .doc(examId)
          .update(examData);

      // Invalidate cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('exams_${widget.schoolCode}');

      setState(() {
        _successMessage = 'Exam updated successfully';
      });

      _loadExams();
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error updating exam: $e';
      });
    }
  }

  Future<void> _deleteExam(String examId, String examName) async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Exam'),
        content: Text('Are you sure you want to delete "$examName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('exams')
            .doc(examId)
            .delete();

        // Invalidate cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('exams_${widget.schoolCode}');

        setState(() {
          _successMessage = 'Exam deleted successfully';
        });
        _loadExams();
      } catch (e) {
        setState(() {
          _errorMessage = 'Error deleting exam: $e';
        });
      }
    }
  }

  Widget _buildExamList() {
    if (_exams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'No Exams Created',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Click the + button to create your first exam',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        itemCount: _exams.length,
        itemBuilder: (context, index) {
          final exam = _exams[index];
          final subjectsMarks = List<Map<String, dynamic>>.from(
            exam['subjects_marks'] ?? [],
          );
          final createdAt = exam['created_at'] != null
              ? (exam['created_at'] as Timestamp).toDate()
              : DateTime.now();

          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: ListTile(
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.deepOrange, Colors.orange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.assignment,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              title: Text(
                exam['exam_name'],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
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
                    'Created: ${_formatDate(createdAt)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.edit,
                        color: Colors.blue[700],
                        size: 18,
                      ),
                    ),
                    onPressed: () => _showEditExamDialog(exam),
                    tooltip: 'Edit Exam',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.delete,
                        color: Colors.red[700],
                        size: 18,
                      ),
                    ),
                    onPressed: () => _deleteExam(exam['id'], exam['exam_name']),
                    tooltip: 'Delete Exam',
                  ),
                ],
              ),
              onTap: () {
                _showExamDetails(exam);
              },
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showExamDetails(Map<String, dynamic> exam) {
    final subjectsMarks = List<Map<String, dynamic>>.from(
      exam['subjects_marks'] ?? [],
    );

    // Responsive dialog sizing - more flexible based on content
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Calculate dialog size based on content
    final baseHeight = _isMobile ? 0.6 : 0.5;
    final additionalHeight = (subjectsMarks.length * 0.05).clamp(0.0, 0.3);
    final dialogHeight = screenHeight * (baseHeight + additionalHeight);

    final dialogWidth = _isMobile
        ? screenWidth * 0.95
        : _isTablet
        ? screenWidth * 0.7
        : screenWidth * 0.4;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.deepOrange, Colors.orange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.assignment,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      exam['exam_name'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Title and Edit Button
              Row(
                children: [
                  const Text(
                    'Exam Details',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // Close details dialog
                      _showEditExamDialog(exam);
                    },
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Subjects Table
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildResponsiveSubjectsTable(subjectsMarks),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Close Button - Made smaller
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveSubjectsTable(
    List<Map<String, dynamic>> subjectsMarks,
  ) {
    if (_isMobile) {
      // Mobile: Use ListView with cards for better small screen experience
      return ListView.builder(
        itemCount: subjectsMarks.length,
        itemBuilder: (context, index) {
          final subject = subjectsMarks[index];
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: index < subjectsMarks.length - 1
                    ? BorderSide(color: Colors.grey[300]!)
                    : BorderSide.none,
              ),
            ),
            child: ListTile(
              title: Text(
                subject['subject_name'] ?? 'Unknown Subject',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Row(
                children: [
                  _buildMarksChip('Max: ${subject['max_marks']}', Colors.blue),
                  const SizedBox(width: 8),
                  _buildMarksChip(
                    'Pass: ${subject['pass_marks']}',
                    Colors.green,
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      // Tablet/Desktop: Use DataTable with horizontal scrolling only if needed
      return SingleChildScrollView(
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.grey[50]),
          dataRowMinHeight: 40,
          dataRowMaxHeight: 60,
          columns: const [
            DataColumn(
              label: Text(
                'Subject',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Max Marks',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            DataColumn(
              label: Text(
                'Pass Marks',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          rows: subjectsMarks.map((subjectMark) {
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    subjectMark['subject_name'],
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                DataCell(
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        subjectMark['max_marks'].toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        subjectMark['pass_marks'].toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      );
    }
  }

  Widget _buildMarksChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // Desktop sidebar info section
  Widget _buildDesktopSidebarInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📚 Exam Management Tips',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoTip('Create exams by adding subjects and setting marks'),
          _buildInfoTip(
            'Each exam can have multiple subjects with different mark distributions',
          ),
          _buildInfoTip(
            'Set both maximum marks and passing marks for each subject',
          ),
          _buildInfoTip('Use clear exam names for easy identification'),
          _buildInfoTip('You can edit or delete exams anytime'),
        ],
      ),
    );
  }

  Widget _buildInfoTip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.circle, size: 6, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
            ),
          ),
        ],
      ),
    );
  }

  // Desktop sidebar
  Widget _buildDesktopSidebar() {
    return Container(
      width: 260,
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
                    backgroundColor: Colors.deepOrange[100],
                    child: const Icon(
                      Icons.assignment,
                      size: 40,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Manage Exams',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.deepOrange,
                    ),
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
            Expanded(child: _buildDesktopSidebarInfo()),
          ],
        ),
      ),
    );
  }

  // Desktop top bar
  Widget _buildDesktopTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: Colors.white,
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.deepOrange),
            onPressed: () {
              Navigator.of(context).pop();
            },
            tooltip: 'Back to Dashboard',
          ),
          const Text(
            'Exam Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.deepOrange),
            onPressed: _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
    );
  }

  // Mobile/Tablet app bar
  AppBar _buildAppBar() {
    return AppBar(
      title: Text(
        _isMobile ? 'Exams' : 'Manage Exams - ${widget.schoolName}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      backgroundColor: Colors.deepOrange,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _isLoading ? null : _refreshData,
          tooltip: 'Refresh Data',
        ),
      ],
    );
  }

  // Main content for all layouts
  Widget _buildMainContent() {
    return Container(
      padding: EdgeInsets.all(_isDesktop ? 24 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.deepOrange.withOpacity(0.03),
            Colors.orange.withOpacity(0.05),
          ],
        ),
      ),
      child: Column(
        children: [
          // Error and Success Messages
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[700], fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          if (_successMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _successMessage!,
                      style: TextStyle(color: Colors.green[700], fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),

          // Statistics Cards
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'Total Exams',
                    _exams.length.toString(),
                    Icons.assignment,
                    Colors.deepOrange,
                  ),
                  _buildStatItem(
                    'Available Subjects',
                    _subjects.length.toString(),
                    Icons.subject,
                    Colors.blue,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(
                  'Exams List',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const Spacer(),
                Text(
                  '${_exams.length} exam${_exams.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Exams List
          Expanded(child: _buildExamList()),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 32, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            _buildDesktopSidebar(),
            Expanded(
              child: Column(
                children: [
                  _buildDesktopTopBar(),
                  Expanded(child: _buildMainContent()),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddExamDialog,
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.add, size: 28),
        ),
      );
    } else {
      return Scaffold(
        appBar: _buildAppBar(),
        body: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.deepOrange,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading Exams...',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : _buildMainContent(),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddExamDialog,
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.add, size: 28),
        ),
      );
    }
  }
}

class _ExamDialog extends StatefulWidget {
  final List<Map<String, dynamic>> subjects;
  final Future<void> Function(String, List<Map<String, dynamic>>) onSave;
  final Map<String, dynamic>? exam;

  const _ExamDialog({required this.subjects, required this.onSave, this.exam});

  @override
  State<_ExamDialog> createState() => __ExamDialogState();
}

class __ExamDialogState extends State<_ExamDialog> {
  final TextEditingController _examNameController = TextEditingController();
  List<Map<String, dynamic>> _subjectRows = [];
  List<TextEditingController> _maxMarksControllers = [];
  List<TextEditingController> _passMarksControllers = [];
  bool _isSaving = false;
  String? _errorMessage;
  String? _numberWarningMessage;
  Timer? _warningTimer;

  @override
  void initState() {
    super.initState();
    if (widget.exam != null) {
      // Edit mode - prefill data
      _examNameController.text = widget.exam!['exam_name'] ?? '';
      final subjectsMarks = List<Map<String, dynamic>>.from(
        widget.exam!['subjects_marks'] ?? [],
      );
      for (var subjectMark in subjectsMarks) {
        _subjectRows.add({
          'subject_id': subjectMark['subject_id'],
          'subject_name': subjectMark['subject_name'],
          'max_marks': subjectMark['max_marks'].toString(),
          'pass_marks': subjectMark['pass_marks'].toString(),
        });
        _maxMarksControllers.add(
          TextEditingController(text: subjectMark['max_marks'].toString()),
        );
        _passMarksControllers.add(
          TextEditingController(text: subjectMark['pass_marks'].toString()),
        );
      }
    } else {
      // Create mode - add empty row
      _addEmptyRows(1);
    }
  }

  @override
  void dispose() {
    _examNameController.dispose();
    // Dispose all mark controllers
    for (var controller in _maxMarksControllers) {
      controller.dispose();
    }
    for (var controller in _passMarksControllers) {
      controller.dispose();
    }
    // Cancel any active timer
    _warningTimer?.cancel();
    super.dispose();
  }

  void _showNumberWarning() {
    setState(() {
      _numberWarningMessage = 'Only numbers are allowed in marks fields';
    });

    // Cancel previous timer if exists
    _warningTimer?.cancel();

    // Set timer to hide warning after 3 seconds
    _warningTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _numberWarningMessage = null;
        });
      }
    });
  }

  void _addEmptyRows(int count) {
    for (int i = 0; i < count; i++) {
      _subjectRows.add({
        'subject_id': null,
        'subject_name': null,
        'max_marks': '',
        'pass_marks': '',
      });
      _maxMarksControllers.add(TextEditingController());
      _passMarksControllers.add(TextEditingController());
    }
  }

  void _addRow() {
    setState(() {
      _subjectRows.add({
        'subject_id': null,
        'subject_name': null,
        'max_marks': '',
        'pass_marks': '',
      });
      _maxMarksControllers.add(TextEditingController());
      _passMarksControllers.add(TextEditingController());
    });
  }

  void _removeRow(int index) {
    setState(() {
      _subjectRows.removeAt(index);
      _maxMarksControllers[index].dispose();
      _passMarksControllers[index].dispose();
      _maxMarksControllers.removeAt(index);
      _passMarksControllers.removeAt(index);
    });
  }

  void _updateSubject(int index, String? subjectId, String? subjectName) {
    setState(() {
      _subjectRows[index]['subject_id'] = subjectId;
      _subjectRows[index]['subject_name'] = subjectName;
    });
  }

  void _updateMarks(int index, String field, String value) {
    // Only allow numbers
    if (value.isNotEmpty && !RegExp(r'^[0-9]*$').hasMatch(value)) {
      _showNumberWarning();
      // Clear the non-numeric value
      if (field == 'max_marks') {
        _maxMarksControllers[index].text = '';
      } else {
        _passMarksControllers[index].text = '';
      }
      setState(() {
        _subjectRows[index][field] = '';
      });
      return;
    }
    setState(() {
      _subjectRows[index][field] = value;
    });
  }

  bool get _isFormValid {
    if (_examNameController.text.trim().isEmpty) return false;

    for (var row in _subjectRows) {
      if (row['subject_id'] == null ||
          row['max_marks']!.isEmpty ||
          row['pass_marks']!.isEmpty) {
        return false;
      }

      // Check passing marks validation
      int maxMarks = int.tryParse(row['max_marks']) ?? 0;
      int passMarks = int.tryParse(row['pass_marks']) ?? 0;

      if (passMarks >= maxMarks) {
        return false;
      }
    }

    final subjectIds = _subjectRows
        .where((row) => row['subject_id'] != null)
        .map((row) => row['subject_id'])
        .toList();

    return subjectIds.toSet().length == subjectIds.length;
  }

  String? _getValidationError() {
    if (_examNameController.text.trim().isEmpty) {
      return 'Please enter exam name';
    }

    for (var row in _subjectRows) {
      if (row['subject_id'] == null) {
        return 'Please select all subjects';
      }
      if (row['max_marks']!.isEmpty || row['pass_marks']!.isEmpty) {
        return 'Please fill all marks fields';
      }

      // Check passing marks validation
      int maxMarks = int.tryParse(row['max_marks']) ?? 0;
      int passMarks = int.tryParse(row['pass_marks']) ?? 0;

      if (passMarks >= maxMarks) {
        return 'Passing marks must be less than maximum marks for ${row['subject_name']}';
      }
    }

    final subjectIds = _subjectRows
        .where((row) => row['subject_id'] != null)
        .map((row) => row['subject_id'])
        .toList();

    if (subjectIds.toSet().length != subjectIds.length) {
      return 'Duplicate subjects are not allowed';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isLargeScreen ? 550 : double.infinity,
          maxHeight: screenHeight * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.deepOrange, Colors.orange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.exam != null ? Icons.edit : Icons.assignment_add,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.exam != null ? 'Edit Exam' : 'Create New Exam',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 24),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 16),

              // Form content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Exam Name Field
                      TextField(
                        controller: _examNameController,
                        decoration: InputDecoration(
                          labelText: 'Exam Name *',
                          hintText: 'e.g., Mid-term Examination, Final Exam',
                          prefixIcon: const Icon(Icons.assignment_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 24),

                      // Number warning message
                      if (_numberWarningMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning,
                                color: Colors.orange[700],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _numberWarningMessage!,
                                  style: TextStyle(
                                    color: Colors.orange[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Error message
                      if (_errorMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red[700],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Subjects & Marks Section
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey[200]!),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.subject,
                                    color: Colors.deepOrange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Subjects & Marks',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.deepOrange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_subjectRows.length} subject${_subjectRows.length == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        color: Colors.deepOrange,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Rows
                              Column(
                                children: _subjectRows.asMap().entries.map((
                                  entry,
                                ) {
                                  final index = entry.key;
                                  final row = entry.value;

                                  return _buildSubjectRow(index, row);
                                }).toList(),
                              ),

                              const SizedBox(height: 16),

                              // Add Row Button
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _addRow,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add Another Subject'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.deepOrange,
                                    side: BorderSide(
                                      color: Colors.deepOrange.withOpacity(0.3),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Buttons
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving || !_isFormValid
                          ? null
                          : () async {
                              setState(() {
                                _isSaving = true;
                                _errorMessage = null;
                              });

                              // Validate form before saving
                              final validationError = _getValidationError();
                              if (validationError != null) {
                                setState(() {
                                  _errorMessage = validationError;
                                  _isSaving = false;
                                });
                                return;
                              }

                              final validRows = _subjectRows
                                  .where((row) => row['subject_id'] != null)
                                  .map(
                                    (row) => {
                                      'subject_id': row['subject_id'],
                                      'subject_name': row['subject_name'],
                                      'max_marks': row['max_marks'],
                                      'pass_marks': row['pass_marks'],
                                    },
                                  )
                                  .toList();

                              await widget.onSave(
                                _examNameController.text.trim(),
                                validRows,
                              );

                              if (mounted) {
                                setState(() {
                                  _isSaving = false;
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _isSaving
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
                          : Text(
                              widget.exam != null
                                  ? 'Update Exam'
                                  : 'Create Exam',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectRow(int index, Map<String, dynamic> row) {
    final availableSubjects = _getAvailableSubjectsForIndex(index, row);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject Dropdown and Remove Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Subject *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String?>(
                      value: row['subject_id'],
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'Select Subject',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        ...availableSubjects.map<DropdownMenuItem<String?>>((
                          subject,
                        ) {
                          return DropdownMenuItem<String?>(
                            value: subject['id'] as String,
                            child: Text(
                              subject['subject_name'] ?? '',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        final subject = widget.subjects.firstWhere(
                          (s) => s['id'] == value,
                          orElse: () => {},
                        );
                        _updateSubject(
                          index,
                          value,
                          subject.isNotEmpty ? subject['subject_name'] : null,
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (_subjectRows.length > 1) ...[
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.red[700],
                        size: 20,
                      ),
                    ),
                    onPressed: () => _removeRow(index),
                    tooltip: 'Remove subject',
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // Marks inputs
          LayoutBuilder(
            builder: (context, constraints) {
              final bool useRowLayout = constraints.maxWidth > 400;

              if (useRowLayout) {
                return Row(
                  children: [
                    Expanded(
                      child: _buildMarksField(
                        label: 'Maximum Marks *',
                        controller: _maxMarksControllers[index],
                        onChanged: (value) =>
                            _updateMarks(index, 'max_marks', value),
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMarksField(
                        label: 'Passing Marks *',
                        controller: _passMarksControllers[index],
                        onChanged: (value) =>
                            _updateMarks(index, 'pass_marks', value),
                        color: Colors.green,
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildMarksField(
                      label: 'Maximum Marks *',
                      controller: _maxMarksControllers[index],
                      onChanged: (value) =>
                          _updateMarks(index, 'max_marks', value),
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    _buildMarksField(
                      label: 'Passing Marks *',
                      controller: _passMarksControllers[index],
                      onChanged: (value) =>
                          _updateMarks(index, 'pass_marks', value),
                      color: Colors.green,
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMarksField({
    required String label,
    required TextEditingController controller,
    required Function(String) onChanged,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            hintText: 'e.g., 100',
            prefixIcon: Icon(Icons.numbers, size: 18, color: color),
          ),
          keyboardType: TextInputType.number,
          onChanged: onChanged,
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _getAvailableSubjectsForIndex(
    int index,
    Map<String, dynamic> currentRow,
  ) {
    final selectedSubjectIds = _subjectRows
        .where((row) => row != currentRow && row['subject_id'] != null)
        .map((row) => row['subject_id'])
        .toList();

    return widget.subjects.where((subject) {
      return !selectedSubjectIds.contains(subject['id']);
    }).toList();
  }
}
