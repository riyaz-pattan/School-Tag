import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

class ManageSubjectsScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;

  const ManageSubjectsScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<ManageSubjectsScreen> createState() => _ManageSubjectsScreenState();
}

class _ManageSubjectsScreenState extends State<ManageSubjectsScreen> {
  final TextEditingController _subjectIdController = TextEditingController();
  final TextEditingController _subjectNameController = TextEditingController();
  List<Map<String, dynamic>> _teachers = [];
  List<String> _selectedTeacherIds = [];
  List<Map<String, dynamic>> _subjects = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;
  bool _isSaving = false;
  Map<String, dynamic>? _editingSubject;

  // Cache variables
  DateTime? _lastTeachersFetchTime;
  DateTime? _lastSubjectsFetchTime;
  static const int CACHE_DURATION_MINUTES = 10;

  // Timer for auto-dismissing messages
  Timer? _messageTimer;

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

  @override
  void dispose() {
    _subjectIdController.dispose();
    _subjectNameController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  void _showMessage(String message, bool isError) {
    // Cancel any existing timer
    _messageTimer?.cancel();

    setState(() {
      if (isError) {
        _errorMessage = message;
        _successMessage = null;
      } else {
        _successMessage = message;
        _errorMessage = null;
      }
    });

    // Auto-dismiss after 3 seconds
    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (isError) {
            _errorMessage = null;
          } else {
            _successMessage = null;
          }
        });
      }
    });
  }

  void _clearMessages() {
    _messageTimer?.cancel();
    if (_errorMessage != null || _successMessage != null) {
      setState(() {
        _errorMessage = null;
        _successMessage = null;
      });
    }
  }

  Future<void> _loadInitialData() async {
    try {
      // Load teachers first, then subjects
      await _loadTeachers();
      await _loadSubjects();
    } catch (e) {
      _showMessage('Error loading initial data: ${e.toString()}', true);
    }
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

  Future<void> _loadTeachers() async {
    // Try to load from cache first
    final cachedData = await _loadCachedData('teachers');
    if (cachedData != null) {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (_isCacheValid(timestamp)) {
        final cachedTeachers = (cachedData['data'] as List)
            .map(
              (item) => _convertFromCacheSafe(Map<String, dynamic>.from(item)),
            )
            .toList();
        setState(() {
          _teachers = List<Map<String, dynamic>>.from(cachedTeachers);
        });
        return;
      }
    }

    // Fetch from Firestore if cache is invalid
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'teacher')
          .get();

      final teachers = snapshot.docs.map((doc) {
        final data = doc.data();
        final username = data['username']?.toString() ?? 'Unknown';
        final fullName = data['full_name']?.toString() ?? 'No Name';
        final displayName = fullName != 'No Name'
            ? '$fullName - $username'
            : username;

        return {
          'id': doc.id,
          'username': username,
          'full_name': fullName,
          'display_name': displayName,
        };
      }).toList();

      await _saveToCache('teachers', teachers);

      setState(() {
        _teachers = teachers;
        _lastTeachersFetchTime = DateTime.now();
      });
    } catch (e) {
      _showMessage('Error loading teachers: ${e.toString()}', true);
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
            .map(
              (item) => _convertFromCacheSafe(Map<String, dynamic>.from(item)),
            )
            .toList();

        // Ensure teacher_names is properly formatted
        final formattedSubjects = cachedSubjects.map((subject) {
          // Convert teacher_names to List<String> if it's not already
          if (subject['teacher_names'] != null &&
              subject['teacher_names'] is List) {
            subject['teacher_names'] = List<String>.from(
              subject['teacher_names'],
            );
          } else {
            subject['teacher_names'] = <String>[];
          }

          // Ensure teacher_ids is properly formatted
          if (subject['teacher_ids'] != null &&
              subject['teacher_ids'] is List) {
            subject['teacher_ids'] = List<String>.from(subject['teacher_ids']);
          } else {
            subject['teacher_ids'] = <String>[];
          }

          return subject;
        }).toList();

        setState(() {
          _subjects = List<Map<String, dynamic>>.from(formattedSubjects);
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
          .collection('subjects')
          .orderBy('subject_name')
          .get();

      final subjects = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'subject_id': data['subject_id']?.toString() ?? 'Unknown ID',
          'subject_name': data['subject_name']?.toString() ?? 'Unknown Subject',
          'teacher_ids': List<String>.from(data['teacher_ids'] ?? []),
          'teacher_names': List<String>.from(data['teacher_names'] ?? []),
        };
      }).toList();

      await _saveToCache('subjects', subjects);

      setState(() {
        _subjects = subjects;
        _isLoading = false;
        _lastSubjectsFetchTime = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Error loading subjects: ${e.toString()}', true);
    }
  }

  // Refresh data manually
  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Clear cache to force refresh
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('teachers_${widget.schoolCode}');
      await prefs.remove('subjects_${widget.schoolCode}');

      // Load teachers first, then subjects
      await _loadTeachers();
      await _loadSubjects();

      _showMessage('Data refreshed successfully', false);
    } catch (e) {
      _showMessage('Error refreshing data: ${e.toString()}', true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isSubjectIdValid(String id) {
    return id.length == 4 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id);
  }

  bool _isSubjectIdUnique(String id) {
    if (_editingSubject != null && _editingSubject!['subject_id'] == id) {
      return true;
    }
    return !_subjects.any((subject) => subject['subject_id'] == id);
  }

  bool _isSubjectNameUnique(String name) {
    if (_editingSubject != null && _editingSubject!['subject_name'] == name) {
      return true;
    }
    return !_subjects.any((subject) => subject['subject_name'] == name);
  }

  void _showAddSubjectDialog() {
    _subjectIdController.clear();
    _subjectNameController.clear();
    _selectedTeacherIds.clear();
    _editingSubject = null;
    _clearMessages();

    showDialog(
      context: context,
      builder: (context) => _SubjectDialog(
        subjectIdController: _subjectIdController,
        subjectNameController: _subjectNameController,
        teachers: _teachers,
        selectedTeacherIds: _selectedTeacherIds,
        editingSubject: _editingSubject,
        onSave: _saveSubject,
        onTeachersUpdated: (List<String> updatedTeacherIds) {
          setState(() {
            _selectedTeacherIds = updatedTeacherIds;
          });
        },
        isDesktop: _isDesktop,
      ),
    ).then((_) {
      if (!_isSaving) {
        _selectedTeacherIds.clear();
      }
    });
  }

  void _showEditSubjectDialog(Map<String, dynamic> subject) {
    _subjectIdController.text = subject['subject_id']?.toString() ?? '';
    _subjectNameController.text = subject['subject_name']?.toString() ?? '';
    _selectedTeacherIds = List<String>.from(subject['teacher_ids'] ?? []);
    _editingSubject = subject;
    _clearMessages();

    showDialog(
      context: context,
      builder: (context) => _SubjectDialog(
        subjectIdController: _subjectIdController,
        subjectNameController: _subjectNameController,
        teachers: _teachers,
        selectedTeacherIds: _selectedTeacherIds,
        editingSubject: _editingSubject,
        onSave: _saveSubject,
        onTeachersUpdated: (List<String> updatedTeacherIds) {
          setState(() {
            _selectedTeacherIds = updatedTeacherIds;
          });
        },
        isDesktop: _isDesktop,
      ),
    );
  }

  Future<void> _saveSubject() async {
    final subjectId = _subjectIdController.text.trim().toUpperCase();
    final subjectName = _subjectNameController.text.trim();

    // Validation
    if (subjectId.isEmpty || subjectName.isEmpty) {
      _showMessage('Please fill in all required fields', true);
      return;
    }

    if (!_isSubjectIdValid(subjectId)) {
      _showMessage(
        'Subject ID must be exactly 4 characters (letters or numbers)',
        true,
      );
      return;
    }

    if (!_isSubjectIdUnique(subjectId)) {
      _showMessage('Subject ID already exists', true);
      return;
    }

    if (!_isSubjectNameUnique(subjectName)) {
      _showMessage('Subject name already exists', true);
      return;
    }

    if (_selectedTeacherIds.isEmpty) {
      _showMessage('Please select at least one teacher', true);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Get teacher names with null safety
      final selectedTeacherNames = _teachers
          .where((teacher) => _selectedTeacherIds.contains(teacher['id']))
          .map(
            (teacher) => teacher['username']?.toString() ?? 'Unknown Teacher',
          )
          .toList();

      final subjectData = {
        'subject_id': subjectId,
        'subject_name': subjectName,
        'teacher_ids': _selectedTeacherIds,
        'teacher_names': selectedTeacherNames,
        'school_code': widget.schoolCode,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (_editingSubject != null) {
        // Update existing subject
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('subjects')
            .doc(_editingSubject!['id'])
            .update(subjectData);
      } else {
        // Add new subject
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('subjects')
            .add(subjectData);
      }

      // Invalidate cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('subjects_${widget.schoolCode}');

      _showMessage(
        _editingSubject != null
            ? 'Subject updated successfully'
            : 'Subject added successfully',
        false,
      );

      _loadSubjects();
      if (mounted) {
        Navigator.pop(context);
      }

      _selectedTeacherIds.clear();
    } catch (e) {
      _showMessage('Error saving subject: ${e.toString()}', true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteSubject(String subjectId, String subjectName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Subject'),
        content: Text('Are you sure you want to delete "$subjectName"?'),
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
            .collection('subjects')
            .doc(subjectId)
            .delete();

        // Invalidate cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('subjects_${widget.schoolCode}');

        _showMessage('Subject deleted successfully', false);
        _loadSubjects();
      } catch (e) {
        _showMessage('Error deleting subject: ${e.toString()}', true);
      }
    }
  }

  Widget _buildSubjectList() {
    if (_subjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subject, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No subjects found',
              style: TextStyle(
                fontSize: _isDesktop ? 20 : 18,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Click the + button to add your first subject',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: _isDesktop ? 14 : 12,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        itemCount: _subjects.length,
        itemBuilder: (context, index) {
          final subject = _subjects[index];

          // Build teacher display names with proper fallbacks
          List<String> teacherDisplayNames = [];
          final teacherIds = List<String>.from(subject['teacher_ids'] ?? []);

          for (String teacherId in teacherIds) {
            try {
              var teacher = _teachers.firstWhere((t) => t['id'] == teacherId);
              // Use full_name if available and not empty, otherwise use username
              String fullName = teacher['full_name']?.toString() ?? '';
              String username =
                  teacher['username']?.toString() ?? 'Unknown Teacher';
              String displayName = fullName.isNotEmpty && fullName != 'No Name'
                  ? fullName
                  : username;
              teacherDisplayNames.add(displayName);
            } catch (e) {
              // If teacher not found in _teachers list, try to use stored teacher_names
              if (subject['teacher_names'] is List &&
                  (subject['teacher_names'] as List).isNotEmpty) {
                // Find the corresponding username in teacher_names
                int teacherIndex = teacherIds.indexOf(teacherId);
                if (teacherIndex >= 0 &&
                    teacherIndex < (subject['teacher_names'] as List).length) {
                  teacherDisplayNames.add(
                    (subject['teacher_names'] as List)[teacherIndex].toString(),
                  );
                } else {
                  teacherDisplayNames.add('Unknown Teacher');
                }
              } else {
                teacherDisplayNames.add('Unknown Teacher');
              }
            }
          }

          // If we couldn't build any display names, fallback to stored teacher_names
          if (teacherDisplayNames.isEmpty && subject['teacher_names'] is List) {
            teacherDisplayNames = List<String>.from(
              subject['teacher_names'] as List,
            );
          }

          return Card(
            margin: EdgeInsets.symmetric(
              horizontal: _isDesktop ? 12 : 8,
              vertical: _isDesktop ? 6 : 4,
            ),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.brown[100],
                child: Text(
                  (subject['subject_id']?.toString() ?? '??').substring(0, 2),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.brown[800],
                  ),
                ),
              ),
              title: Text(
                subject['subject_name']?.toString() ?? 'Unknown Subject',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: _isDesktop ? 16 : 14,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID: ${subject['subject_id']}',
                    style: TextStyle(fontSize: _isDesktop ? 14 : 12),
                  ),
                  if (teacherDisplayNames.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        Icon(Icons.people, size: 12, color: Colors.grey[600]),
                        Text(
                          'Teachers: ${teacherDisplayNames.join(', ')}',
                          style: TextStyle(
                            fontSize: _isDesktop ? 12 : 10,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.edit,
                      color: Colors.blue,
                      size: _isDesktop ? 24 : 20,
                    ),
                    onPressed: () => _showEditSubjectDialog(subject),
                    tooltip: 'Edit subject',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete,
                      color: Colors.red,
                      size: _isDesktop ? 24 : 20,
                    ),
                    onPressed: () =>
                        _deleteSubject(subject['id'], subject['subject_name']),
                    tooltip: 'Delete subject',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Desktop sidebar info section
  Widget _buildDesktopSidebarInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.brown[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.brown[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📖 Subject Management Tips',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.brown[700],
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoTip('Create subjects with unique 4-character IDs'),
          _buildInfoTip(
            'Assign teachers to each subject for better organization',
          ),
          _buildInfoTip(
            'Subject IDs should be meaningful and easy to remember',
          ),
          _buildInfoTip('You can assign multiple teachers to a single subject'),
          _buildInfoTip('Subjects can be edited or removed anytime'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[100]!),
            ),
            child: Text(
              'Need help? Contact your system administrator for assistance.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
                fontStyle: FontStyle.italic,
              ),
            ),
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
          Icon(Icons.circle, size: 6, color: Colors.brown[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.brown[600]),
            ),
          ),
        ],
      ),
    );
  }

  // Desktop sidebar
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
                    backgroundColor: Colors.brown[100],
                    child: Icon(
                      Icons.subject,
                      size: 40,
                      color: Colors.brown[700],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Manage Subjects',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.brown[700],
                    ),
                  ),
                  const SizedBox(height: 4),
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
            icon: Icon(Icons.arrow_back, color: Colors.brown[700]),
            onPressed: () {
              Navigator.of(context).pop();
            },
            tooltip: 'Back to Dashboard',
          ),
          Text(
            'Subject Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.brown[700],
            ),
          ),
          const Spacer(),
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.refresh, color: Colors.brown[700]),
            onPressed: _isLoading ? null : _refreshData,
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
        _isMobile ? 'Subjects' : 'Manage Subjects - ${widget.schoolName}',
        style: TextStyle(fontSize: _isMobile ? 18 : 20),
      ),
      backgroundColor: Colors.brown[700],
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          onPressed: _isLoading ? null : _refreshData,
          tooltip: 'Refresh Data',
        ),
      ],
    );
  }

  // Message container
  Widget _buildMessageContainer(
    String message,
    Color backgroundColor,
    IconData icon,
    Color iconColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: iconColor.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: iconColor),
            onPressed: _clearMessages,
          ),
        ],
      ),
    );
  }

  // Main content for all layouts
  Widget _buildMainContent() {
    return Padding(
      padding: EdgeInsets.all(_isDesktop ? 24 : 16),
      child: Column(
        children: [
          // Error and Success Messages
          if (_errorMessage != null)
            _buildMessageContainer(
              _errorMessage!,
              Colors.red[50]!,
              Icons.error,
              Colors.red,
            ),
          if (_successMessage != null)
            _buildMessageContainer(
              _successMessage!,
              Colors.green[50]!,
              Icons.check_circle,
              Colors.green,
            ),

          // Statistics
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: EdgeInsets.all(_isDesktop ? 24 : 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'Total Subjects',
                    _subjects.length.toString(),
                    Icons.subject,
                    Colors.brown,
                  ),
                  _buildStatItem(
                    'Available Teachers',
                    _teachers.length.toString(),
                    Icons.people,
                    Colors.blue,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Subjects List
          Expanded(child: _buildSubjectList()),
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
          width: _isDesktop ? 70 : 60,
          height: _isDesktop ? 70 : 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: _isDesktop ? 36 : 32, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: _isDesktop ? 24 : 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: _isDesktop ? 14 : 12, color: Colors.grey),
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
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildMainContent(),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddSubjectDialog,
          backgroundColor: Colors.brown[700],
          tooltip: 'Add New Subject',
          child: const Icon(Icons.add, color: Colors.white),
        ),
      );
    } else {
      return Scaffold(
        appBar: _buildAppBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildMainContent(),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddSubjectDialog,
          backgroundColor: Colors.brown[700],
          tooltip: 'Add New Subject',
          child: const Icon(Icons.add, color: Colors.white),
        ),
      );
    }
  }
}

class _SubjectDialog extends StatefulWidget {
  final TextEditingController subjectIdController;
  final TextEditingController subjectNameController;
  final List<Map<String, dynamic>> teachers;
  final List<String> selectedTeacherIds;
  final Map<String, dynamic>? editingSubject;
  final Future<void> Function() onSave;
  final Function(List<String>) onTeachersUpdated;
  final bool isDesktop;

  const _SubjectDialog({
    required this.subjectIdController,
    required this.subjectNameController,
    required this.teachers,
    required this.selectedTeacherIds,
    required this.editingSubject,
    required this.onSave,
    required this.onTeachersUpdated,
    required this.isDesktop,
  });

  @override
  State<_SubjectDialog> createState() => __SubjectDialogState();
}

class __SubjectDialogState extends State<_SubjectDialog> {
  late List<String> _currentSelectedTeacherIds;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentSelectedTeacherIds = List.from(widget.selectedTeacherIds);
  }

  void _removeTeacher(String teacherId) {
    setState(() {
      _currentSelectedTeacherIds.remove(teacherId);
    });
    widget.onTeachersUpdated(_currentSelectedTeacherIds);
  }

  void _showTeacherSelectionDialog() {
    List<String> tempSelectedTeacherIds = List.from(_currentSelectedTeacherIds);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: widget.isDesktop ? 500 : double.maxFinite,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.people, color: Colors.brown[700], size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Select Teachers',
                            style: TextStyle(
                              fontSize: widget.isDesktop ? 20 : 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (widget.teachers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No teachers available',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    else
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: widget.isDesktop ? 400 : 300,
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: widget.teachers.length,
                            itemBuilder: (context, index) {
                              final teacher = widget.teachers[index];
                              final isSelected = tempSelectedTeacherIds
                                  .contains(teacher['id']);

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 0,
                                ),
                                child: CheckboxListTile(
                                  title: Text(
                                    teacher['display_name']?.toString() ??
                                        'Unknown Teacher',
                                    style: TextStyle(
                                      fontSize: widget.isDesktop ? 16 : 14,
                                    ),
                                  ),
                                  value: isSelected,
                                  onChanged: (selected) {
                                    setDialogState(() {
                                      if (selected == true) {
                                        tempSelectedTeacherIds.add(
                                          teacher['id'],
                                        );
                                      } else {
                                        tempSelectedTeacherIds.remove(
                                          teacher['id'],
                                        );
                                      }
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.grey[400]!),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _currentSelectedTeacherIds = List.from(
                                  tempSelectedTeacherIds,
                                );
                              });
                              widget.onTeachersUpdated(
                                _currentSelectedTeacherIds,
                              );
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.brown[700],
                            ),
                            child: const Text(
                              'Done',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: widget.isDesktop ? 500 : double.maxFinite,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.subject, color: Colors.brown[700], size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.editingSubject != null
                        ? 'Edit Subject'
                        : 'Add New Subject',
                    style: TextStyle(
                      fontSize: widget.isDesktop ? 20 : 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: widget.subjectIdController,
                      decoration: const InputDecoration(
                        labelText: 'Subject ID *',
                        hintText: '4 characters (e.g., MATH, SCI1)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLength: 4,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: widget.subjectNameController,
                      decoration: const InputDecoration(
                        labelText: 'Subject Name *',
                        hintText: 'Enter subject name',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildTeacherSelection(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () async {
                            setState(() {
                              _isSaving = true;
                            });
                            await widget.onSave();
                            if (mounted) {
                              setState(() {
                                _isSaving = false;
                              });
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.brown[700],
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
                            widget.editingSubject != null ? 'Update' : 'Save',
                            style: const TextStyle(color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assign Teachers *',
          style: TextStyle(
            fontSize: widget.isDesktop ? 16 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[400]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              if (_currentSelectedTeacherIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _currentSelectedTeacherIds.map((teacherId) {
                      Map<String, dynamic>? foundTeacher;
                      try {
                        foundTeacher = widget.teachers.firstWhere(
                          (t) => t['id'] == teacherId,
                        );
                      } catch (e) {
                        foundTeacher = null;
                      }

                      final teacher =
                          foundTeacher ??
                          <String, dynamic>{
                            'display_name': 'Unknown Teacher',
                            'username': 'Unknown',
                          };
                      return Chip(
                        label: Text(
                          teacher['display_name']?.toString() ??
                              'Unknown Teacher',
                          style: TextStyle(
                            fontSize: widget.isDesktop ? 14 : 12,
                          ),
                        ),
                        onDeleted: () => _removeTeacher(teacherId),
                        deleteIcon: const Icon(Icons.close, size: 16),
                      );
                    }).toList(),
                  ),
                ),
              ListTile(
                title: Text(
                  'Select Teachers',
                  style: TextStyle(fontSize: widget.isDesktop ? 16 : 14),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showTeacherSelectionDialog,
                  tooltip: 'Add Teachers',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Selected: ${_currentSelectedTeacherIds.length} teacher(s)',
          style: TextStyle(
            fontSize: widget.isDesktop ? 14 : 12,
            color: _currentSelectedTeacherIds.isEmpty
                ? Colors.red
                : Colors.grey[600],
            fontWeight: _currentSelectedTeacherIds.isEmpty
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
        if (_currentSelectedTeacherIds.isEmpty)
          Text(
            'Please select at least one teacher',
            style: TextStyle(
              fontSize: widget.isDesktop ? 12 : 11,
              color: Colors.red,
            ),
          ),
      ],
    );
  }
}
