import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminManageUsersScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;

  const AdminManageUsersScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<AdminManageUsersScreen> createState() => _AdminManageUsersScreenState();
}

class _AdminManageUsersScreenState extends State<AdminManageUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedRoleFilter = 'all';
  String _selectedClassFilter = 'all';
  String _selectedSectionFilter = 'all';
  String _selectedSubjectFilter = 'all';

  // Cache variables
  List<Map<String, dynamic>> _cachedUsers = [];
  DateTime? _lastFetchTime;
  static const int CACHE_DURATION_MINUTES = 10;
  // Add this with your other variables
  List<Map<String, dynamic>> _subjectDocuments = [];

  // Statistics cache
  Map<String, int> _cachedStats = {};
  bool _isLoading = false;
  bool _initialLoadCompleted = false;

  // Filter options
  List<String> _availableClasses = ['all'];
  List<String> _availableSections = ['all'];
  List<String> _availableSubjects = ['all'];

  // Firebase Cloud Functions instance
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Bulk selection variables
  bool _isSelecting = false;
  Set<String> _selectedUserIds = <String>{};
  bool _isBulkDeleting = false;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // Sidebar and filter visibility
  bool _showDesktopFilters = false; // Changed to false by default
  bool _showMobileFilters = false;

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
    _loadCachedData().then((_) {
      if (mounted) {
        setState(() {
          _initialLoadCompleted = true;
        });
      }
    });
    _loadSubjectsFromCollection(); // Load subjects immediately
  }

  @override
  void dispose() {
    _searchController.dispose();
    _infoPageController.dispose();
    super.dispose();
  }

  // Cache methods
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

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUsersJson = prefs.getString(
        'cached_users_${widget.schoolCode}',
      );
      if (cachedUsersJson != null && cachedUsersJson.isNotEmpty) {
        final Map<String, dynamic> usersData = json.decode(cachedUsersJson);
        final List<dynamic> usersList = usersData['users'] ?? [];
        _cachedUsers = usersList.map((user) {
          return _convertFromCacheSafe(Map<String, dynamic>.from(user));
        }).toList();
        _updateFilterOptions();
      }

      final lastFetchMillis = prefs.getInt(
        'last_fetch_time_${widget.schoolCode}',
      );
      if (lastFetchMillis != null) {
        _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(lastFetchMillis);
      }

      final cachedStatsJson = prefs.getString(
        'cached_stats_${widget.schoolCode}',
      );
      if (cachedStatsJson != null) {
        _cachedStats = Map<String, int>.from(json.decode(cachedStatsJson));
      }

      if (mounted) setState(() {});
    } catch (e) {
      print('Error loading cached data: $e');
    }
  }

  void _updateFilterOptions() {
    final classes = <String>{};
    final sections = <String>{};
    final subjects = <String>{};

    for (final user in _cachedUsers) {
      final role = user['role']?.toString() ?? '';

      if (role == 'student') {
        final classGrade =
            user['class_grade']?.toString() ??
            user['class_name']?.toString() ??
            user['class']?.toString();
        if (classGrade != null &&
            classGrade.isNotEmpty &&
            classGrade != 'null') {
          classes.add(classGrade);
        }

        final section = user['section']?.toString();
        if (section != null && section.isNotEmpty && section != 'null') {
          sections.add(section);
        }
      } else if (role == 'teacher') {
        final subject =
            user['subject']?.toString() ??
            user['subjects']?.toString() ??
            user['teacher_subject']?.toString() ??
            user['teaching_subject']?.toString();

        if (subject != null && subject.isNotEmpty && subject != 'null') {
          subjects.add(subject);
        }
      }
    }

    setState(() {
      _availableClasses = ['all', ...classes.toList()..sort()];
      _availableSections = ['all', ...sections.toList()..sort()];
      // Don't override subjects if we already loaded from collection
      if (_availableSubjects.length <= 1) {
        _availableSubjects = ['all', ...subjects.toList()..sort()];
      }
    });
  }

  Future<void> _saveToCache(
    List<Map<String, dynamic>> users,
    Map<String, int> stats,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      final cacheSafeUsers = users
          .map((user) => _convertToCacheSafe(user))
          .toList();
      final usersMap = {'users': cacheSafeUsers};

      await prefs.setString(
        'cached_users_${widget.schoolCode}',
        json.encode(usersMap),
      );
      await prefs.setInt(
        'last_fetch_time_${widget.schoolCode}',
        now.millisecondsSinceEpoch,
      );
      await prefs.setString(
        'cached_stats_${widget.schoolCode}',
        json.encode(stats),
      );

      _cachedUsers = users;
      _cachedStats = stats;
      _lastFetchTime = now;
      _initialLoadCompleted = true;
      _updateFilterOptions();
    } catch (e) {
      print('Error saving to cache: $e');
    }
  }

  bool get _isCacheValid {
    if (_lastFetchTime == null) return false;
    if (_cachedUsers.isEmpty) return false;

    final difference = DateTime.now().difference(_lastFetchTime!);
    return difference.inMinutes < CACHE_DURATION_MINUTES;
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final users = await _fetchUsersFromFirestore();
      final stats = await _fetchStatisticsFromFirestore();
      await _saveToCache(users, stats);

      // FIXED: Force reload subjects collection to get latest teacher assignments
      await _loadSubjectsFromCollection();

      // FIXED: Clear and update the cached users immediately
      setState(() {
        _cachedUsers = users;
        _cachedStats = stats;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Data refreshed successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.fixed,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      print('Error refreshing data: $e');
      // Fallback to local calculation if Firestore fails
      final users = await _fetchUsersFromFirestore();
      final stats = _calculateStatistics(users);
      await _saveToCache(users, stats);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Error refreshing data: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.fixed,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Load subjects from Firestore subjects collection with teacher assignments
  Future<void> _loadSubjectsFromCollection() async {
    try {
      print('Loading subjects with teacher assignments...');

      final subjectsSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('subjects')
          .get();

      final subjectsFromCollection = <String>{};
      _subjectDocuments = []; // Clear existing

      for (final doc in subjectsSnapshot.docs) {
        final data = doc.data();
        final subjectName = data['subject_name']?.toString();
        final teacherIds = List<String>.from(data['teacher_ids'] ?? []);
        final teacherNames = List<String>.from(data['teacher_names'] ?? []);

        if (subjectName != null && subjectName.isNotEmpty) {
          subjectsFromCollection.add(subjectName);
          _subjectDocuments.add({
            'subject_name': subjectName,
            'teacher_ids': teacherIds,
            'teacher_names': teacherNames,
            'id': doc.id,
          });

          // Debug print
          print('📚 Subject: $subjectName');
          print('   Teacher IDs: $teacherIds');
          print('   Teacher Names: $teacherNames');
        }
      }

      if (subjectsFromCollection.isNotEmpty) {
        setState(() {
          _availableSubjects = [
            'all',
            ...subjectsFromCollection.toList()..sort(),
          ];
        });
        print(
          '✅ Loaded ${subjectsFromCollection.length} subjects from collection',
        );
        print('Available subjects: $_availableSubjects');
      } else {
        print('⚠️ No subjects found in collection');
      }
    } catch (e) {
      print('❌ Error loading subjects from collection: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUsersFromFirestore() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {'id': doc.id, ...data};
      }).toList();
    } catch (e) {
      print('Error fetching users: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> get _users async {
    if (!_isCacheValid && !_isLoading && mounted) {
      await _refreshDataInBackground();
    }
    return _cachedUsers;
  }

  Future<void> _refreshDataInBackground() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final users = await _fetchUsersFromFirestore();
      // FIXED: Use Firestore stats instead of local calculation
      final stats = await _fetchStatisticsFromFirestore();
      await _saveToCache(users, stats);
    } catch (e) {
      print('Error refreshing data in background: $e');
      // Fallback to local calculation
      final users = await _fetchUsersFromFirestore();
      final stats = _calculateStatistics(users);
      await _saveToCache(users, stats);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Map<String, int> _calculateStatistics(List<Map<String, dynamic>> users) {
    final totalUsers = users.length;
    final students = users.where((user) => user['role'] == 'student').length;
    final teachers = users.where((user) => user['role'] == 'teacher').length;
    return {'total': totalUsers, 'students': students, 'teachers': teachers};
  }

  // NEW: Fetch statistics from Firestore
  Future<Map<String, int>> _fetchStatisticsFromFirestore() async {
    try {
      final schoolDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .get();

      if (schoolDoc.exists) {
        final data = schoolDoc.data()!;
        final studentCount = data['student_count'] ?? 0;
        final teacherCount = data['teacher_count'] ?? 0;
        final adminCount = data['admin_count'] ?? 0;

        return {
          'total': studentCount + teacherCount + adminCount,
          'students': studentCount,
          'teachers': teacherCount,
        };
      }
      return {'total': 0, 'students': 0, 'teachers': 0};
    } catch (e) {
      print('Error fetching statistics from Firestore: $e');
      // Fallback to counting from cached users
      return _calculateStatistics(_cachedUsers);
    }
  }

  // Bulk selection methods
  void _toggleSelectionMode() {
    setState(() {
      _isSelecting = !_isSelecting;
      if (!_isSelecting) {
        _selectedUserIds.clear();
      }
    });
  }

  void _toggleUserSelection(String userId, bool selected) {
    setState(() {
      if (selected) {
        _selectedUserIds.add(userId);
      } else {
        _selectedUserIds.remove(userId);
      }
    });
  }

  void _selectAllUsers() {
    try {
      final filteredUsers = _getFilteredUsers();

      // Extract valid user IDs safely
      final validUserIds = <String>{};

      for (final user in filteredUsers) {
        final userId = user['id']?.toString();
        if (userId != null && userId.isNotEmpty && userId != 'null') {
          validUserIds.add(userId);
        }
      }

      setState(() {
        _selectedUserIds = validUserIds;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selected ${validUserIds.length} filtered users',
              style: const TextStyle(fontSize: 14),
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error selecting all users: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting users: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredUsers() {
    // Add null/empty check at the start
    if (_cachedUsers.isEmpty) return [];

    List<Map<String, dynamic>> users = [..._cachedUsers]; // Create a copy

    try {
      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        users = users.where((user) {
          try {
            final username = user['username']?.toString().toLowerCase() ?? '';
            final fullName = user['full_name']?.toString().toLowerCase() ?? '';
            final email = user['gmail']?.toString().toLowerCase() ?? '';
            final mobile =
                user['mobile_number']?.toString().toLowerCase() ?? '';

            return username.contains(_searchQuery) ||
                fullName.contains(_searchQuery) ||
                email.contains(_searchQuery) ||
                mobile.contains(_searchQuery);
          } catch (e) {
            print('Error filtering user by search: $e');
            return false;
          }
        }).toList();
      }

      // Apply role filter
      if (_selectedRoleFilter != 'all') {
        users = users.where((user) {
          try {
            final role = user['role']?.toString() ?? '';
            return role == _selectedRoleFilter;
          } catch (e) {
            print('Error filtering by role: $e');
            return false;
          }
        }).toList();
      }

      // Apply class filter for students
      if (_selectedClassFilter != 'all') {
        users = users.where((user) {
          try {
            final role = user['role']?.toString() ?? '';
            if (role == 'student') {
              final classGrade =
                  user['class_grade']?.toString() ??
                  user['class_name']?.toString() ??
                  user['class']?.toString() ??
                  '';
              return classGrade == _selectedClassFilter;
            }
            return _selectedRoleFilter == 'all';
          } catch (e) {
            print('Error filtering by class: $e');
            return false;
          }
        }).toList();
      }

      // Apply section filter for students
      if (_selectedSectionFilter != 'all') {
        users = users.where((user) {
          try {
            final role = user['role']?.toString() ?? '';
            if (role == 'student') {
              final section = user['section']?.toString() ?? '';
              return section == _selectedSectionFilter;
            }
            return _selectedRoleFilter == 'all';
          } catch (e) {
            print('Error filtering by section: $e');
            return false;
          }
        }).toList();
      }

      // Apply subject filter for teachers
      if (_selectedSubjectFilter != 'all') {
        users = users.where((user) {
          try {
            final role = user['role']?.toString() ?? '';
            final userId = user['id']?.toString() ?? '';

            if (role == 'teacher') {
              bool isAssignedToSubject = _subjectDocuments.any((subject) {
                final subjectName = subject['subject_name']?.toString() ?? '';
                final teacherIds = List<String>.from(
                  subject['teacher_ids'] ?? [],
                );

                final subjectMatches =
                    subjectName.toLowerCase() ==
                    _selectedSubjectFilter.toLowerCase();
                final teacherAssigned = teacherIds.contains(userId);

                return subjectMatches && teacherAssigned;
              });

              return isAssignedToSubject;
            }
            return _selectedRoleFilter == 'all';
          } catch (e) {
            print('Error filtering by subject: $e');
            return false;
          }
        }).toList();
      }

      // Filter out admin users from display
      users = users.where((user) {
        try {
          final role = user['role']?.toString() ?? '';
          return role != 'admin' && role != 'super_admin';
        } catch (e) {
          print('Error filtering admin users: $e');
          return true; // Keep by default if error
        }
      }).toList();

      return users;
    } catch (e) {
      print('Error in _getFilteredUsers: $e');
      return [];
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedUserIds.clear();
    });
  }

  Future<void> _bulkDeleteUsers() async {
    if (_selectedUserIds.isEmpty) return;

    final selectedCount = _selectedUserIds.length;

    // Modern confirmation dialog
    final isMobileDialog = MediaQuery.of(context).size.width < 600;

    final confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isMobileDialog
                ? MediaQuery.of(context).size.width * 0.9
                : 500,
            maxHeight: 400,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modern Header with gradient
              Container(
                height: 70,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red[700]!, Colors.red[500]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      top: -20,
                      child: Icon(
                        Icons.delete_outline,
                        size: 100,
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.delete_forever,
                              color: Colors.red[700],
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Bulk Delete',
                            style: TextStyle(
                              fontSize: isMobileDialog ? 22 : 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isMobileDialog ? 20 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Count Display
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.red[100]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    selectedCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Users Selected',
                                style: TextStyle(
                                  fontSize: isMobileDialog ? 16 : 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Warning Message
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_rounded,
                              color: Colors.orange[700],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'This action cannot be undone',
                                    style: TextStyle(
                                      fontSize: isMobileDialog ? 15 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[800],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Selected users will be permanently deleted from both database and authentication system.',
                                    style: TextStyle(
                                      fontSize: isMobileDialog ? 13 : 14,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // Modern Action Buttons
              Container(
                padding: EdgeInsets.all(isMobileDialog ? 16 : 20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.grey[700],
                          elevation: 0,
                          padding: EdgeInsets.symmetric(
                            vertical: isMobileDialog ? 14 : 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: isMobileDialog ? 16 : 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[600],
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: EdgeInsets.symmetric(
                            vertical: isMobileDialog ? 14 : 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          shadowColor: Colors.red.withOpacity(0.3),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete, size: isMobileDialog ? 18 : 20),
                            const SizedBox(width: 8),
                            Text(
                              'Delete All',
                              style: TextStyle(
                                fontSize: isMobileDialog ? 16 : 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
      ),
    );

    if (confirmDelete != true) return;

    setState(() {
      _isBulkDeleting = true;
    });

    // Enhanced progress dialog
    // Minimal progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320, maxHeight: 180),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFFDC2626),
                      ),
                      backgroundColor: const Color(0xFFFEE2E2),
                    ),
                    const Center(
                      child: Icon(
                        Icons.delete_outline,
                        color: Color(0xFFDC2626),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Deleting Users',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Processing $selectedCount users...',
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final callable = _functions.httpsCallable(
        'deleteUsersBulk',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
      );

      final result = await callable.call({
        'userIds': _selectedUserIds.toList(),
      });

      Navigator.pop(context); // Close progress dialog

      final response = Map<String, dynamic>.from(result.data);
      final results = (response['results'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final summary = Map<String, dynamic>.from(response['summary']);

      int successCount = summary['successful'] ?? 0;
      int errorCount = summary['failed'] ?? 0;
      int permissionErrors = summary['permissionErrors'] ?? 0;

      // Enhanced results analysis
      List<String> errorMessages = [];
      List<String> authPendingUsers = [];

      for (final result in results) {
        if (result['success'] != true) {
          errorMessages.add(
            '${result['userId']}: ${result['error'] ?? result['message']}',
          );
        } else if (result['authDeleted'] == false) {
          authPendingUsers.add(result['username'] ?? result['userId']);
        }
      }

      // Show enhanced results
      if (successCount > 0) {
        String successMessage = '✅ Successfully processed $successCount users';
        if (authPendingUsers.isNotEmpty) {
          successMessage +=
              ' (${authPendingUsers.length} with automatic Auth cleanup)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage, style: const TextStyle(fontSize: 14)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }

      if (errorCount > 0 && mounted) {
        _showQuotaAwareResults(
          successCount,
          errorCount,
          permissionErrors,
          errorMessages,
          authPendingUsers,
        );
      } else if (authPendingUsers.isNotEmpty && mounted) {
        // Show info about pending Auth cleanup
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ℹ️ ${authPendingUsers.length} users will be automatically cleaned from Auth',
              style: const TextStyle(fontSize: 14),
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }

      _clearSelection();
      _toggleSelectionMode();

      // Enhanced cache invalidation
      setState(() {
        _cachedUsers = [];
        _cachedStats = {};
        _lastFetchTime = null;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_users_${widget.schoolCode}');
      await prefs.remove('cached_stats_${widget.schoolCode}');
      await prefs.remove('last_fetch_time_${widget.schoolCode}');

      // Force immediate refresh
      await Future.delayed(const Duration(seconds: 2));
      await _refreshData();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) Navigator.pop(context);

      String errorMessage = 'Error during bulk delete';

      if (e.code == 'deadline-exceeded') {
        errorMessage =
            'Delete operation timed out. Some users may have been deleted. Please check the user list.';
      } else if (e.code == 'resource-exhausted') {
        errorMessage =
            'Quota limits exceeded. The system will automatically retry. Please try again in a few minutes.';
      } else if (e.code == 'permission-denied') {
        errorMessage = 'Permission denied. Please check your user permissions.';
      } else if (e.code == 'invalid-argument') {
        errorMessage =
            'Invalid request: ${e.message ?? 'Please check the selected users and try again.'}';
      } else {
        errorMessage = 'Error during bulk delete: ${e.message ?? e.toString()}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ $errorMessage',
            style: const TextStyle(fontSize: 14),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ Error during bulk delete: ${e.toString()}',
            style: const TextStyle(fontSize: 14),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBulkDeleting = false;
        });
      }
    }
  }

  void _showQuotaAwareResults(
    int successCount,
    int errorCount,
    int permissionErrors,
    List<String> errorMessages,
    List<String> authPendingUsers,
  ) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.all(isMobile ? 12 : 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isMobile ? MediaQuery.of(context).size.width - 24 : 500,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: errorCount > 0 ? Colors.orange[50] : Colors.green[50],
                  border: Border(
                    bottom: BorderSide(
                      color: errorCount > 0
                          ? Colors.orange[200]!
                          : Colors.green[200]!,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      errorCount > 0 ? Icons.warning : Icons.check_circle,
                      color: errorCount > 0 ? Colors.orange : Colors.green,
                      size: isMobile ? 20 : 24,
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bulk Delete Results',
                            style: TextStyle(
                              fontSize: isMobile ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              color: errorCount > 0
                                  ? Colors.orange[800]
                                  : Colors.green[800],
                            ),
                          ),
                          if (errorCount > 0)
                            Text(
                              '$errorCount users need attention',
                              style: TextStyle(
                                fontSize: isMobile ? 12 : 14,
                                color: Colors.orange[700],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content - Scrollable
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Section
                      Text(
                        'Summary:',
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      SizedBox(height: 12),

                      // Stats in row for mobile, column for very small screens
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final useColumnLayout = constraints.maxWidth < 300;

                          if (useColumnLayout) {
                            return Column(
                              children: [
                                _buildCompactResultCard(
                                  'Successful',
                                  '$successCount users',
                                  Colors.green,
                                  Icons.check_circle,
                                  isMobile,
                                ),
                                SizedBox(height: 8),
                                _buildCompactResultCard(
                                  'Need Attention',
                                  '$errorCount users',
                                  Colors.orange,
                                  Icons.warning,
                                  isMobile,
                                ),
                              ],
                            );
                          } else {
                            return Row(
                              children: [
                                Expanded(
                                  child: _buildCompactResultCard(
                                    'Successful',
                                    '$successCount users',
                                    Colors.green,
                                    Icons.check_circle,
                                    isMobile,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: _buildCompactResultCard(
                                    'Need Attention',
                                    '$errorCount users',
                                    Colors.orange,
                                    Icons.warning,
                                    isMobile,
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),

                      // Additional cards
                      if (authPendingUsers.isNotEmpty) ...[
                        SizedBox(height: 8),
                        _buildCompactResultCard(
                          'Auto-Cleanup',
                          '${authPendingUsers.length} users',
                          Colors.blue,
                          Icons.autorenew,
                          isMobile,
                        ),
                      ],

                      if (permissionErrors > 0) ...[
                        SizedBox(height: 8),
                        _buildCompactResultCard(
                          'Permission Errors',
                          '$permissionErrors users',
                          Colors.red,
                          Icons.block,
                          isMobile,
                        ),
                      ],

                      SizedBox(height: 16),

                      // Auto-cleanup info (only show if needed)
                      if (authPendingUsers.isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.all(isMobile ? 10 : 12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info,
                                    size: isMobile ? 14 : 16,
                                    color: Colors.blue,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Automatic Cleanup',
                                    style: TextStyle(
                                      fontSize: isMobile ? 12 : 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(
                                '${authPendingUsers.length} users will be automatically cleaned from Auth due to quota limits.',
                                style: TextStyle(
                                  fontSize: isMobile ? 11 : 12,
                                  color: Colors.blue[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                      ],

                      // Error Details (only show if there are errors)
                      if (errorMessages.isNotEmpty) ...[
                        Text(
                          'Users Needing Attention:',
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          constraints: BoxConstraints(
                            maxHeight: isMobile ? 150 : 200,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemCount: errorMessages.length,
                            itemBuilder: (context, index) => Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 8 : 12,
                                vertical: isMobile ? 6 : 8,
                              ),
                              decoration: BoxDecoration(
                                border: index > 0
                                    ? Border(
                                        top: BorderSide(
                                          color: Colors.grey[200]!,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.orange,
                                    size: isMobile ? 16 : 18,
                                  ),
                                  SizedBox(width: isMobile ? 8 : 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          errorMessages[index].split(':').first,
                                          style: TextStyle(
                                            fontSize: isMobile ? 12 : 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.orange[800],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (errorMessages[index].contains(':'))
                                          Text(
                                            errorMessages[index]
                                                .split(':')
                                                .sublist(1)
                                                .join(':')
                                                .trim(),
                                            style: TextStyle(
                                              fontSize: isMobile ? 11 : 12,
                                              color: Colors.grey[700],
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                      ],

                      // Recommendations (only show if there are errors)
                      if (errorCount > 0) ...[
                        Container(
                          padding: EdgeInsets.all(isMobile ? 10 : 12),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Next Steps:',
                                style: TextStyle(
                                  fontSize: isMobile ? 13 : 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[800],
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '• System will automatically retry failed operations\n'
                                '• Database is kept in consistent state\n'
                                '• Authentication cleanup happens automatically',
                                style: TextStyle(
                                  fontSize: isMobile ? 11 : 12,
                                  color: Colors.orange[800],
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

              // Close Button
              Container(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 12 : 14,
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method for compact result cards
  Widget _buildCompactResultCard(
    String title,
    String value,
    Color color,
    IconData icon,
    bool isMobile,
  ) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: isMobile ? 20 : 22),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 11 : 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 12 : 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Row(
      children: [
        Icon(icon, color: color, size: isSmallScreen ? 18 : 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // User Details Dialog
  void _showUserDetails(Map<String, dynamic> userData) {
    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: isDesktop
            ? const EdgeInsets.symmetric(horizontal: 100, vertical: 50)
            : const EdgeInsets.all(20),
        child: UserDetailsDialog(
          userData: userData,
          schoolCode: widget.schoolCode,
        ),
      ),
    );
  }

  // Reset Password Function
  Future<void> _resetUserPassword(
    String userId,
    String username,
    String role,
  ) async {
    if (role == 'admin' || role == 'super_admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot reset password for ${role.toUpperCase()} accounts',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool confirmReset = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: Colors.orange),
            SizedBox(width: 8),
            Text('Reset Password'),
          ],
        ),
        content: Text(
          'This will generate a new temporary password for "$username".\n\nThey will be forced to change it on next login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Reset Password',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );

    if (confirmReset != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Resetting password...'),
          ],
        ),
      ),
    );

    try {
      final result = await _functions.httpsCallable('resetUserPassword').call({
        'targetUid': userId,
        'username': username,
        'role': role,
      });

      final response = result.data;

      Navigator.pop(context);

      await showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: BoxConstraints(
              maxWidth: _isMobile
                  ? MediaQuery.of(context).size.width * 0.9
                  : 400,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 24),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Password Reset Successfully',
                        style: TextStyle(
                          fontSize: _isMobile ? 18 : 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),

                Text(
                  'Temporary Password for "$username":',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: _isMobile
                      ? _buildMobilePasswordLayout(
                          response['tempPassword'],
                          context,
                        )
                      : _buildDesktopPasswordLayout(
                          response['tempPassword'],
                          context,
                        ),
                ),

                SizedBox(height: 12),

                if (response['authEmail'] != null) ...[
                  Text(
                    'Auth Email: ${response['authEmail']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  SizedBox(height: 4),
                ],

                SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'User must change this temporary password on next login.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      Navigator.pop(context);

      String errorMessage = 'Error resetting password';
      if (e.toString().contains('permission-denied')) {
        errorMessage = 'You do not have permission to reset passwords';
      } else if (e.toString().contains('not-found')) {
        errorMessage =
            'User not found in authentication system.\n\n'
            'This user exists in the database but not in the authentication system. '
            'Please contact support or recreate the user account.';
      } else {
        errorMessage = 'Error: ${e.toString().replaceAll('Exception: ', '')}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Widget _buildMobilePasswordLayout(String tempPassword, BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: SelectableText(
            tempPassword,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: tempPassword));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy Password'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopPasswordLayout(
    String tempPassword,
    BuildContext context,
  ) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: SelectableText(
              tempPassword,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        Tooltip(
          message: 'Copy to clipboard',
          child: IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: tempPassword));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Delete User Function
  Future<void> _deleteUser(String userId, String username) async {
    bool confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Are you sure you want to delete user "$username"? This action will remove the user from both database and authentication system and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmDelete != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Deleting user...'),
          ],
        ),
      ),
    );

    try {
      final result = await _functions.httpsCallable('deleteUser').call({
        'userId': userId,
        'username': username,
      });

      final response = result.data;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message']),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_fetch_time_${widget.schoolCode}');
      await _refreshData();
    } catch (e) {
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting user: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _editUser(Map<String, dynamic> userData, String userId) {
    showDialog(
      context: context,
      builder: (context) => AdminEditUserDialog(
        userData: userData,
        userId: userId,
        schoolCode: widget.schoolCode,
        schoolName: widget.schoolName,
        onUserUpdated: _refreshData,
      ),
    );
  }

  // ========== RESPONSIVE UI METHODS ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isDesktop ? null : _buildAppBar(),
      body: _isDesktop ? _buildDesktopLayout() : _buildMobileTabletLayout(),
      floatingActionButton: _isSelecting && !_isDesktop
          ? _buildBulkActionButtons()
          : null,
    );
  }

  // FIXED: Improved AppBar for mobile
  AppBar _buildAppBar() {
    return AppBar(
      title: _isSelecting
          ? Text('Selected (${_selectedUserIds.length})')
          : Text('Manage Users'),
      backgroundColor: Colors.white,
      foregroundColor: const Color.fromARGB(255, 21, 101, 192),
      elevation: 0,
      actions: _buildAppBarActions(),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (_isSelecting) {
      return [
        if (_selectedUserIds.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _isBulkDeleting ? null : _bulkDeleteUsers,
            tooltip: 'Delete Selected',
          ),
        // FIXED: Select All button now uses filtered users
        IconButton(
          icon: const Icon(Icons.select_all),
          onPressed: _selectAllUsers, // This now uses the filtered version
          tooltip: 'Select All Filtered Users',
        ),
        // FIXED: Clear Selection button
        IconButton(
          icon: const Icon(Icons.clear_all),
          onPressed: _clearSelection,
          tooltip: 'Clear Selection',
        ),
        TextButton(
          onPressed: _toggleSelectionMode,
          child: const Text('Cancel', style: TextStyle(color: Colors.red)),
        ),
      ];
    } else {
      return [
        // Filter toggle button
        IconButton(
          icon: Icon(
            _showMobileFilters ? Icons.filter_alt_off : Icons.filter_alt,
          ),
          onPressed: () {
            setState(() {
              _showMobileFilters = !_showMobileFilters;
            });
          },
          tooltip: 'Toggle Filters',
        ),
        // Refresh button
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _isLoading ? null : _refreshData,
          tooltip: 'Refresh Data',
        ),
        // Selection mode button
        IconButton(
          icon: const Icon(Icons.checklist),
          onPressed: _toggleSelectionMode,
          tooltip: 'Select Users',
        ),
      ];
    }
  }

  // FIXED: Improved mobile/tablet layout without duplicates
  Widget _buildMobileTabletLayout() {
    return Column(
      children: [
        // Search Bar - Only show when not selecting
        if (!_isSelecting) ...[
          Container(
            padding: EdgeInsets.all(_isMobile ? 12 : 16),
            color: Colors.white,
            child: Row(children: [Expanded(child: _buildModernSearchBar())]),
          ),
          // Filters Section
          _buildMobileFilters(),
        ],

        // FIXED: Removed duplicate Selection Info Bar from here
        // FIXED: Removed duplicate User Statistics from here

        // User List (which contains the proper single instances)
        Expanded(child: _buildMainContent()),
      ],
    );
  }

  // FIXED: Completely rewritten mobile filters - No more overflow!
  Widget _buildMobileFilters() {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      height: _showMobileFilters ? (_isMobile ? 100 : 120) : 0,
      child: _showMobileFilters
          ? Container(
              width: double.infinity,
              padding: EdgeInsets.all(_isMobile ? 8 : 12),
              margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // FIXED: Removed duplicate header - using app bar button instead

                  // FIXED: Better responsive filter row
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableWidth = constraints.maxWidth;
                        final isVerySmallScreen = availableWidth < 350;

                        return ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            // Role Filter - Always show
                            Container(
                              margin: EdgeInsets.only(right: 8),
                              child: _buildResponsiveFilterDropdown(
                                value: _selectedRoleFilter,
                                options: ['all', 'teacher', 'student'],
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _selectedRoleFilter = newValue ?? 'all';
                                    _selectedClassFilter = 'all';
                                    _selectedSectionFilter = 'all';
                                    _selectedSubjectFilter = 'all';
                                  });
                                },
                                hintText: 'Role',
                                color: Colors.blue,
                                isMobile: true,
                                isVerySmall: isVerySmallScreen,
                              ),
                            ),

                            // Student Filters
                            if (_selectedRoleFilter == 'student') ...[
                              Container(
                                margin: EdgeInsets.only(right: 8),
                                child: _buildResponsiveFilterDropdown(
                                  value: _selectedClassFilter,
                                  options: _availableClasses,
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _selectedClassFilter = newValue ?? 'all';
                                    });
                                  },
                                  hintText: 'Class',
                                  color: Colors.green,
                                  isMobile: true,
                                  isVerySmall: isVerySmallScreen,
                                ),
                              ),
                              Container(
                                margin: EdgeInsets.only(right: 8),
                                child: _buildResponsiveFilterDropdown(
                                  value: _selectedSectionFilter,
                                  options: _availableSections,
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _selectedSectionFilter =
                                          newValue ?? 'all';
                                    });
                                  },
                                  hintText: 'Section',
                                  color: Colors.orange,
                                  isMobile: true,
                                  isVerySmall: isVerySmallScreen,
                                ),
                              ),
                            ],

                            // Teacher Filters
                            if (_selectedRoleFilter == 'teacher') ...[
                              Container(
                                margin: EdgeInsets.only(right: 8),
                                child: _buildResponsiveFilterDropdown(
                                  value: _selectedSubjectFilter,
                                  options: _availableSubjects,
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _selectedSubjectFilter =
                                          newValue ?? 'all';
                                    });
                                  },
                                  hintText: 'Subject',
                                  color: Colors.purple,
                                  isMobile: true,
                                  isVerySmall: isVerySmallScreen,
                                ),
                              ),
                            ],

                            // FIXED: Always show Clear Filters button
                            Container(
                              margin: EdgeInsets.only(right: 8),
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedRoleFilter = 'all';
                                    _selectedClassFilter = 'all';
                                    _selectedSectionFilter = 'all';
                                    _selectedSubjectFilter = 'all';
                                  });
                                },
                                icon: Icon(
                                  Icons.clear_all,
                                  size: isVerySmallScreen ? 14 : 16,
                                ),
                                label: Text(
                                  'Clear',
                                  style: TextStyle(
                                    fontSize: isVerySmallScreen ? 12 : 13,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isVerySmallScreen ? 8 : 12,
                                    vertical: isVerySmallScreen ? 6 : 8,
                                  ),
                                  side: BorderSide(color: Colors.red),
                                ),
                              ),
                            ),

                            // Add some extra space at the end for better scrolling
                            SizedBox(width: 8),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          : SizedBox.shrink(),
    );
  }

  // FIXED: New responsive filter dropdown for mobile
  Widget _buildResponsiveFilterDropdown({
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    required String hintText,
    required Color color,
    bool isMobile = false,
    bool isVerySmall = false,
  }) {
    final width = isVerySmall ? 100.0 : (isMobile ? 120.0 : 140.0);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down,
            color: color,
            size: isVerySmall ? 14 : 16,
          ),
          iconSize: isVerySmall ? 16 : 18,
          elevation: 4,
          style: TextStyle(
            color: Colors.grey[800],
            fontSize: isVerySmall ? 11 : 12,
            fontWeight: FontWeight.w500,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(6),
          onChanged: onChanged,
          items: [
            DropdownMenuItem(
              value: 'all',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isVerySmall ? 4 : 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.all_inclusive,
                      size: isVerySmall ? 10 : 12,
                      color: Colors.grey,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'All $hintText',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: isVerySmall ? 10 : 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...options.where((option) => option != 'all').map((option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isVerySmall ? 4 : 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: isVerySmall ? 4 : 6),
                      Expanded(
                        child: Text(
                          option.length > (isVerySmall ? 8 : 12)
                              ? '${option.substring(0, isVerySmall ? 6 : 10)}...'
                              : option,
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w500,
                            fontSize: isVerySmall ? 10 : 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildModernSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search users...',
          hintStyle: TextStyle(
            color: Colors.grey[600],
            fontSize: _isMobile ? 14 : 14,
          ),
          border: InputBorder.none,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: Colors.blue[700],
            size: _isMobile ? 20 : 18,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, size: _isMobile ? 18 : 16),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          contentPadding: EdgeInsets.symmetric(
            horizontal: _isMobile ? 16 : 12,
            vertical: _isMobile ? 12 : 10,
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }

  // Desktop Layout Methods
  Widget _buildDesktopLayout() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar - Fixed width
          SizedBox(width: 280, child: _buildDesktopSidebar()),

          // Filters - Fixed width
          _buildDesktopFilters(),

          // Main Content - Takes remaining space
          Expanded(
            child: Container(
              constraints: BoxConstraints(minWidth: 500),
              child: Column(
                children: [
                  // Top bar with LayoutBuilder for responsive constraints
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SizedBox(
                        width: constraints.maxWidth,
                        child: _buildDesktopTopBar(),
                      );
                    },
                  ),
                  Expanded(child: _buildMainContent()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    // Calculate statistics from filtered users, not cached stats
    final filteredUsers = _getFilteredUsers();
    final stats = _calculateStatistics(filteredUsers);

    return Container(
      width: 280,
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
                  Icons.people,
                  size: 40,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
                const SizedBox(height: 8),
                const Text(
                  'User Management',
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

          // Statistics Section - NOW SHOWS FILTERED STATS
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Filtered Statistics',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 21, 101, 192),
                      ),
                    ),
                    if (_selectedRoleFilter != 'all' ||
                        _selectedClassFilter != 'all' ||
                        _selectedSectionFilter != 'all' ||
                        _selectedSubjectFilter != 'all')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Filtered',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color.fromARGB(255, 21, 101, 192),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSidebarStatCard(
                      'Total',
                      stats['total'] ?? 0,
                      Colors.blue,
                      isFiltered:
                          _selectedRoleFilter != 'all' ||
                          _selectedClassFilter != 'all' ||
                          _selectedSectionFilter != 'all' ||
                          _selectedSubjectFilter != 'all',
                    ),
                    _buildSidebarStatCard(
                      'Students',
                      stats['students'] ?? 0,
                      Colors.green,
                      isFiltered:
                          _selectedRoleFilter == 'student' ||
                          _selectedClassFilter != 'all' ||
                          _selectedSectionFilter != 'all',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildSidebarStatCard(
                  'Teachers',
                  stats['teachers'] ?? 0,
                  Colors.orange,
                  isFiltered:
                      _selectedRoleFilter == 'teacher' ||
                      _selectedSubjectFilter != 'all',
                ),
                const SizedBox(height: 8),

                // Show active filters
                if (_selectedRoleFilter != 'all' ||
                    _selectedClassFilter != 'all' ||
                    _selectedSectionFilter != 'all' ||
                    _selectedSubjectFilter != 'all')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Filters:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (_selectedRoleFilter != 'all')
                              _buildFilterChip('Role: $_selectedRoleFilter'),
                            if (_selectedClassFilter != 'all')
                              _buildFilterChip('Class: $_selectedClassFilter'),
                            if (_selectedSectionFilter != 'all')
                              _buildFilterChip(
                                'Section: $_selectedSectionFilter',
                              ),
                            if (_selectedSubjectFilter != 'all')
                              _buildFilterChip(
                                'Subject: $_selectedSubjectFilter',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Filter Toggle Button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _showDesktopFilters = !_showDesktopFilters;
                  });
                },
                icon: Icon(
                  _showDesktopFilters ? Icons.filter_alt_off : Icons.filter_alt,
                  size: 16,
                ),
                label: Text(
                  _showDesktopFilters ? 'Hide Filters' : 'Show Filters',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),

          // Info Pages
          Expanded(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height - 400,
              ),
              child: PageView(
                controller: _infoPageController,
                onPageChanged: (page) {
                  setState(() {
                    _currentInfoPage = page;
                  });
                },
                children: [
                  SingleChildScrollView(child: _buildInfoPage1()),
                  SingleChildScrollView(child: _buildInfoPage2()),
                ],
              ),
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

  // Helper method for filter chips
  Widget _buildFilterChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color.fromARGB(255, 21, 101, 192),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoPage1() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How to Manage Users',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.search,
            'Search Users',
            'Use the search bar to find users by username or full name',
          ),
          _buildInfoItem(
            Icons.filter_list,
            'Filter by Role',
            'Filter users by role (teacher, student) to view specific groups',
          ),
          _buildInfoItem(
            Icons.class_,
            'Class & Section Filters',
            'Filter students by their class and section for better organization',
          ),
          _buildInfoItem(
            Icons.subject,
            'Subject Filters',
            'Filter teachers by the subjects they teach',
          ),
          _buildInfoItem(
            Icons.checklist,
            'Bulk Selection',
            'Select multiple users for bulk operations like deletion',
          ),
          _buildInfoItem(
            Icons.edit,
            'Edit User Details',
            'Click the edit button to update user information and roles',
          ),
          _buildInfoItem(
            Icons.lock_reset,
            'Reset Password',
            'Reset passwords for teachers and students. Generates temporary password.',
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
            'User Management Tips',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem('👥', 'Regularly review user accounts for accuracy'),
          _buildTipItem(
            '🔐',
            'Use password reset feature for users who forget their passwords',
          ),
          _buildTipItem(
            '🔍',
            'Use filters to quickly find specific user groups',
          ),
          _buildTipItem('📊', 'Monitor user statistics to track school growth'),
          _buildTipItem(
            '⚠️',
            'Always double-check before deleting user accounts',
          ),
          _buildTipItem(
            '🔄',
            'Refresh data periodically to ensure you have the latest information',
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
              'Need help? Contact your system administrator for assistance with user management.',
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

  // Updated sidebar stat card to show filtered state
  Widget _buildSidebarStatCard(
    String title,
    int count,
    Color color, {
    bool isFiltered = false,
  }) {
    final isWideCard = title == 'Teachers';

    return isWideCard
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(isFiltered ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withOpacity(isFiltered ? 0.5 : 0.3),
                width: isFiltered ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isFiltered) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.filter_alt, size: 14, color: color),
                ],
              ],
            ),
          )
        : Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(isFiltered ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: color.withOpacity(isFiltered ? 0.5 : 0.3),
                  width: isFiltered ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      if (isFiltered) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.filter_alt, size: 14, color: color),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
  }

  Widget _buildDesktopFilters() {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      width: _showDesktopFilters ? 220 : 0, // Reduced width
      margin: EdgeInsets.only(
        right: _showDesktopFilters ? 8 : 0, // Reduced margin
      ),
      child: _showDesktopFilters
          ? Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.filter_alt_rounded,
                          color: Colors.blue[700],
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Filters',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                        Spacer(),
                        IconButton(
                          icon: Icon(Icons.close, size: 16),
                          onPressed: () {
                            setState(() {
                              _showDesktopFilters = false;
                            });
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 12),

                    // Role Filter - Always show
                    Text(
                      'Role',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 6),
                    _buildFilterDropdown(
                      value: _selectedRoleFilter,
                      options: ['all', 'teacher', 'student'],
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedRoleFilter = newValue ?? 'all';
                          // Reset dependent filters when role changes
                          _selectedClassFilter = 'all';
                          _selectedSectionFilter = 'all';
                          _selectedSubjectFilter = 'all';
                        });
                      },
                      hintText: 'Roles',
                      color: Colors.blue,
                    ),
                    SizedBox(height: 12),

                    // FIXED: Only show role filter initially, then show specific filters based on role
                    if (_selectedRoleFilter == 'student') ...[
                      // Student filters
                      Text(
                        'Class',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 6),
                      _buildFilterDropdown(
                        value: _selectedClassFilter,
                        options: _availableClasses,
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedClassFilter = newValue ?? 'all';
                          });
                        },
                        hintText: 'Classes',
                        color: Colors.green,
                      ),
                      SizedBox(height: 12),

                      Text(
                        'Section',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 6),
                      _buildFilterDropdown(
                        value: _selectedSectionFilter,
                        options: _availableSections,
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedSectionFilter = newValue ?? 'all';
                          });
                        },
                        hintText: 'Sections',
                        color: Colors.orange,
                      ),
                      SizedBox(height: 12),
                    ],

                    if (_selectedRoleFilter == 'teacher') ...[
                      // Teacher filters
                      Text(
                        'Subject',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 6),
                      _buildFilterDropdown(
                        value: _selectedSubjectFilter,
                        options: _availableSubjects,
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedSubjectFilter = newValue ?? 'all';
                          });
                        },
                        hintText: 'Subjects',
                        color: Colors.purple,
                      ),
                      SizedBox(height: 12),
                    ],

                    // Clear Filters Button
                    if (_selectedRoleFilter != 'all' ||
                        _selectedClassFilter != 'all' ||
                        _selectedSectionFilter != 'all' ||
                        _selectedSubjectFilter != 'all')
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedRoleFilter = 'all';
                              _selectedClassFilter = 'all';
                              _selectedSectionFilter = 'all';
                              _selectedSubjectFilter = 'all';
                            });
                          },
                          icon: Icon(Icons.clear_all, size: 16),
                          label: Text('Clear Filters'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : SizedBox.shrink(),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    required String hintText,
    required Color color,
    double? width,
  }) {
    return Container(
      width: width ?? (_isMobile ? 140 : 160),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: color, size: 16),
          iconSize: 18,
          elevation: 4,
          style: TextStyle(
            color: Colors.grey[800],
            fontSize: _isMobile ? 11 : 12,
            fontWeight: FontWeight.w500,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(6),
          onChanged: onChanged,
          items: [
            DropdownMenuItem(
              value: 'all',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(Icons.all_inclusive, size: 12, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      'All $hintText',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: _isMobile ? 11 : 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...options.where((option) => option != 'all').map((option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          option,
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w500,
                            fontSize: _isMobile ? 11 : 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTopBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isWideScreen = availableWidth > 1000;

        return Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: Colors.white,
          child: Row(
            children: [
              // Left section - Back button and title
              Container(
                width: isWideScreen ? 280 : 220,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Color.fromARGB(255, 21, 101, 192),
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back to Dashboard',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isSelecting
                            ? 'Select Users (${_selectedUserIds.length})'
                            : 'User Management',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 21, 101, 192),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Middle section - Search bar (only when not selecting)
              if (!_isSelecting) ...[
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: isWideScreen ? 400 : 300,
                    ),
                    child: _buildCompactSearchBar(),
                  ),
                ),
                const SizedBox(width: 16),
              ] else ...[
                const Spacer(),
              ],

              // Right section - Action buttons
              Container(
                constraints: BoxConstraints(maxWidth: _isSelecting ? 180 : 140),
                child: _buildDesktopTopBarActions(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactSearchBar() {
    return Container(
      constraints: BoxConstraints(maxHeight: 40), // Added constraint
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search users...',
          hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
          border: InputBorder.none,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: Colors.blue[700],
            size: 18,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, size: 16),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          isDense: true,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }

  Widget _buildDesktopTopBarActions() {
    if (_isSelecting) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_selectedUserIds.isNotEmpty) ...[
            IconButton(
              icon: _isBulkDeleting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    )
                  : Icon(Icons.delete, color: Colors.red, size: 18),
              onPressed: _isBulkDeleting ? null : _bulkDeleteUsers,
              tooltip: 'Delete Selected',
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: 36, maxWidth: 36),
            ),
            const SizedBox(width: 4),
          ],
          TextButton(
            onPressed: _toggleSelectionMode,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size(0, 0),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue, size: 18),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh Data',
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 36, maxWidth: 36),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _toggleSelectionMode,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size(0, 0),
            ),
            child: const Text('Select', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }
  }

  // FIXED: Improved main content without duplicates
  Widget _buildMainContent() {
    return Column(
      children: [
        // FIXED: Selection Info Bar - Only show once and only when selecting
        if (_isSelecting) _buildSelectionInfoBar(),

        // FIXED: User Statistics - Only show once and only when not selecting and not in desktop
        if (!_isDesktop && !_isSelecting) _buildUserStatistics(),

        // User List
        Expanded(child: _buildUserList()),
      ],
    );
  }

  // FIXED: Improved selection info bar without duplicate buttons
  Widget _buildSelectionInfoBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.blue[50],
      child: Row(
        children: [
          Icon(Icons.checklist, color: Colors.blue[700], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_selectedUserIds.length} users selected',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
                fontSize: _isMobile ? 14 : 16,
              ),
            ),
          ),
          // FIXED: Only show buttons in desktop, mobile has them in app bar
          if (_isDesktop) ...[
            TextButton(onPressed: _clearSelection, child: const Text('Clear')),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _selectAllUsers, // This now uses the filtered version
              child: const Text('Select All Filtered'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUserStatistics() {
    // Get filtered users and calculate statistics from them
    final filteredUsers = _getFilteredUsers();
    final filteredStats = _calculateStatistics(filteredUsers);

    return Container(
      padding: EdgeInsets.all(_isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard(
            'Total Users',
            filteredStats['total'] ?? 0,
            Colors.blue,
          ),
          _buildStatCard(
            'Students',
            filteredStats['students'] ?? 0,
            Colors.green,
          ),
          _buildStatCard(
            'Teachers',
            filteredStats['teachers'] ?? 0,
            Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(_isMobile ? 8 : 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: _isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: _isMobile ? 10 : 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // FIXED: Improved user list with proper filtering
  Widget _buildUserList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _users,
      builder: (context, snapshot) {
        if ((_cachedUsers.isEmpty && _isLoading) ||
            (snapshot.connectionState == ConnectionState.waiting &&
                _cachedUsers.isEmpty &&
                !_initialLoadCompleted)) {
          return const Center(child: CircularProgressIndicator());
        }

        List<Map<String, dynamic>> users = _cachedUsers;

        if (users.isEmpty) {
          return _buildEmptyState();
        }

        // Apply search filter
        if (_searchQuery.isNotEmpty) {
          users = users.where((user) {
            final username = user['username']?.toString().toLowerCase() ?? '';
            final fullName = user['full_name']?.toString().toLowerCase() ?? '';
            final email = user['gmail']?.toString().toLowerCase() ?? '';
            final mobile =
                user['mobile_number']?.toString().toLowerCase() ?? '';

            return username.contains(_searchQuery) ||
                fullName.contains(_searchQuery) ||
                email.contains(_searchQuery) ||
                mobile.contains(_searchQuery);
          }).toList();
        }

        // Apply role filter
        if (_selectedRoleFilter != 'all') {
          users = users.where((user) {
            final role = user['role']?.toString() ?? '';
            return role == _selectedRoleFilter;
          }).toList();
        }

        // Apply class filter for students
        if (_selectedClassFilter != 'all') {
          users = users.where((user) {
            final role = user['role']?.toString() ?? '';
            if (role == 'student') {
              final classGrade =
                  user['class_grade']?.toString() ??
                  user['class_name']?.toString() ??
                  user['class']?.toString() ??
                  '';
              return classGrade == _selectedClassFilter;
            }
            return _selectedRoleFilter == 'all';
          }).toList();
        }

        // Apply section filter for students
        if (_selectedSectionFilter != 'all') {
          users = users.where((user) {
            final role = user['role']?.toString() ?? '';
            if (role == 'student') {
              final section = user['section']?.toString() ?? '';
              return section == _selectedSectionFilter;
            }
            return _selectedRoleFilter == 'all';
          }).toList();
        }

        if (_selectedSubjectFilter != 'all') {
          users = users.where((user) {
            final role = user['role']?.toString() ?? '';
            final userId = user['id']?.toString() ?? '';

            if (role == 'teacher') {
              // Check if this teacher is assigned to the selected subject
              bool isAssignedToSubject = _subjectDocuments.any((subject) {
                final subjectName = subject['subject_name']?.toString() ?? '';
                final teacherIds = List<String>.from(
                  subject['teacher_ids'] ?? [],
                );

                // Check if subject name matches AND teacher ID is in the teacher_ids list
                final subjectMatches =
                    subjectName.toLowerCase() ==
                    _selectedSubjectFilter.toLowerCase();
                final teacherAssigned = teacherIds.contains(userId);

                if (subjectMatches && teacherAssigned) {
                  print(
                    '✅ TEACHER SUBJECT MATCH: ${user['username']} is assigned to $subjectName',
                  );
                  return true;
                }
                return false;
              });

              if (!isAssignedToSubject) {
                print(
                  '❌ TEACHER NOT ASSIGNED: ${user['username']} is NOT assigned to $_selectedSubjectFilter',
                );
              }

              return isAssignedToSubject;
            }
            // Keep non-teacher users when role filter is 'all'
            return _selectedRoleFilter == 'all';
          }).toList();
        }

        // Filter out admin users from display
        users = users.where((user) {
          final role = user['role']?.toString() ?? '';
          return role != 'admin' && role != 'super_admin';
        }).toList();

        if (users.isEmpty) {
          return _buildEmptyState();
        }

        return RefreshIndicator(
          onRefresh: _refreshData,
          child: _isDesktop
              ? _buildDesktopUserList(users)
              : _buildMobileUserList(users),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      child: Container(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No users found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Try adjusting your search or filters',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (_selectedRoleFilter != 'all' ||
                    _selectedClassFilter != 'all' ||
                    _selectedSectionFilter != 'all' ||
                    _selectedSubjectFilter != 'all')
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _selectedRoleFilter = 'all';
                        _selectedClassFilter = 'all';
                        _selectedSectionFilter = 'all';
                        _selectedSubjectFilter = 'all';
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                    child: const Text('Clear All Filters'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // FIXED: Improved desktop user list without duplicate select all header
  Widget _buildDesktopUserList(List<Map<String, dynamic>> users) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Users (${users.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) => InkWell(
                  onTap: _isSelecting
                      ? null
                      : () => _showUserDetails(users[index]),
                  child: _buildDesktopUserItem(users[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopUserItem(Map<String, dynamic> user) {
    final userId = user['id'] ?? '';
    final username = user['username'] ?? 'No username';
    final role = user['role'] ?? 'unknown';
    final fullName = user['full_name'] ?? 'No name';
    final isFirstLogin = user['is_first_login'] ?? false;
    final createdAt = user['created_at'] is Timestamp
        ? (user['created_at'] as Timestamp).toDate()
        : null;
    final classGrade =
        user['class_grade']?.toString() ??
        user['class_name']?.toString() ??
        user['class']?.toString() ??
        '';
    final section = user['section'] ?? '';
    final subject = user['subject'] ?? '';
    final isSelected = _selectedUserIds.contains(userId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: _isSelecting
            ? Checkbox(
                value: isSelected,
                onChanged: (bool? value) {
                  _toggleUserSelection(userId, value ?? false);
                },
              )
            : CircleAvatar(
                backgroundColor: _getRoleColor(role),
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
        title: Text(
          fullName != 'No name' ? fullName : username,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Username: $username', style: const TextStyle(fontSize: 14)),
            Text(
              'Role: ${role.toUpperCase()}',
              style: const TextStyle(fontSize: 14),
            ),
            if (role == 'student' && classGrade.isNotEmpty)
              Text(
                'Class: $classGrade${section.isNotEmpty ? ' - $section' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            if (role == 'teacher' && subject.isNotEmpty)
              Text(
                'Subject: $subject',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            if (createdAt != null)
              Text(
                'Created: ${_formatDate(createdAt)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (isFirstLogin)
              const Text(
                '⚠️ First login required',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
          ],
        ),
        trailing: _isSelecting
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _editUser(user, userId);
                      break;
                    case 'reset_password':
                      _resetUserPassword(userId, username, role);
                      break;
                    case 'delete':
                      _deleteUser(userId, username);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text('Edit User'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'reset_password',
                    child: Row(
                      children: [
                        Icon(Icons.lock_reset, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        const Text('Reset Password'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Delete User',
                          style: TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // FIXED: Improved mobile user list without duplicate select all header
  Widget _buildMobileUserList(List<Map<String, dynamic>> users) {
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final userId = user['id'] ?? '';
        final username = user['username'] ?? 'No username';
        final role = user['role'] ?? 'unknown';
        final fullName = user['full_name'] ?? 'No name';
        final isFirstLogin = user['is_first_login'] ?? false;
        final createdAt = user['created_at'] is Timestamp
            ? (user['created_at'] as Timestamp).toDate()
            : null;
        final classGrade =
            user['class_grade']?.toString() ??
            user['class_name']?.toString() ??
            user['class']?.toString() ??
            '';
        final section = user['section'] ?? '';
        final subject = user['subject'] ?? '';
        final isSelected = _selectedUserIds.contains(userId);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: _isSelecting
                ? Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) {
                      _toggleUserSelection(userId, value ?? false);
                    },
                  )
                : CircleAvatar(
                    backgroundColor: _getRoleColor(role),
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
            title: Text(
              fullName != 'No name' ? fullName : username,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Username: $username',
                  style: TextStyle(fontSize: _isMobile ? 12 : 14),
                ),
                Text(
                  'Role: ${role.toUpperCase()}',
                  style: TextStyle(fontSize: _isMobile ? 12 : 14),
                ),
                if (role == 'student' && classGrade.isNotEmpty)
                  Text(
                    'Class: $classGrade${section.isNotEmpty ? ' - $section' : ''}',
                    style: TextStyle(
                      fontSize: _isMobile ? 11 : 12,
                      color: Colors.green,
                    ),
                  ),
                if (role == 'teacher' && subject.isNotEmpty)
                  Text(
                    'Subject: $subject',
                    style: TextStyle(
                      fontSize: _isMobile ? 11 : 12,
                      color: Colors.orange,
                    ),
                  ),
                if (createdAt != null)
                  Text(
                    'Created: ${_formatDate(createdAt)}',
                    style: TextStyle(
                      fontSize: _isMobile ? 10 : 12,
                      color: Colors.grey,
                    ),
                  ),
                if (isFirstLogin)
                  Text(
                    '⚠️ First login required',
                    style: TextStyle(
                      fontSize: _isMobile ? 10 : 12,
                      color: Colors.orange,
                    ),
                  ),
              ],
            ),
            onTap: _isSelecting ? null : () => _showUserDetails(user),
            trailing: _isSelecting
                ? null
                : PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editUser(user, userId);
                          break;
                        case 'reset_password':
                          _resetUserPassword(userId, username, role);
                          break;
                        case 'delete':
                          _deleteUser(userId, username);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Edit User'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'reset_password',
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_reset,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text('Reset Password'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Delete User',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  // FIXED: Improved bulk action buttons for mobile
  Widget _buildBulkActionButtons() {
    if (!_isSelecting || _selectedUserIds.isEmpty)
      return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _isBulkDeleting ? null : _bulkDeleteUsers,
            backgroundColor: Colors.red,
            label: _isBulkDeleting
                ? const Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('Deleting...'),
                    ],
                  )
                : Text('Delete (${_selectedUserIds.length})'),
            icon: _isBulkDeleting
                ? const SizedBox.shrink()
                : const Icon(Icons.delete),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'teacher':
        return Colors.orange;
      case 'student':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// FIXED: User Details Dialog with proper class info and teacher subjects
class UserDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String schoolCode;

  const UserDetailsDialog({
    super.key,
    required this.userData,
    required this.schoolCode,
  });

  @override
  State<UserDetailsDialog> createState() => _UserDetailsDialogState();
}

class _UserDetailsDialogState extends State<UserDetailsDialog> {
  Map<String, dynamic>? _classInfo;
  List<Map<String, dynamic>> _teacherSubjects = [];
  bool _isLoadingClass = false;
  bool _isLoadingSubjects = false;
  String? _classError;
  String? _subjectError;

  @override
  void initState() {
    super.initState();
    if (widget.userData['role'] == 'student') {
      _loadClassInfo();
    }
    if (widget.userData['role'] == 'teacher') {
      _loadTeacherSubjects();
    }
  }

  // FIXED: Improved class info loading
  Future<void> _loadClassInfo() async {
    setState(() {
      _isLoadingClass = true;
      _classError = null;
    });

    try {
      final classId = widget.userData['class_id'];
      final className = widget.userData['class_name'];
      final classGrade = widget.userData['class_grade'];
      final section = widget.userData['section'];

      print('🔍 Loading class info for student:');
      print('   Class ID: $classId');
      print('   Class Name: $className');
      print('   Class Grade: $classGrade');
      print('   Section: $section');

      // If we have a class_id, try to load from Firestore
      if (classId != null && classId.toString().isNotEmpty) {
        final classDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('classes')
            .doc(classId.toString())
            .get();

        if (classDoc.exists) {
          setState(() {
            _classInfo = classDoc.data();
            _isLoadingClass = false;
          });
          print('✅ Class info loaded from Firestore: ${_classInfo}');
        } else {
          setState(() {
            _classError = 'Class document not found in database';
            _isLoadingClass = false;
          });
          print('❌ Class document not found for ID: $classId');
        }
      } else {
        // If no class_id, create class info from user data
        setState(() {
          _classInfo = {
            'grade': classGrade ?? className ?? 'Not assigned',
            'section': section ?? 'Not assigned',
            'class_name': className ?? 'Not assigned',
          };
          _isLoadingClass = false;
        });
        print('ℹ️ Using user data for class info: $_classInfo');
      }
    } catch (e) {
      print('❌ Error loading class info: $e');
      setState(() {
        _classError = 'Error loading class information: $e';
        _isLoadingClass = false;
      });
    }
  }

  // FIXED: Improved teacher subjects loading
  Future<void> _loadTeacherSubjects() async {
    setState(() {
      _isLoadingSubjects = true;
      _subjectError = null;
      _teacherSubjects = [];
    });

    try {
      final teacherId = widget.userData['id'];
      final userSubject = widget.userData['subject'];

      print('🔍 Loading subjects for teacher:');
      print('   Teacher ID: $teacherId');
      print('   User Subject: $userSubject');

      if (teacherId == null || teacherId.toString().isEmpty) {
        setState(() {
          _subjectError = 'Teacher ID not found';
          _isLoadingSubjects = false;
        });
        return;
      }

      // Load subjects from the subjects collection where this teacher is assigned
      final subjectsSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('subjects')
          .where('teacher_ids', arrayContains: teacherId.toString())
          .get();

      if (subjectsSnapshot.docs.isNotEmpty) {
        final subjects = subjectsSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'subject_id': doc.id,
            'subject_name': data['subject_name'] ?? 'Unknown Subject',
            'grade': data['grade'] ?? 'All Grades',
            'section': data['section'] ?? 'All Sections',
          };
        }).toList();

        setState(() {
          _teacherSubjects = subjects;
          _isLoadingSubjects = false;
        });

        print('✅ Loaded ${subjects.length} subjects for teacher:');
        for (final subject in subjects) {
          print(
            '   - ${subject['subject_name']} (${subject['grade']} - ${subject['section']})',
          );
        }
      } else {
        // If no subjects found in collection, check if user has subject field
        if (userSubject != null && userSubject.toString().isNotEmpty) {
          setState(() {
            _teacherSubjects = [
              {
                'subject_name': userSubject.toString(),
                'grade': 'Not specified',
                'section': 'Not specified',
                'source': 'user_profile',
              },
            ];
            _isLoadingSubjects = false;
          });
          print('ℹ️ Using subject from user profile: $userSubject');
        } else {
          setState(() {
            _subjectError =
                'No subjects assigned in collection and no subject in user profile';
            _isLoadingSubjects = false;
          });
          print(
            '❌ No subjects found for teacher in collection or user profile',
          );
        }
      }
    } catch (e) {
      print('❌ Error loading teacher subjects: $e');
      setState(() {
        _subjectError = 'Error loading subjects: $e';
        _isLoadingSubjects = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;
    final isStudent = widget.userData['role'] == 'student';
    final isTeacher = widget.userData['role'] == 'teacher';

    return Dialog(
      insetPadding: isDesktop
          ? const EdgeInsets.symmetric(horizontal: 100, vertical: 50)
          : const EdgeInsets.all(16),
      child: Container(
        constraints: isDesktop
            ? const BoxConstraints(maxWidth: 600, maxHeight: 700)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${widget.userData['full_name'] ?? widget.userData['username']} - Details',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Class Information for Students - FIXED
                    if (isStudent) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Class Information',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),

                            if (_isLoadingClass)
                              _buildLoadingIndicator(
                                'Loading class information...',
                              )
                            else if (_classError != null)
                              _buildErrorWidget(_classError!)
                            else if (_classInfo != null) ...[
                              // Show class info from Firestore or user data
                              _buildClassDetailRow(
                                'Grade/Class',
                                _classInfo!['grade'] ??
                                    _classInfo!['class_name'] ??
                                    widget.userData['class_grade'] ??
                                    widget.userData['class_name'] ??
                                    'Not assigned',
                              ),
                              _buildClassDetailRow(
                                'Section',
                                _classInfo!['section'] ??
                                    widget.userData['section'] ??
                                    'Not assigned',
                              ),
                            ] else
                              const Text('No class information available'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Subjects Information for Teachers - FIXED
                    if (isTeacher) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Teaching Subjects',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),

                            if (_isLoadingSubjects)
                              _buildLoadingIndicator('Loading subjects...')
                            else if (_subjectError != null)
                              _buildErrorWidget(_subjectError!)
                            else if (_teacherSubjects.isNotEmpty) ...[
                              ..._teacherSubjects.map((subject) {
                                return Column(
                                  children: [
                                    _buildSubjectDetailRow(
                                      subject['subject_name'] ??
                                          'Unknown Subject',
                                      subject['grade'] ?? 'All Grades',
                                      subject['section'] ?? 'All Sections',
                                    ),
                                    if (_teacherSubjects.length > 1 &&
                                        _teacherSubjects.indexOf(subject) <
                                            _teacherSubjects.length - 1)
                                      const Divider(height: 16),
                                  ],
                                );
                              }).toList(),
                              if (_teacherSubjects.any(
                                (subject) =>
                                    subject['source'] == 'user_profile',
                              ))
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[100],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '* Subject information from user profile',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color.fromARGB(255, 239, 108, 0),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ] else
                              const Text('No subjects assigned'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // User Details - FIXED with better data handling
                    _buildUserDetailRow(
                      'Username',
                      widget.userData['username'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Full Name',
                      widget.userData['full_name'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Role',
                      (widget.userData['role'] ?? 'N/A')
                          .toString()
                          .toUpperCase(),
                    ),
                    _buildUserDetailRow(
                      'Status',
                      (widget.userData['status'] ?? 'active')
                          .toString()
                          .toUpperCase(),
                    ),
                    _buildUserDetailRow(
                      'School Code',
                      widget.userData['school_code'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Mobile Number',
                      widget.userData['mobile_number'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'Email',
                      widget.userData['gmail'] ?? 'N/A',
                    ),
                    _buildUserDetailRow(
                      'First Login Required',
                      (widget.userData['is_first_login'] ?? false)
                          ? 'Yes'
                          : 'No',
                    ),

                    // Additional student fields
                    if (isStudent) ...[
                      if (widget.userData['roll_number'] != null)
                        _buildUserDetailRow(
                          'Roll Number',
                          widget.userData['roll_number']!,
                        ),
                      if (widget.userData['parent_guardian_name'] != null)
                        _buildUserDetailRow(
                          'Parent/Guardian Name',
                          widget.userData['parent_guardian_name']!,
                        ),
                      if (widget.userData['parent_guardian_mobile'] != null)
                        _buildUserDetailRow(
                          'Parent/Guardian Mobile',
                          widget.userData['parent_guardian_mobile']!,
                        ),
                    ],

                    // Additional teacher fields
                    if (isTeacher) ...[
                      if (widget.userData['subject'] != null)
                        _buildUserDetailRow(
                          'Primary Subject',
                          widget.userData['subject']!,
                        ),
                      if (widget.userData['class_teacher_for'] != null)
                        _buildUserDetailRow(
                          'Class Teacher For',
                          widget.userData['class_teacher_for']!,
                        ),
                    ],
                  ],
                ),
              ),
            ),
            // Close Button
            Container(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator(String message) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
          ),
        ),
        const SizedBox(width: 8),
        Text(message, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildErrorWidget(String error) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: Colors.red[700], size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(fontSize: 12, color: Colors.red[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildClassDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.blue,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectDetailRow(
    String subjectName,
    String grade,
    String section,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subjectName,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.orange,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                'Grade: $grade',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(width: 16),
              Text(
                'Section: $section',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// Admin Edit User Dialog
class AdminEditUserDialog extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;
  final String schoolCode;
  final String schoolName;
  final VoidCallback? onUserUpdated;

  const AdminEditUserDialog({
    super.key,
    required this.userData,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    this.onUserUpdated,
  });

  @override
  State<AdminEditUserDialog> createState() => _AdminEditUserDialogState();
}

class _AdminEditUserDialogState extends State<AdminEditUserDialog> {
  late String _selectedRole;
  late String _selectedStatus;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _classTeacherForController =
      TextEditingController();
  final TextEditingController _classGradeController = TextEditingController();
  final TextEditingController _rollNumberController = TextEditingController();
  final TextEditingController _parentNameController = TextEditingController();
  final TextEditingController _parentMobileController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _gmailController = TextEditingController();

  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.userData['role'] ?? 'student';
    _selectedStatus = widget.userData['status'] ?? 'active';

    _usernameController.text = widget.userData['username'] ?? '';
    _fullNameController.text = widget.userData['full_name'] ?? '';
    _subjectController.text = widget.userData['subject'] ?? '';
    _classTeacherForController.text =
        widget.userData['class_teacher_for'] ?? '';
    _classGradeController.text = widget.userData['class_grade'] ?? '';
    _rollNumberController.text = widget.userData['roll_number'] ?? '';
    _parentNameController.text = widget.userData['parent_guardian_name'] ?? '';
    _parentMobileController.text =
        widget.userData['parent_guardian_mobile'] ?? '';
    _mobileController.text = widget.userData['mobile_number'] ?? '';
    _gmailController.text = widget.userData['gmail'] ?? '';
  }

  Future<void> _updateUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Map<String, dynamic> updateData = {
        'role': _selectedRole,
        'school_code': widget.schoolCode,
        'school_name': widget.schoolName,
        'status': _selectedStatus,
        'updated_at': FieldValue.serverTimestamp(),
      };

      final fullName = _fullNameController.text.trim();
      if (fullName.isNotEmpty) {
        updateData['full_name'] = fullName;
      }

      final mobileNumber = _mobileController.text.trim();
      if (mobileNumber.isNotEmpty) {
        updateData['mobile_number'] = mobileNumber;
      }

      final gmail = _gmailController.text.trim();
      if (gmail.isNotEmpty) {
        updateData['gmail'] = gmail;
      }

      if (_selectedRole == 'teacher') {
        final subject = _subjectController.text.trim();
        if (subject.isNotEmpty) {
          updateData['subject'] = subject;
        }

        final classTeacherFor = _classTeacherForController.text.trim();
        if (classTeacherFor.isNotEmpty) {
          updateData['class_teacher_for'] = classTeacherFor;
        }

        updateData.remove('class_grade');
        updateData.remove('roll_number');
        updateData.remove('parent_guardian_name');
        updateData.remove('parent_guardian_mobile');
      } else if (_selectedRole == 'student') {
        final classGrade = _classGradeController.text.trim();
        if (classGrade.isNotEmpty) {
          updateData['class_grade'] = classGrade;
        }

        final rollNumber = _rollNumberController.text.trim();
        if (rollNumber.isNotEmpty) {
          updateData['roll_number'] = rollNumber;
        }

        final parentName = _parentNameController.text.trim();
        if (parentName.isNotEmpty) {
          updateData['parent_guardian_name'] = parentName;
        }

        final parentMobile = _parentMobileController.text.trim();
        if (parentMobile.isNotEmpty) {
          updateData['parent_guardian_mobile'] = parentMobile;
        }

        updateData.remove('subject');
        updateData.remove('class_teacher_for');
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update(updateData);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_fetch_time_${widget.schoolCode}');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onUserUpdated?.call();
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error updating user: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;
    return Dialog(
      insetPadding: isDesktop
          ? const EdgeInsets.symmetric(horizontal: 100, vertical: 50)
          : const EdgeInsets.all(20),
      child: Container(
        constraints: isDesktop
            ? const BoxConstraints(maxWidth: 600, maxHeight: 700)
            : null,
        child: Column(
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Edit User',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // School Information
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.school,
                            color: Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.schoolName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'Code: ${widget.schoolCode}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Username Field (Read-only)
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Color.fromARGB(255, 236, 236, 236),
                      ),
                      readOnly: true,
                      enabled: false,
                    ),
                    const SizedBox(height: 16),

                    // Role Selection
                    DropdownButtonFormField<String>(
                      value: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                      items: ['student', 'teacher'].map((String role) {
                        return DropdownMenuItem<String>(
                          value: role,
                          child: Text(
                            role[0].toUpperCase() + role.substring(1),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedRole = newValue!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Status Selection
                    DropdownButtonFormField<String>(
                      value: _selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: ['active', 'inactive'].map((String status) {
                        return DropdownMenuItem<String>(
                          value: status,
                          child: Text(
                            status[0].toUpperCase() + status.substring(1),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedStatus = newValue!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Common Fields
                    TextField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        hintText: 'Enter full name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _mobileController,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number',
                        hintText: 'Enter mobile number',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _gmailController,
                      decoration: const InputDecoration(
                        labelText: 'Gmail',
                        hintText: 'Enter gmail address',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),

                    if (_selectedRole == 'student') ...[
                      TextField(
                        controller: _classGradeController,
                        decoration: const InputDecoration(
                          labelText: 'Class/Grade',
                          hintText: 'Enter class/grade (e.g., 5A)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _rollNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Roll Number',
                          hintText: 'Enter roll number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _parentNameController,
                        decoration: const InputDecoration(
                          labelText: 'Parent/Guardian Name',
                          hintText: 'Enter parent/guardian name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _parentMobileController,
                        decoration: const InputDecoration(
                          labelText: 'Parent/Guardian Mobile',
                          hintText: 'Enter parent/guardian mobile',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Error Message
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
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
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _updateUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(
                          255,
                          21,
                          101,
                          192,
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(color: Colors.white),
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

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _subjectController.dispose();
    _classTeacherForController.dispose();
    _classGradeController.dispose();
    _rollNumberController.dispose();
    _parentNameController.dispose();
    _parentMobileController.dispose();
    _mobileController.dispose();
    _gmailController.dispose();
    super.dispose();
  }
}
