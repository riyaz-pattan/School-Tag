// teacher_view_exam_schedule_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'teacher_dashboard_screen.dart';

class TeacherViewExamScheduleScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String teacherId;

  const TeacherViewExamScheduleScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.teacherId,
  });

  @override
  State<TeacherViewExamScheduleScreen> createState() =>
      _TeacherViewExamScheduleScreenState();
}

class _TeacherViewExamScheduleScreenState
    extends State<TeacherViewExamScheduleScreen> {
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _classes = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;

  // New state variables for viewing schedules
  String? _selectedViewExamId;
  List<String> _selectedViewClassIds = [];
  List<Map<String, dynamic>> _viewSchedules = [];
  bool _isLoadingSchedules = false;
  bool _isRefreshing = false;

  // Cache management
  final Map<String, dynamic> _cache = {};
  DateTime? _lastCacheUpdate;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  // Helper method to convert Firestore data to JSON-serializable format
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

  // Helper method to convert JSON data back to Firestore types
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

  @override
  void initState() {
    super.initState();
    _clearCorruptedCache().then((_) {
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

  Future<void> _clearCorruptedCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${widget.schoolCode}_exams');
    await prefs.remove('${widget.schoolCode}_classes');
    await prefs.remove('${widget.schoolCode}_schedules');
  }

  // Cache management methods
  Future<void> _cacheData(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '${widget.schoolCode}_$key';
      final serializableData = _convertToJsonSerializable(data);
      final cacheData = {
        'data': serializableData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(cacheKey, json.encode(cacheData));
    } catch (e) {
      print('Error caching data: $e');
    }
  }

  Future<dynamic> _getCachedData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '${widget.schoolCode}_$key';
      final cachedString = prefs.getString(cacheKey);

      if (cachedString == null) return null;

      final cacheData = json.decode(cachedString);
      final timestamp = cacheData['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Cache valid for 5 minutes
      if (now - timestamp > 5 * 60 * 1000) {
        await prefs.remove(cacheKey);
        return null;
      }

      final cachedData = cacheData['data'];
      return _convertFromJsonSerializable(cachedData);
    } catch (e) {
      print('Error reading cached data: $e');
      // If there's an error reading cache, clear it to avoid future issues
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${widget.schoolCode}_$key');
      return null;
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
      // Clear all cache and reload
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${widget.schoolCode}_exams');
      await prefs.remove('${widget.schoolCode}_classes');

      // Clear all schedule cache keys
      final keys = await prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('${widget.schoolCode}_schedules')) {
          await prefs.remove(key);
        }
      }

      // Clear current selections and data
      setState(() {
        _selectedViewExamId = null;
        _selectedViewClassIds = [];
        _viewSchedules = [];
      });

      // Reload data from Firebase
      await _loadExams();
      await _loadClasses();

      setState(() {
        _successMessage = 'Data refreshed successfully! ✅';
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
        _errorMessage = 'Error refreshing data: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  // Methods for viewing schedules
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
            '📅 Exam Schedule Info',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoTip('View exam schedules for your classes'),
          _buildInfoTip('Select multiple classes to compare schedules'),
          _buildInfoTip('Each subject in an exam has its own schedule'),
          _buildInfoTip('Schedules help plan exam preparation'),
          _buildInfoTip('Contact admin for any schedule changes'),
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
            icon: const Icon(Icons.arrow_back, color: Colors.deepPurple),
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
            'View Exam Schedules',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const Spacer(),
          if (_isRefreshing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.deepPurple,
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
                ? 'Exam Schedules'
                : 'Exam Schedules - ${widget.schoolName}',
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
      actions: [
        if (!_isMobile)
          _isRefreshing
              ? const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshData,
                  tooltip: 'Refresh Data',
                ),
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
                  Expanded(child: _buildViewSchedulesTab()),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return Scaffold(
        appBar: _buildAppBar(),
        body: _isLoading ? _buildLoadingState() : _buildViewSchedulesTab(),
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

  Widget _buildViewSchedulesTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Messages
          if (_errorMessage != null) _buildMessage(_errorMessage!, true),
          if (_successMessage != null) _buildMessage(_successMessage!, false),
          const SizedBox(height: 16),

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
          if (_viewSchedules.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: _isDesktop
                  ? const EdgeInsets.symmetric(horizontal: 24)
                  : const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Found ${_viewSchedules.length} schedule${_viewSchedules.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ..._viewSchedules
                .map(
                  (schedule) => Padding(
                    padding: _isDesktop
                        ? const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          )
                        : const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                    child: _buildScheduleCard(schedule),
                  ),
                )
                .toList(),
          ] else if (_selectedViewExamId != null &&
              _selectedViewClassIds.isNotEmpty &&
              !_isLoadingSchedules) ...[
            const SizedBox(height: 32),
            _buildEmptyState(
              icon: Icons.schedule_outlined,
              title: 'No Schedules Found',
              subtitle: 'No schedules found for the selected criteria',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String label,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    required Function(String?) onChanged,
    required String displayField,
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
      ),
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item['id'],
          child: Text(
            item[displayField],
            style: TextStyle(fontSize: _isDesktop ? 16 : 14),
          ),
        );
      }).toList(),
      onChanged: onChanged,
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

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
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
              subtitle,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.assignment, color: Colors.deepPurple, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        schedule['exam_name'] ?? 'Unknown Exam',
                        style: TextStyle(
                          fontSize: _isDesktop ? 20 : 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
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
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Schedule Items
            if (scheduleItems.isEmpty)
              _buildEmptyState(
                icon: Icons.schedule_outlined,
                title: 'No Schedule Items',
                subtitle: 'No subjects scheduled for this exam',
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Schedule Items (${scheduleItems.length}):',
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
}
