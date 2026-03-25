// create_exam_schedule_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CreateExamScheduleScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;

  const CreateExamScheduleScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<CreateExamScheduleScreen> createState() =>
      _CreateExamScheduleScreenState();
}

class _CreateExamScheduleScreenState extends State<CreateExamScheduleScreen> {
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _classes = [];
  String? _selectedExamId;
  String? _selectedClassId;
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;

  // New state variables for viewing schedules
  String? _selectedViewExamId;
  List<String> _selectedViewClassIds = [];
  List<Map<String, dynamic>> _viewSchedules = [];
  bool _isLoadingSchedules = false;

  // Cache management
  final Map<String, dynamic> _cache = {};
  DateTime? _lastCacheUpdate;

  // Active tab for desktop (0 = Create, 1 = View)
  int _activeDesktopTab = 0;

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
    // Clear any corrupted cache immediately
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();

      // Clear ALL cache for this school code to start fresh
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('${widget.schoolCode}_')) {
          await prefs.remove(key);
        }
      }

      // Then load data
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    try {
      await Future.wait([_loadExams(), _loadClasses()]);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadExams() async {
    // Check cache first
    final cachedExams = await _getCachedData('exams');
    if (cachedExams != null) {
      setState(() {
        _exams = List<Map<String, dynamic>>.from(cachedExams);
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exams')
          .orderBy('created_at', descending: true)
          .get();

      final examsData = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'exam_name': data['exam_name'],
          'subjects_marks': List<Map<String, dynamic>>.from(
            data['subjects_marks'] ?? [],
          ),
        };
      }).toList();

      setState(() {
        _exams = examsData;
      });

      // Cache the data
      await _cacheData('exams', examsData);
    } catch (e) {
      print('Error loading exams: $e');
      // Clear cache if there's an error
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${widget.schoolCode}_exams');
    }
  }

  Future<void> _loadClasses() async {
    // Check cache first
    final cachedClasses = await _getCachedData('classes');
    if (cachedClasses != null) {
      setState(() {
        _classes = List<Map<String, dynamic>>.from(cachedClasses);
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();

      final classesData = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'grade': data['grade'],
          'sections': data['sections'] ?? [],
          'className':
              'Grade ${data['grade']} ${(data['sections'] as List).isNotEmpty ? '(${data['sections'].join(', ')})' : ''}',
        };
      }).toList();

      setState(() {
        _classes = classesData;
      });

      // Cache the data
      await _cacheData('classes', classesData);
    } catch (e) {
      print('Error loading classes: $e');
      // Clear cache if there's an error
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${widget.schoolCode}_classes');
    }
  }

  // Replace the _clearCorruptedCache() method with this:
  Future<void> _clearCorruptedCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear all cache keys for this school
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith('${widget.schoolCode}_')) {
          final value = prefs.getString(key);
          if (value != null) {
            try {
              // Try to parse the JSON to check if it's valid
              json.decode(value);
              // If we get here, JSON is valid
            } catch (e) {
              // JSON is corrupted, remove it
              await prefs.remove(key);
              print('Removed corrupted cache: $key');
            }
          }
        }
      }

      // Also clear specific keys to be safe
      await prefs.remove('${widget.schoolCode}_exams');
      await prefs.remove('${widget.schoolCode}_classes');
      await prefs.remove('${widget.schoolCode}_schedules');
    } catch (e) {
      print('Error clearing corrupted cache: $e');
    }
  }

  // Cache management methods
  Future<void> _cacheData(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '${widget.schoolCode}_$key';
      final cacheData = {
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(cacheKey, json.encode(cacheData));
    } catch (e) {
      print('Error caching data: $e');
    }
  }

  // Also update the _getCachedData() method to be more robust:
  Future<dynamic> _getCachedData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '${widget.schoolCode}_$key';
      final cachedString = prefs.getString(cacheKey);

      if (cachedString == null) return null;

      // Validate JSON format
      final decoded = json.decode(cachedString);

      if (decoded is! Map<String, dynamic>) {
        throw FormatException('Invalid cache format for key: $cacheKey');
      }

      final timestamp = decoded['timestamp'] as int?;
      final data = decoded['data'];

      if (timestamp == null || data == null) {
        throw FormatException(
          'Missing required cache fields for key: $cacheKey',
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // Cache valid for 5 minutes
      if (now - timestamp > 5 * 60 * 1000) {
        await prefs.remove(cacheKey);
        return null;
      }

      return data;
    } catch (e) {
      print('Error reading cached data: $e');
      // If there's an error reading cache, clear it to avoid future issues
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${widget.schoolCode}_$key');
      return null;
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });

    // Clear cache and reload
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${widget.schoolCode}_exams');
    await prefs.remove('${widget.schoolCode}_classes');

    await _loadInitialData();
  }

  Future<void> _checkExistingSchedule() async {
    if (_selectedExamId == null || _selectedClassId == null) return;

    try {
      final existingSchedule = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exam_schedules')
          .where('exam_id', isEqualTo: _selectedExamId)
          .where('class_id', isEqualTo: _selectedClassId)
          .get();

      if (existingSchedule.docs.isNotEmpty) {
        _showScheduleOptionsDialog(existingSchedule.docs.first);
      } else {
        _showCreateScheduleDialog();
      }
    } catch (e) {
      print('Error checking existing schedule: $e');
      _showCreateScheduleDialog();
    }
  }

  void _showScheduleOptionsDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> existingSchedule,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Schedule Exists'),
          ],
        ),
        content: const Text(
          'An exam schedule already exists for this class. What would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditScheduleDialog(existingSchedule);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit, size: 18),
                SizedBox(width: 4),
                Text('Edit Existing'),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showCreateScheduleDialog();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 18),
                SizedBox(width: 4),
                Text('Create New'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateScheduleDialog() {
    final selectedExam = _exams.firstWhere(
      (exam) => exam['id'] == _selectedExamId,
    );
    final selectedClass = _classes.firstWhere(
      (cls) => cls['id'] == _selectedClassId,
    );

    showDialog(
      context: context,
      builder: (context) => ExamScheduleDialog(
        exam: selectedExam,
        classData: selectedClass,
        schoolCode: widget.schoolCode,
        onSave: _saveExamSchedule,
      ),
    );
  }

  void _showEditScheduleDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> existingSchedule,
  ) {
    final selectedExam = _exams.firstWhere(
      (exam) => exam['id'] == _selectedExamId,
    );
    final selectedClass = _classes.firstWhere(
      (cls) => cls['id'] == _selectedClassId,
    );

    showDialog(
      context: context,
      builder: (context) => ExamScheduleDialog(
        exam: selectedExam,
        classData: selectedClass,
        schoolCode: widget.schoolCode,
        existingSchedule: existingSchedule.data(),
        onSave: _saveExamSchedule,
      ),
    );
  }

  Future<void> _saveExamSchedule(
    String examId,
    String classId,
    List<Map<String, dynamic>> scheduleItems,
  ) async {
    try {
      final scheduleData = {
        'exam_id': examId,
        'class_id': classId,
        'schedule_items': scheduleItems,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Check if schedule already exists
      final existingQuery = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exam_schedules')
          .where('exam_id', isEqualTo: examId)
          .where('class_id', isEqualTo: classId)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        await existingQuery.docs.first.reference.update(scheduleData);
      } else {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('exam_schedules')
            .add(scheduleData);
      }

      setState(() {
        _successMessage = 'Exam schedule saved successfully! 🎉';
      });

      // Clear selections
      setState(() {
        _selectedExamId = null;
        _selectedClassId = null;
      });

      // Clear schedule cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${widget.schoolCode}_schedules');

      // Reload schedules if viewing
      if (_selectedViewExamId != null && _selectedViewClassIds.isNotEmpty) {
        _loadViewSchedules();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving exam schedule: $e';
      });
    }
  }

  // New methods for viewing schedules
  Future<void> _loadViewSchedules() async {
    if (_selectedViewExamId == null || _selectedViewClassIds.isEmpty) {
      setState(() {
        _viewSchedules = [];
      });
      return;
    }

    setState(() {
      _isLoadingSchedules = true;
    });

    try {
      // Check cache first
      final cacheKey =
          '${widget.schoolCode}_schedules_${_selectedViewExamId}_${_selectedViewClassIds.join('_')}';
      final cachedSchedules = await _getCachedData(cacheKey);

      if (cachedSchedules != null) {
        setState(() {
          _viewSchedules = List<Map<String, dynamic>>.from(cachedSchedules);
          _isLoadingSchedules = false;
        });
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exam_schedules')
          .where('exam_id', isEqualTo: _selectedViewExamId)
          .where('class_id', whereIn: _selectedViewClassIds)
          .get();

      final schedules = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final classData = _classes.firstWhere(
          (cls) => cls['id'] == data['class_id'],
          orElse: () => {'className': 'Unknown Class'},
        );

        final examData = _exams.firstWhere(
          (exam) => exam['id'] == data['exam_id'],
          orElse: () => {'exam_name': 'Unknown Exam'},
        );

        schedules.add({
          'id': doc.id,
          ...data,
          'class_name': classData['className'],
          'exam_name': examData['exam_name'],
        });
      }

      setState(() {
        _viewSchedules = schedules;
      });

      // Cache the schedules
      await _cacheData(cacheKey, schedules);
    } catch (e) {
      print('Error loading schedules: $e');
      setState(() {
        _errorMessage = 'Error loading schedules: $e';
      });
    } finally {
      setState(() {
        _isLoadingSchedules = false;
      });
    }
  }

  Future<void> _deleteExamSchedule(String scheduleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Schedule'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this exam schedule? This action cannot be undone.',
        ),
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

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exam_schedules')
          .doc(scheduleId)
          .delete();

      setState(() {
        _successMessage = 'Exam schedule deleted successfully! ✅';
        _viewSchedules.removeWhere((schedule) => schedule['id'] == scheduleId);
      });

      // Clear schedule cache
      final prefs = await SharedPreferences.getInstance();
      final keys = await prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('${widget.schoolCode}_schedules')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error deleting exam schedule: $e';
      });
    }
  }

  void _toggleViewClass(String classId) {
    setState(() {
      if (_selectedViewClassIds.contains(classId)) {
        _selectedViewClassIds.remove(classId);
      } else {
        _selectedViewClassIds.add(classId);
      }
    });
  }

  void _clearViewSelections() {
    setState(() {
      _selectedViewExamId = null;
      _selectedViewClassIds = [];
      _viewSchedules = [];
    });
  }

  void _setActiveDesktopTab(int index) {
    setState(() {
      _activeDesktopTab = index;
    });
  }

  // Desktop sidebar info section
  Widget _buildDesktopSidebarInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📅 Exam Schedule Tips',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoTip(
            'Create schedules for exams by selecting date and time for each subject',
          ),
          _buildInfoTip('You can edit existing schedules or create new ones'),
          _buildInfoTip('View and compare schedules across multiple classes'),
          _buildInfoTip('Each subject in an exam can have its own schedule'),
          _buildInfoTip(
            'Schedules help students and teachers plan exam preparation',
          ),
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
          const Icon(Icons.circle, size: 6, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.deepPurple),
            ),
          ),
        ],
      ),
    );
  }

  // Replace the _buildDesktopSidebar() method with this corrected version:
  Widget _buildDesktopSidebar() {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey[300]!)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.deepPurple[100],
                    child: const Icon(
                      Icons.schedule,
                      size: 40,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Exam Schedules',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.deepPurple,
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

  // Also fix the _buildDesktopTopBar() method:
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
            icon: const Icon(Icons.arrow_back, color: Colors.deepPurple),
            onPressed: () {
              Navigator.of(context).pop();
            },
            tooltip: 'Back to Dashboard',
          ),
          Text(
            'Exam Schedule Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.deepPurple),
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
      title: Row(
        children: [
          Icon(
            Icons.schedule_send,
            color: _isMobile ? Colors.deepPurple : Colors.white,
          ),
          const SizedBox(width: 12),
          Text(
            _isMobile
                ? 'Exam Schedule'
                : 'Exam Schedule - ${widget.schoolName}',
            style: TextStyle(
              fontSize: _isDesktop ? 20 : 18,
              color: _isMobile ? Colors.deepPurple : Colors.white,
            ),
          ),
        ],
      ),
      backgroundColor: _isMobile ? Colors.deepPurple[50] : Colors.deepPurple,
      foregroundColor: _isMobile ? Colors.deepPurple : Colors.white,
      elevation: _isMobile ? 0 : 2,
      bottom: TabBar(
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        labelColor: _isMobile ? Colors.deepPurple : Colors.white,
        unselectedLabelColor: _isMobile
            ? Colors.deepPurple[600]
            : Colors.white70,
        indicatorColor: _isMobile ? Colors.deepPurple : Colors.white,
        tabs: const [
          Tab(icon: Icon(Icons.add_circle_outline), text: 'Create Schedule'),
          Tab(icon: Icon(Icons.visibility_outlined), text: 'View Schedules'),
        ],
      ),
      actions: [
        if (_isDesktop)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh Data',
          ),
      ],
    );
  }

  // Desktop main content area
  Widget _buildDesktopMainContent() {
    return Column(
      children: [
        _buildDesktopTopBar(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left panel - Filters (Fixed width)
              Container(
                width: 380,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.grey[300]!)),
                  color: Colors.grey[50],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Navigation buttons for desktop
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _setActiveDesktopTab(0),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _activeDesktopTab == 0
                                    ? Colors.deepPurple
                                    : Colors.grey[200],
                                foregroundColor: _activeDesktopTab == 0
                                    ? Colors.white
                                    : Colors.grey[800],
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_circle_outline, size: 18),
                                  SizedBox(width: 8),
                                  Text('Create'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _setActiveDesktopTab(1),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _activeDesktopTab == 1
                                    ? Colors.deepPurple
                                    : Colors.grey[200],
                                foregroundColor: _activeDesktopTab == 1
                                    ? Colors.white
                                    : Colors.grey[800],
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.visibility_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('View'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Show appropriate filters based on active tab
                      if (_activeDesktopTab == 0)
                        _buildCreateFiltersForDesktop(),
                      if (_activeDesktopTab == 1) _buildViewFiltersForDesktop(),
                    ],
                  ),
                ),
              ),

              // Right panel - Main content (Flexible)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  child: _buildDesktopContentArea(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Create filters for desktop
  Widget _buildCreateFiltersForDesktop() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create Exam Schedule',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select exam and class to create or edit schedule',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),

        // Exam Dropdown
        _buildDropdown(
          value: _selectedExamId,
          label: 'Select Exam',
          icon: Icons.assignment_outlined,
          items: _exams,
          onChanged: (value) => setState(() => _selectedExamId = value),
          displayField: 'exam_name',
          isDesktop: true,
        ),
        const SizedBox(height: 20),

        // Class Dropdown
        _buildDropdown(
          value: _selectedClassId,
          label: 'Select Class',
          icon: Icons.class_outlined,
          items: _classes,
          onChanged: (value) => setState(() => _selectedClassId = value),
          displayField: 'className',
          isDesktop: true,
        ),
        const SizedBox(height: 32),

        // Create Schedule Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selectedExamId != null && _selectedClassId != null
                ? _checkExistingSchedule
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_send, size: 20),
                SizedBox(width: 8),
                Text('Create/Edit Schedule'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // View filters for desktop
  Widget _buildViewFiltersForDesktop() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'View Exam Schedules',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select exam and classes to view schedules',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),

        // Exam Dropdown for Viewing
        _buildDropdown(
          value: _selectedViewExamId,
          label: 'Select Exam',
          icon: Icons.assignment_outlined,
          items: _exams,
          onChanged: (value) {
            setState(() {
              _selectedViewExamId = value;
              _selectedViewClassIds = [];
              _viewSchedules = [];
            });
          },
          displayField: 'exam_name',
          isDesktop: true,
        ),
        const SizedBox(height: 20),

        // Class Selection (Multiple)
        if (_selectedViewExamId != null) ...[
          Text(
            'Select Classes to Compare:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            constraints: BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _classes.map((cls) {
                  final isSelected = _selectedViewClassIds.contains(cls['id']);
                  return FilterChip(
                    label: Text(
                      cls['className'],
                      style: TextStyle(fontSize: 13),
                    ),
                    selected: isSelected,
                    onSelected: (selected) => _toggleViewClass(cls['id']),
                    checkmarkColor: Colors.white,
                    selectedColor: Colors.deepPurple,
                    backgroundColor: Colors.grey[200],
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[800],
                      fontWeight: FontWeight.w500,
                    ),
                    avatar: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed:
                    _selectedViewExamId != null &&
                        _selectedViewClassIds.isNotEmpty
                    ? _loadViewSchedules
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoadingSchedules
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search, size: 18),
                          SizedBox(width: 8),
                          Text('Load Schedules'),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _clearViewSelections,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.clear_all, size: 18),
                  SizedBox(width: 8),
                  Text('Clear'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Desktop content area
  Widget _buildDesktopContentArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Messages
        if (_errorMessage != null) ...[
          _buildMessage(_errorMessage!, true),
          const SizedBox(height: 16),
        ],
        if (_successMessage != null) ...[
          _buildMessage(_successMessage!, false),
          const SizedBox(height: 16),
        ],

        // Content based on active tab
        Expanded(
          child: _activeDesktopTab == 0
              ? _buildCreateDesktopContent()
              : _buildViewDesktopContent(),
        ),
      ],
    );
  }

  // Create content for desktop
  Widget _buildCreateDesktopContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.schedule_outlined, size: 100, color: Colors.grey[300]),
        const SizedBox(height: 20),
        Text(
          'Ready to Create Schedule',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Select an exam and class from the left panel\nand click "Create/Edit Schedule" to begin',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
        const SizedBox(height: 32),
        if (_selectedExamId != null && _selectedClassId != null)
          ElevatedButton(
            onPressed: _checkExistingSchedule,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_send, size: 20),
                SizedBox(width: 12),
                Text('Create/Edit Schedule Now'),
              ],
            ),
          ),
      ],
    );
  }

  // View content for desktop
  Widget _buildViewDesktopContent() {
    if (_selectedViewExamId == null) {
      return _buildEmptyState(
        icon: Icons.assignment_outlined,
        title: 'Select an Exam',
        subtitle: 'Choose an exam from the left panel to view schedules',
        isDesktop: true,
      );
    }

    if (_selectedViewClassIds.isEmpty) {
      return _buildEmptyState(
        icon: Icons.class_outlined,
        title: 'Select Classes',
        subtitle: 'Choose classes from the left panel to view schedules',
        isDesktop: true,
      );
    }

    if (_isLoadingSchedules) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 3, color: Colors.deepPurple),
            const SizedBox(height: 16),
            Text(
              'Loading Schedules...',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (_viewSchedules.isEmpty) {
      return _buildEmptyState(
        icon: Icons.schedule_outlined,
        title: 'No Schedules Found',
        subtitle: 'No schedules found for the selected criteria',
        isDesktop: true,
      );
    }

    return ListView.builder(
      itemCount: _viewSchedules.length,
      itemBuilder: (context, index) {
        final schedule = _viewSchedules[index];
        return _buildScheduleCard(schedule);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(
        body: _isLoading
            ? _buildLoadingState()
            : Row(
                children: [
                  _buildDesktopSidebar(),
                  Expanded(child: _buildDesktopMainContent()),
                ],
              ),
      );
    } else {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: _buildAppBar(),
          body: _isLoading
              ? _buildLoadingState()
              : TabBarView(
                  children: [
                    _buildCreateScheduleTab(),
                    _buildViewSchedulesTab(),
                  ],
                ),
        ),
      );
    }
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(strokeWidth: 3, color: Colors.deepPurple),
          const SizedBox(height: 16),
          Text(
            'Loading Exam Data...',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateScheduleTab() {
    return SingleChildScrollView(
      padding: _isDesktop ? const EdgeInsets.all(24) : const EdgeInsets.all(16),
      child: Column(
        children: [
          // Messages
          if (_errorMessage != null) _buildMessage(_errorMessage!, true),
          if (_successMessage != null) _buildMessage(_successMessage!, false),
          const SizedBox(height: 16),

          // Selection Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              padding: _isDesktop
                  ? const EdgeInsets.all(32)
                  : const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.create_outlined,
                        size: 28,
                        color: Colors.deepPurple,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Create Exam Schedule',
                        style: TextStyle(
                          fontSize: _isDesktop ? 24 : 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Exam Dropdown
                  _buildDropdown(
                    value: _selectedExamId,
                    label: 'Select Exam',
                    icon: Icons.assignment_outlined,
                    items: _exams,
                    onChanged: (value) =>
                        setState(() => _selectedExamId = value),
                    displayField: 'exam_name',
                    isDesktop: _isDesktop,
                  ),
                  const SizedBox(height: 20),

                  // Class Dropdown
                  _buildDropdown(
                    value: _selectedClassId,
                    label: 'Select Class',
                    icon: Icons.class_outlined,
                    items: _classes,
                    onChanged: (value) =>
                        setState(() => _selectedClassId = value),
                    displayField: 'className',
                    isDesktop: _isDesktop,
                  ),
                  const SizedBox(height: 32),

                  // Create Schedule Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _selectedExamId != null && _selectedClassId != null
                          ? _checkExistingSchedule
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: _isDesktop ? 20 : 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_send, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Create/Edit Schedule',
                            style: TextStyle(fontSize: _isDesktop ? 18 : 16),
                          ),
                        ],
                      ),
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

  Widget _buildViewSchedulesTab() {
    return Column(
      children: [
        // Selection Card
        Card(
          elevation: 4,
          margin: _isDesktop
              ? const EdgeInsets.all(24)
              : const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: _isDesktop
                ? const EdgeInsets.all(32)
                : const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 28,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'View Exam Schedules',
                      style: TextStyle(
                        fontSize: _isDesktop ? 24 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Exam Dropdown for Viewing
                _buildDropdown(
                  value: _selectedViewExamId,
                  label: 'Select Exam',
                  icon: Icons.assignment_outlined,
                  items: _exams,
                  onChanged: (value) {
                    setState(() {
                      _selectedViewExamId = value;
                      _selectedViewClassIds = [];
                      _viewSchedules = [];
                    });
                  },
                  displayField: 'exam_name',
                  isDesktop: _isDesktop,
                ),
                const SizedBox(height: 20),

                // Class Selection (Multiple)
                if (_selectedViewExamId != null) ...[
                  Text(
                    'Select Classes to Compare:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: _isDesktop ? 18 : 16,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _classes.map((cls) {
                      final isSelected = _selectedViewClassIds.contains(
                        cls['id'],
                      );
                      return FilterChip(
                        label: Text(cls['className']),
                        selected: isSelected,
                        onSelected: (selected) => _toggleViewClass(cls['id']),
                        checkmarkColor: Colors.white,
                        selectedColor: Colors.deepPurple,
                        backgroundColor: Colors.grey[200],
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[800],
                          fontWeight: FontWeight.w500,
                        ),
                        avatar: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            _selectedViewExamId != null &&
                                _selectedViewClassIds.isNotEmpty
                            ? _loadViewSchedules
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: _isDesktop ? 16 : 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoadingSchedules
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.search, size: 18),
                                  const SizedBox(width: 8),
                                  const Text('Load Schedules'),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _clearViewSelections,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: _isDesktop ? 16 : 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.clear_all, size: 18),
                          const SizedBox(width: 8),
                          const Text('Clear'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Schedules List
        Expanded(child: _buildSchedulesList()),
      ],
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String label,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    required Function(String?) onChanged,
    required String displayField,
    bool isDesktop = false,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.deepPurple),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: isDesktop ? 18 : 16,
          horizontal: 16,
        ),
      ),
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item['id'],
          child: Text(
            item[displayField],
            style: TextStyle(fontSize: isDesktop ? 16 : 14),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: onChanged,
      isExpanded: true,
    );
  }

  Widget _buildMessage(String message, bool isError) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: _isDesktop ? 0 : 16),
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
              if (isError) {
                _errorMessage = null;
              } else {
                _successMessage = null;
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulesList() {
    if (_selectedViewExamId == null) {
      return _buildEmptyState(
        icon: Icons.assignment_outlined,
        title: 'Select an Exam',
        subtitle: 'Choose an exam to view schedules',
        isDesktop: false,
      );
    }

    if (_selectedViewClassIds.isEmpty) {
      return _buildEmptyState(
        icon: Icons.class_outlined,
        title: 'Select Classes',
        subtitle: 'Choose classes to compare schedules',
        isDesktop: false,
      );
    }

    if (_isLoadingSchedules) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 3, color: Colors.deepPurple),
            const SizedBox(height: 16),
            Text(
              'Loading Schedules...',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (_viewSchedules.isEmpty) {
      return _buildEmptyState(
        icon: Icons.schedule_outlined,
        title: 'No Schedules Found',
        subtitle: 'No schedules found for the selected criteria',
        isDesktop: false,
      );
    }

    return ListView.builder(
      padding: _isDesktop ? const EdgeInsets.all(24) : const EdgeInsets.all(16),
      itemCount: _viewSchedules.length,
      itemBuilder: (context, index) {
        final schedule = _viewSchedules[index];
        return _buildScheduleCard(schedule);
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDesktop,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: isDesktop ? 80 : 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: isDesktop ? 22 : 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: Color.fromARGB(255, 158, 157, 157),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> schedule) {
    final scheduleItems = List<Map<String, dynamic>>.from(
      schedule['schedule_items'] ?? [],
    );

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: _isDesktop
            ? const EdgeInsets.all(24)
            : const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with delete button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.assignment,
                            color: Colors.deepPurple,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            schedule['exam_name'] ?? 'Unknown Exam',
                            style: TextStyle(
                              fontSize: _isDesktop ? 20 : 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.class_, color: Colors.grey[600], size: 16),
                          const SizedBox(width: 6),
                          Text(
                            schedule['class_name'] ?? 'Unknown Class',
                            style: TextStyle(
                              fontSize: _isDesktop ? 16 : 14,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteExamSchedule(schedule['id']),
                  tooltip: 'Delete Schedule',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Schedule Items
            if (scheduleItems.isEmpty)
              _buildEmptyState(
                icon: Icons.schedule_outlined,
                title: 'No Schedule Items',
                subtitle: 'No subjects scheduled for this exam',
                isDesktop: false,
              )
            else
              Column(
                children: scheduleItems
                    .map((item) => _buildScheduleItem(item))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleItem(Map<String, dynamic> item) {
    // Helper function to convert 24-hour format to 12-hour format with AM/PM
    String _formatTimeTo12Hour(String? time24) {
      if (time24 == null || time24.isEmpty) return 'Not set';

      try {
        final parts = time24.split(':');
        if (parts.length != 2) return time24;

        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1]);

        String period = hour >= 12 ? 'PM' : 'AM';
        if (hour > 12) hour -= 12;
        if (hour == 0) hour = 12;

        return '${hour}:${minute.toString().padLeft(2, '0')} $period';
      } catch (e) {
        return time24;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.subject, color: Colors.deepPurple, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['subject_name'] ?? 'Unknown Subject',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: _isDesktop ? 18 : 16,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Date: ${_formatDisplayDate(item['date'])}',
                      style: TextStyle(
                        fontSize: _isDesktop ? 14 : 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      'Time: ${_formatTimeTo12Hour(item['start_time'])} - ${_formatTimeTo12Hour(item['end_time'])}',
                      style: TextStyle(
                        fontSize: _isDesktop ? 14 : 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDisplayDate(String? dateString) {
    if (dateString == null) return 'Not set';
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateString);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }
}

String _formatDisplayDate(DateTime? date) {
  if (date == null) return 'Not set';
  return DateFormat('MMM dd, yyyy').format(date);
}

// Helper function to convert 24-hour format to 12-hour format with AM/PM
String _formatTimeTo12Hour(String? time24) {
  if (time24 == null || time24.isEmpty) return 'Not set';

  try {
    final parts = time24.split(':');
    if (parts.length != 2) return time24;

    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);

    String period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;

    return '${hour}:${minute.toString().padLeft(2, '0')} $period';
  } catch (e) {
    return time24;
  }
}

class ExamScheduleDialog extends StatefulWidget {
  final Map<String, dynamic> exam;
  final Map<String, dynamic> classData;
  final String schoolCode;
  final Map<String, dynamic>? existingSchedule;
  final Future<void> Function(String, String, List<Map<String, dynamic>>)
  onSave;

  const ExamScheduleDialog({
    super.key,
    required this.exam,
    required this.classData,
    required this.schoolCode,
    this.existingSchedule,
    required this.onSave,
  });

  @override
  State<ExamScheduleDialog> createState() => _ExamScheduleDialogState();
}

class _ExamScheduleDialogState extends State<ExamScheduleDialog> {
  List<Map<String, dynamic>> _scheduleItems = [];
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 768;

  @override
  void initState() {
    super.initState();
    if (widget.existingSchedule != null) {
      _scheduleItems = List<Map<String, dynamic>>.from(
        widget.existingSchedule!['schedule_items'] ?? [],
      );
    }
  }

  void _addScheduleItem() {
    setState(() {
      _scheduleItems.add({
        'subject_id': null,
        'subject_name': null,
        'date': null,
        'start_time': null,
        'end_time': null,
      });
    });
  }

  void _removeScheduleItem(int index) {
    setState(() {
      _scheduleItems.removeAt(index);
    });
  }

  void _updateScheduleItem(int index, String field, dynamic value) {
    setState(() {
      _scheduleItems[index][field] = value;
    });
  }

  List<Map<String, dynamic>> get _availableSubjects {
    final examSubjects = List<Map<String, dynamic>>.from(
      widget.exam['subjects_marks'] ?? [],
    );

    final scheduledSubjectIds = _scheduleItems
        .where((item) => item['subject_id'] != null)
        .map((item) => item['subject_id'])
        .toList();

    return examSubjects.where((subject) {
      return !scheduledSubjectIds.contains(subject['subject_id']);
    }).toList();
  }

  bool get _isFormValid {
    for (var item in _scheduleItems) {
      if (item['subject_id'] == null ||
          item['date'] == null ||
          item['start_time'] == null ||
          item['end_time'] == null) {
        return false;
      }
    }
    return _scheduleItems.isNotEmpty;
  }

  // Helper function to convert 24-hour format to 12-hour format with AM/PM
  String _formatTimeTo12Hour(String? time24) {
    if (time24 == null || time24.isEmpty) return 'Select Time';

    try {
      final parts = time24.split(':');
      if (parts.length != 2) return time24;

      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);

      String period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;

      return '${hour}:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return time24;
    }
  }

  Future<void> _saveSchedule() async {
    if (!_isFormValid) {
      setState(() {
        _errorMessage = 'Please fill all fields for all subjects';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.onSave(
        widget.exam['id'],
        widget.classData['id'],
        _scheduleItems,
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving schedule: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: _isDesktop ? 700 : 500,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(_isDesktop ? 24 : 20),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_send,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Exam Schedule - ${widget.exam['exam_name']}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _isDesktop ? 20 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.classData['className'],
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: _isDesktop ? 16 : 14,
                          ),
                        ),
                      ],
                    ),
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
              child: Padding(
                padding: EdgeInsets.all(_isDesktop ? 24 : 20),
                child: Column(
                  children: [
                    // Error Message
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
                            Icon(Icons.error_outline, color: Colors.red[700]),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_errorMessage!)),
                          ],
                        ),
                      ),

                    // Schedule Items Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Schedule Items',
                          style: TextStyle(
                            fontSize: _isDesktop ? 18 : 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                        Text(
                          '${_scheduleItems.length} subject${_scheduleItems.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Schedule Items List
                    Expanded(
                      child: _scheduleItems.isEmpty
                          ? _buildEmptyScheduleState()
                          : ListView.builder(
                              itemCount: _scheduleItems.length,
                              itemBuilder: (context, index) {
                                return _buildScheduleItemCard(index);
                              },
                            ),
                    ),

                    // Add Button
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _availableSubjects.isEmpty
                                  ? null
                                  : _addScheduleItem,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Subject'),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  vertical: _isDesktop ? 16 : 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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

            // Footer Buttons
            Container(
              padding: EdgeInsets.all(_isDesktop ? 24 : 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: _isDesktop ? 16 : 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving || !_isFormValid
                          ? null
                          : _saveSchedule,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: _isDesktop ? 16 : 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.save, size: 18),
                                const SizedBox(width: 8),
                                const Text('Save Schedule'),
                              ],
                            ),
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

  Widget _buildEmptyScheduleState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No Subjects Scheduled',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click the "Add Subject" button to start\ncreating your exam schedule',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color.fromARGB(255, 158, 158, 158),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleItemCard(int index) {
    final item = _scheduleItems[index];
    final availableSubjects = _availableSubjects;

    // Add back the current subject to available options
    if (item['subject_id'] != null) {
      final currentSubject = (widget.exam['subjects_marks'] as List<dynamic>)
          .firstWhere(
            (subject) =>
                (subject as Map<String, dynamic>)['subject_id'] ==
                item['subject_id'],
            orElse: () => <String, dynamic>{},
          );
      if (currentSubject.isNotEmpty) {
        availableSubjects.insert(0, currentSubject as Map<String, dynamic>);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with delete button
            Row(
              children: [
                Icon(Icons.subject, color: Colors.deepPurple, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Subject ${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                if (_scheduleItems.length > 1)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    onPressed: () => _removeScheduleItem(index),
                    tooltip: 'Remove Subject',
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Subject dropdown
            DropdownButtonFormField<String>(
              value: item['subject_id'],
              decoration: InputDecoration(
                labelText: 'Select Subject',
                prefixIcon: const Icon(Icons.menu_book_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: availableSubjects.map((subject) {
                return DropdownMenuItem<String>(
                  value: subject['subject_id'],
                  child: Text(subject['subject_name']),
                );
              }).toList(),
              onChanged: (value) {
                final subject = availableSubjects.firstWhere(
                  (s) => s['subject_id'] == value,
                );
                _updateScheduleItem(index, 'subject_id', value);
                _updateScheduleItem(
                  index,
                  'subject_name',
                  subject['subject_name'],
                );
              },
            ),
            const SizedBox(height: 16),

            // Date and Time Section - Responsive layout
            if (_isDesktop)
              Row(
                children: [
                  Expanded(child: _buildDatePicker(index)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTimePicker(index, 'start_time', 'Start Time'),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTimePicker(index, 'end_time', 'End Time'),
                  ),
                ],
              )
            else
              Column(
                children: [
                  // Date Picker - Full width on mobile
                  _buildDatePicker(index),
                  const SizedBox(height: 12),

                  // Time Pickers - Stacked vertically on mobile
                  _buildTimePicker(index, 'start_time', 'Start Time'),
                  const SizedBox(height: 12),
                  _buildTimePicker(index, 'end_time', 'End Time'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePicker(int index) {
    final item = _scheduleItems[index];
    return InkWell(
      onTap: () async {
        final selectedDate = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (selectedDate != null) {
          _updateScheduleItem(
            index,
            'date',
            DateFormat('yyyy-MM-dd').format(selectedDate),
          );
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Exam Date',
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              item['date'] != null
                  ? DateFormat(
                      'MMM dd, yyyy',
                    ).format(DateFormat('yyyy-MM-dd').parse(item['date']))
                  : 'Select Date',
              style: TextStyle(
                color: item['date'] != null ? Colors.black : Colors.grey,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(int index, String field, String label) {
    final item = _scheduleItems[index];

    return InkWell(
      onTap: () async {
        final selectedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
          builder: (BuildContext context, Widget? child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(alwaysUse24HourFormat: false),
              child: child!,
            );
          },
        );
        if (selectedTime != null) {
          _updateScheduleItem(
            index,
            field,
            '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
          );
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.access_time_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _formatTimeTo12Hour(item[field]),
                style: TextStyle(
                  color: item[field] != null ? Colors.black : Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
