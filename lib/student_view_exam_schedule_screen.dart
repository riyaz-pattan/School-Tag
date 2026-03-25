// student_view_exam_schedule_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'student_dashboard_screen.dart';

class StudentViewExamScheduleScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String studentId;
  final String? classId;

  const StudentViewExamScheduleScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.studentId,
    required this.classId,
  });

  @override
  State<StudentViewExamScheduleScreen> createState() =>
      _StudentViewExamScheduleScreenState();
}

class _StudentViewExamScheduleScreenState
    extends State<StudentViewExamScheduleScreen> {
  List<Map<String, dynamic>> _availableExams = [];
  Map<String, dynamic>? _selectedExam;
  List<Map<String, dynamic>> _examSchedules = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;
  bool _isRefreshing = false;

  // Cache keys
  static const String _examsCacheKey = 'available_exams';
  static const String _examSchedulesCacheKey = 'exam_schedules';
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
    _loadAvailableExams();
  }

  Future<void> _loadAvailableExams() async {
    if (widget.classId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      // Try to load from cache first
      final cachedExams = _prefs.getString(
        '${_examsCacheKey}_${widget.schoolCode}_${widget.classId}',
      );
      if (cachedExams != null) {
        final decodedData = json.decode(cachedExams);
        setState(() {
          _availableExams = List<Map<String, dynamic>>.from(
            _convertFromJsonSerializable(decodedData),
          );
          _isLoading = false;
        });
      }
      // Load from network
      await _loadAvailableExamsFromFirebase();
    } catch (e) {
      print('Error loading available exams: $e');
      setState(() {
        _errorMessage = 'Error loading available exams: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAvailableExamsFromFirebase() async {
    if (widget.classId == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolCode)
        .collection('exam_schedules')
        .where('class_id', isEqualTo: widget.classId)
        .get();

    // Load exam details for each schedule
    List<Map<String, dynamic>> exams = [];
    for (var scheduleDoc in snapshot.docs) {
      final scheduleData = scheduleDoc.data();
      // Get exam details
      final examDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('exams')
          .doc(scheduleData['exam_id'])
          .get();
      if (examDoc.exists) {
        final examData = examDoc.data()!;
        exams.add({
          'id': scheduleDoc.id,
          'exam_id': scheduleData['exam_id'],
          'exam_name': examData['exam_name'],
          'exam_description': examData['exam_description'] ?? '',
          'schedule_items': List<Map<String, dynamic>>.from(
            scheduleData['schedule_items'] ?? [],
          ),
          'created_at': scheduleData['created_at'],
        });
      }
    }
    setState(() {
      _availableExams = exams;
      _isLoading = false;
    });
    // Cache the exams
    await _prefs.setString(
      '${_examsCacheKey}_${widget.schoolCode}_${widget.classId}',
      json.encode(_convertToJsonSerializable(exams)),
    );
  }

  Future<void> _onExamSelected(Map<String, dynamic>? exam) async {
    setState(() {
      _selectedExam = exam;
      _examSchedules = exam != null ? [exam] : [];
    });

    if (exam != null) {
      // Cache the selected exam schedule
      await _prefs.setString(
        '${_examSchedulesCacheKey}_${widget.schoolCode}_${widget.classId}_${exam['exam_id']}',
        json.encode(_convertToJsonSerializable([exam])),
      );
    }
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Clear cache and reload
      await _prefs.remove(
        '${_examsCacheKey}_${widget.schoolCode}_${widget.classId}',
      );
      if (_selectedExam != null) {
        await _prefs.remove(
          '${_examSchedulesCacheKey}_${widget.schoolCode}_${widget.classId}_${_selectedExam!['exam_id']}',
        );
      }

      await _loadAvailableExamsFromFirebase();

      setState(() {
        _successMessage = 'Exam data refreshed successfully! ✅';
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
        _errorMessage = 'Error refreshing exam data: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  // Helper methods for JSON conversion
  dynamic _convertToJsonSerializable(dynamic data) {
    if (data is Timestamp) {
      return {
        '_timestamp': true,
        'seconds': data.seconds,
        'nanoseconds': data.nanoseconds,
      };
    } else if (data is Map<String, dynamic>) {
      return data.map(
        (key, value) => MapEntry(key, _convertToJsonSerializable(value)),
      );
    } else if (data is List<dynamic>) {
      return data.map((item) => _convertToJsonSerializable(item)).toList();
    } else if (data is DocumentReference) {
      return {'_documentReference': true, 'path': data.path};
    } else if (data is GeoPoint) {
      return {
        '_geoPoint': true,
        'latitude': data.latitude,
        'longitude': data.longitude,
      };
    }
    return data;
  }

  dynamic _convertFromJsonSerializable(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['_timestamp'] == true) {
        return Timestamp(data['seconds'], data['nanoseconds']);
      } else if (data['_documentReference'] == true) {
        return FirebaseFirestore.instance.doc(data['path']);
      } else if (data['_geoPoint'] == true) {
        return GeoPoint(data['latitude'], data['longitude']);
      } else {
        return data.map(
          (key, value) => MapEntry(key, _convertFromJsonSerializable(value)),
        );
      }
    } else if (data is List<dynamic>) {
      return data.map((item) => _convertFromJsonSerializable(item)).toList();
    }
    return data;
  }

  // Desktop Layout
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar with auto-slide
        _ExamScheduleInfoSidebar(schoolName: widget.schoolName),
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
              color: Color.fromARGB(255, 74, 20, 140),
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
            'My Exam Schedules',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 74, 20, 140),
            ),
          ),
          const Spacer(),
          if (_isRefreshing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color.fromARGB(255, 74, 20, 140),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.deepPurple),
              onPressed: _refreshData,
              tooltip: 'Refresh Data',
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
            Icon(Icons.schedule, color: Colors.white),
            SizedBox(width: 12),
            Text(
              'Exam Schedules',
              style: TextStyle(fontSize: _isDesktop ? 20 : 18),
            ),
          ],
        ),
        backgroundColor: Color.fromARGB(255, 74, 20, 140),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    if (widget.classId == null) {
      return _buildNoClassAssigned();
    }

    if (_isLoading) {
      return _buildLoadingState();
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Messages
          if (_errorMessage != null) _buildMessage(_errorMessage!, true),
          if (_successMessage != null) _buildMessage(_successMessage!, false),
          const SizedBox(height: 16),

          // Content
          Padding(
            padding: _isDesktop
                ? const EdgeInsets.all(24)
                : const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header for mobile/tablet
                if (!_isDesktop) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 28,
                        color: Color.fromARGB(255, 74, 20, 140),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'My Exam Schedules',
                        style: TextStyle(
                          fontSize: _isDesktop ? 24 : 20,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 74, 20, 140),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Exam Selection Dropdown
                _buildExamSelectionDropdown(),

                const SizedBox(height: 24),

                // Schedule Display
                if (_selectedExam == null)
                  _buildNoExamSelected()
                else if (_examSchedules.isEmpty)
                  _buildEmptyState()
                else
                  ..._examSchedules
                      .map(
                        (schedule) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildScheduleCard(schedule),
                        ),
                      )
                      .toList(),
              ],
            ),
          ),
        ],
      ),
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
                  color: Color.fromARGB(255, 74, 20, 140),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Select Exam',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color.fromARGB(255, 74, 20, 140),
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
                value:
                    _findSelectedExamInList(), // Use helper method to find the exact instance
                hint: Text(
                  'Choose an exam to view schedule',
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
                    value: exam, // Use the exact instance from _availableExams
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
                'No exams available for your class',
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

  // Helper method to find the exact exam instance in _availableExams that matches _selectedExam
  Map<String, dynamic>? _findSelectedExamInList() {
    if (_selectedExam == null) return null;

    // Find the exam in _availableExams that has the same ID as _selectedExam
    try {
      return _availableExams.firstWhere(
        (exam) => exam['id'] == _selectedExam!['id'],
      );
    } catch (e) {
      // If not found, return null to avoid the error
      return null;
    }
  }

  Widget _buildNoExamSelected() {
    return Center(
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
              'Choose an exam from the dropdown above to view its schedule',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color.fromARGB(255, 158, 157, 157),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoClassAssigned() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.class_, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Not Assigned to Any Class',
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
              'Please contact admin to assign you to a class',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color.fromARGB(255, 158, 157, 157),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            color: Color.fromARGB(255, 74, 20, 140),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading Exam Schedules...',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No Schedule Available',
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
              'No schedule items found for the selected exam',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color.fromARGB(255, 158, 157, 157),
              ),
            ),
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

  Widget _buildScheduleCard(Map<String, dynamic> schedule) {
    final scheduleItems = List<Map<String, dynamic>>.from(
      schedule['schedule_items'] ?? [],
    );

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: _isDesktop
            ? const EdgeInsets.all(24)
            : const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.assignment,
                  color: Color.fromARGB(255, 74, 20, 140),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        schedule['exam_name'] ?? 'Unknown Exam',
                        style: TextStyle(
                          fontSize: _isDesktop ? 20 : 18,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 74, 20, 140),
                        ),
                      ),
                      if (schedule['exam_description'] != null &&
                          schedule['exam_description'].isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            schedule['exam_description'],
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Schedule Items
            if (scheduleItems.isEmpty)
              _buildEmptyScheduleItems()
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exam Schedule:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...scheduleItems
                      .map((item) => _buildScheduleItem(item))
                      .toList(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyScheduleItems() {
    return Center(
      child: Column(
        children: [
          Icon(Icons.schedule_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'No Schedule Items',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No subjects scheduled for this exam',
            style: const TextStyle(
              fontSize: 14,
              color: Color.fromARGB(255, 158, 157, 157),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleItem(Map<String, dynamic> item) {
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
              color: Color.fromARGB(255, 74, 20, 140).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.subject,
              color: Color.fromARGB(255, 74, 20, 140),
              size: 24,
            ),
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
class _ExamScheduleInfoSidebar extends StatefulWidget {
  final String schoolName;

  const _ExamScheduleInfoSidebar({required this.schoolName});

  @override
  State<_ExamScheduleInfoSidebar> createState() =>
      _ExamScheduleInfoSidebarState();
}

class _ExamScheduleInfoSidebarState extends State<_ExamScheduleInfoSidebar> {
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
            'Understanding Exam Schedules',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 74, 20, 140),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.assignment,
            'Select Exam First',
            'Choose an exam from the dropdown to view its schedule',
          ),
          _buildInfoItem(
            Icons.subject,
            'Subject-wise Schedule',
            'Each subject in the exam has its own date and time',
          ),
          _buildInfoItem(
            Icons.calendar_today,
            'Exam Dates',
            'Pay attention to the specific date for each subject',
          ),
          _buildInfoItem(
            Icons.access_time,
            'Time Slots',
            'Exams have specific start and end times - arrive early!',
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
            'Exam Preparation Tips',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 74, 20, 140),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            '📅',
            'Select an exam first to view its complete schedule',
          ),
          _buildTipItem('⏰', 'Note the exact time for each subject exam'),
          _buildTipItem('📚', 'Organize study materials by subject and exam'),
          _buildTipItem(
            '🔄',
            'Use refresh button to get latest schedule updates',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.fromARGB(255, 74, 20, 140).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Color.fromARGB(255, 74, 20, 140).withOpacity(0.3),
              ),
            ),
            child: const Text(
              'Always double-check exam schedules regularly as they may be updated by school administration.',
              style: TextStyle(
                fontSize: 12,
                color: Color.fromARGB(255, 74, 20, 140),
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
          Icon(icon, size: 20, color: Color.fromARGB(255, 74, 20, 140)),
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
              color: Color.fromARGB(255, 74, 20, 140).withOpacity(0.1),
              border: Border(
                bottom: BorderSide(
                  color: Color.fromARGB(255, 74, 20, 140).withOpacity(0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.schedule,
                  size: 40,
                  color: Color.fromARGB(255, 74, 20, 140),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Exam Schedules',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 74, 20, 140),
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
