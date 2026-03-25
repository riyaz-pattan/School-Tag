import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

class MessagesScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String userRole;
  final String userName;

  const MessagesScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.userRole,
    required this.userName,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabTitles = ['Inbox', 'Sent', 'Compose'];

  List<Map<String, dynamic>> _inboxMessages = [];
  List<Map<String, dynamic>> _sentMessages = [];
  bool _isLoadingInbox = true;
  bool _isLoadingSent = true;

  // For compose section
  String _selectedRecipientType = 'individual';
  String? _selectedRecipientId;
  String? _selectedRecipientName;
  String _subject = '';
  String _body = '';

  // For recipient selection
  List<Map<String, dynamic>> _availableTeachers = [];
  List<Map<String, dynamic>> _availableStudents = [];
  List<Map<String, dynamic>> _availableClasses = [];
  List<Map<String, dynamic>> _availableAdmins = [];

  bool _isLoadingRecipients = false;
  bool _isSendingMessage = false;
  bool _needsRecipientRefresh = true;

  // For search and filters - SEPARATE CONTROLLERS FOR EACH TAB
  final TextEditingController _inboxSearchController = TextEditingController();
  final TextEditingController _sentSearchController = TextEditingController();
  final TextEditingController _composeSearchController =
      TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  String _selectedRoleFilter = '';
  List<Map<String, dynamic>> _filteredUsers = [];

  // UI state
  final FocusNode _subjectFocusNode = FocusNode();
  final FocusNode _bodyFocusNode = FocusNode();
  final ScrollController _inboxScrollController = ScrollController();
  final ScrollController _sentScrollController = ScrollController();
  final ScrollController _composeScrollController = ScrollController();

  // Cache
  late SharedPreferences _prefs;
  static const String _inboxCacheKey = 'inbox_messages';
  static const String _sentCacheKey = 'sent_messages';
  static const String _teachersCacheKey = 'cached_teachers';
  static const String _studentsCacheKey = 'cached_students';
  static const String _adminsCacheKey = 'cached_admins';
  static const String _classesCacheKey = 'cached_classes';
  static const String _timetableCacheKey = 'cached_timetables';
  static const String _subjectsCacheKey = 'cached_subjects';
  static const String _userClassCacheKey = 'cached_user_class';
  static const String _cacheTimestampKey = 'cache_timestamp';

  // Timestamp conversion methods
  Map<String, dynamic> _timestampToMap(Timestamp timestamp) {
    return {'seconds': timestamp.seconds, 'nanoseconds': timestamp.nanoseconds};
  }

  Timestamp _mapToTimestamp(Map<String, dynamic> map) {
    return Timestamp(map['seconds'] as int, map['nanoseconds'] as int);
  }

  // Timetable data for filtering
  List<Map<String, dynamic>> _timetableData = [];
  List<Map<String, dynamic>> _subjectsData = [];
  Map<String, List<String>> _teacherAssignments = {};
  Map<String, List<String>> _teacherSubjectsMap = {};
  Map<String, String> _studentClasses = {};
  String? _currentUserClassId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        setState(() {
          // Clear all search controllers when switching tabs
          _inboxSearchController.clear();
          _sentSearchController.clear();
          _composeSearchController.clear();
          // Load recipients when switching to compose tab
          if (_tabController.index == 2) {
            _needsRecipientRefresh = true;
            _loadRecipients();
          }
          // Reset compose when switching tabs
          if (_tabController.index != 2) {
            _resetComposeForm();
          }
        });
      });

    _initSharedPreferences();
    _initializeRecipientTypes();

    // Listen to text changes
    _subjectController.addListener(() {
      _subject = _subjectController.text;
    });

    _bodyController.addListener(() {
      _body = _bodyController.text;
    });
  }

  void _resetComposeForm() {
    setState(() {
      _subject = '';
      _body = '';
      _selectedRecipientId = null;
      _selectedRecipientName = null;
      _toController.clear();
      _selectedRecipientType = 'individual';
      _selectedRoleFilter = _getDefaultRoleFilter();
      _composeSearchController.clear();
      _subjectController.clear();
      _bodyController.clear();
      _filteredUsers.clear();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inboxSearchController.dispose();
    _sentSearchController.dispose();
    _composeSearchController.dispose();
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _subjectFocusNode.dispose();
    _bodyFocusNode.dispose();
    _inboxScrollController.dispose();
    _sentScrollController.dispose();
    _composeScrollController.dispose();
    super.dispose();
  }

  void _initializeRecipientTypes() {
    if (widget.userRole == 'admin') {
      _selectedRoleFilter = 'teacher';
    } else if (widget.userRole == 'teacher') {
      _selectedRoleFilter = 'admin';
    } else if (widget.userRole == 'student') {
      _selectedRoleFilter = 'teacher';
    }
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadInboxMessages(), _loadSentMessages()]);
    if (widget.userRole == 'teacher' ||
        widget.userRole == 'admin' ||
        widget.userRole == 'student') {
      await _loadRecipients();
    }
  }

  Future<void> _loadInboxMessages() async {
    setState(() {
      _isLoadingInbox = true;
    });

    try {
      // Try cache first
      final cachedInbox = _prefs.getString(
        '${_inboxCacheKey}_${widget.userId}_${widget.schoolCode}',
      );
      if (cachedInbox != null) {
        final decoded = json.decode(cachedInbox) as List<dynamic>;
        setState(() {
          _inboxMessages = decoded.map<Map<String, dynamic>>((cacheMsg) {
            final Map<String, dynamic> msg = Map.from(cacheMsg);
            if (msg['timestamp'] is Map) {
              msg['timestamp'] = _mapToTimestamp(
                msg['timestamp'] as Map<String, dynamic>,
              );
            }
            return msg;
          }).toList();
        });
      }

      // Load from Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('messages')
          .where('recipients', arrayContains: widget.userId)
          .where('sender_id', isNotEqualTo: widget.userId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      final messages = await _processMessages(snapshot.docs);

      setState(() {
        _inboxMessages = messages;
        _isLoadingInbox = false;
      });

      // Cache the results
      await _prefs.setString(
        '${_inboxCacheKey}_${widget.userId}_${widget.schoolCode}',
        json.encode(
          messages.map((msg) {
            final Map<String, dynamic> cacheMsg = Map.from(msg);
            cacheMsg['timestamp'] = _timestampToMap(
              cacheMsg['timestamp'] as Timestamp,
            );
            return cacheMsg;
          }).toList(),
        ),
      );
    } catch (e) {
      print('Error loading inbox: $e');
      setState(() {
        _isLoadingInbox = false;
      });
    }
  }

  Future<void> _loadSentMessages() async {
    setState(() {
      _isLoadingSent = true;
    });

    try {
      // Try cache first
      final cachedSent = _prefs.getString(
        '${_sentCacheKey}_${widget.userId}_${widget.schoolCode}',
      );
      if (cachedSent != null) {
        final decoded = json.decode(cachedSent) as List<dynamic>;
        setState(() {
          _sentMessages = decoded.map<Map<String, dynamic>>((cacheMsg) {
            final Map<String, dynamic> msg = Map.from(cacheMsg);
            if (msg['timestamp'] is Map) {
              msg['timestamp'] = _mapToTimestamp(
                msg['timestamp'] as Map<String, dynamic>,
              );
            }
            return msg;
          }).toList();
        });
      }

      // Load from Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('messages')
          .where('sender_id', isEqualTo: widget.userId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      final messages = await _processMessages(snapshot.docs);

      setState(() {
        _sentMessages = messages;
        _isLoadingSent = false;
      });

      // Cache the results
      await _prefs.setString(
        '${_sentCacheKey}_${widget.userId}_${widget.schoolCode}',
        json.encode(
          messages.map((msg) {
            final Map<String, dynamic> cacheMsg = Map.from(msg);
            cacheMsg['timestamp'] = _timestampToMap(
              cacheMsg['timestamp'] as Timestamp,
            );
            return cacheMsg;
          }).toList(),
        ),
      );
    } catch (e) {
      print('Error loading sent messages: $e');
      setState(() {
        _isLoadingSent = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _processMessages(
    List<QueryDocumentSnapshot> docs,
  ) async {
    final messages = <Map<String, dynamic>>[];

    for (var doc in docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final senderId = data['sender_id'];
        final recipients = List<String>.from(data['recipients'] ?? []);
        final messageType = data['message_type'] ?? 'individual';

        // Get sender name - use stored name from message data
        String senderName = data['sender_name'] ?? 'Unknown';

        // For backwards compatibility, try to fetch if not stored
        if (senderName == 'Unknown' && widget.userRole != 'student') {
          if (senderId == widget.userId) {
            senderName = widget.userName;
          } else {
            try {
              final senderDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(senderId)
                  .get();
              if (senderDoc.exists) {
                final senderData = senderDoc.data()!;
                senderName =
                    senderData['full_name'] ??
                    senderData['username'] ??
                    'Unknown';
              }
            } catch (e) {
              print('Error getting sender name: $e');
            }
          }
        }

        // Get recipient display text based on message type
        List<String> recipientDisplay = [];

        if (messageType == 'class') {
          final className = data['recipient_name'] ?? 'Class';
          recipientDisplay = [className];
        } else {
          if (senderId == widget.userId) {
            if (data['recipient_name'] != null) {
              recipientDisplay = [data['recipient_name']];
            } else {
              recipientDisplay = await _getRecipientDisplayNames(
                recipients,
                skipCurrentUser: true,
              );
            }
          } else {
            recipientDisplay = [];
          }
        }

        messages.add({
          'id': doc.id,
          'sender_id': senderId,
          'sender_name': senderName,
          'recipients': recipients,
          'recipient_display': recipientDisplay,
          'subject': data['subject'] ?? 'No Subject',
          'body': data['body'] ?? '',
          'timestamp': data['timestamp'] != null
              ? (data['timestamp'] is Timestamp
                    ? data['timestamp'] as Timestamp
                    : Timestamp.now())
              : Timestamp.now(),
          'is_read': data['read_by']?.contains(widget.userId) ?? false,
          'message_type': messageType,
        });
      } catch (e) {
        print('Error processing message ${doc.id}: $e');
        // Continue with next message
      }
    }

    return messages;
  }

  Future<List<String>> _getRecipientDisplayNames(
    List<String> recipientIds, {
    bool skipCurrentUser = true,
  }) async {
    final displayNames = <String>[];

    for (var i = 0; i < recipientIds.length && i < 3; i++) {
      final recipientId = recipientIds[i];

      if (skipCurrentUser && recipientId == widget.userId) continue;

      if (widget.userRole == 'admin' || widget.userRole == 'teacher') {
        try {
          final recipientDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(recipientId)
              .get();
          if (recipientDoc.exists) {
            final recipientData = recipientDoc.data()!;
            final name =
                recipientData['full_name'] ??
                recipientData['username'] ??
                'User';
            displayNames.add(name);
          } else {
            displayNames.add('User');
          }
        } catch (e) {
          print('Error getting recipient name: $e');
          displayNames.add('User');
        }
      } else if (widget.userRole == 'student') {
        displayNames.add('User');
      }
    }

    if (recipientIds.length > 3) {
      final moreCount = recipientIds.length - 3;
      displayNames.add('+$moreCount more');
    }

    return displayNames;
  }

  Future<void> _loadRecipients() async {
    // Only load if needed to prevent unnecessary Firebase calls
    if (!_needsRecipientRefresh &&
        (_availableTeachers.isNotEmpty ||
            _availableStudents.isNotEmpty ||
            _availableAdmins.isNotEmpty)) {
      _applyUserSearch();
      return;
    }

    setState(() {
      _isLoadingRecipients = true;
      _needsRecipientRefresh = false;
    });

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastCacheTime =
          _prefs.getInt(
            '${_cacheTimestampKey}_${widget.userRole}_${widget.schoolCode}',
          ) ??
          0;
      final cacheExpired = now - lastCacheTime > 3600000; // 1 hour

      // Try to load from cache first if not expired
      if (!cacheExpired) {
        await _loadRecipientsFromCache();
      }

      // Load from Firebase if cache is expired or empty
      if (cacheExpired ||
          _availableTeachers.isEmpty ||
          _availableStudents.isEmpty ||
          _availableAdmins.isEmpty ||
          _availableClasses.isEmpty) {
        await _loadTimetableData();
        await _loadSubjectsData();
        await _loadRecipientsFromFirestore();
        await _cacheRecipients();
      }

      setState(() {
        _isLoadingRecipients = false;
        _applyUserSearch();
      });
    } catch (e) {
      print('Error loading recipients: $e');
      setState(() {
        _isLoadingRecipients = false;
      });
    }
  }

  // Helper method to convert complex objects to JSON-serializable format
  dynamic _convertToJsonSerializable(dynamic value) {
    if (value is Timestamp) {
      return _timestampToMap(value);
    } else if (value is Map) {
      return value.map<String, dynamic>(
        (key, value) =>
            MapEntry(key.toString(), _convertToJsonSerializable(value)),
      );
    } else if (value is List) {
      return value.map(_convertToJsonSerializable).toList();
    }
    return value;
  }

  // Helper method to convert back from JSON-serializable format
  dynamic _convertFromJsonSerializable(dynamic value) {
    if (value is Map) {
      // Check if it's a timestamp map
      final map = Map<String, dynamic>.from(value);
      if (map.containsKey('seconds') && map.containsKey('nanoseconds')) {
        return _mapToTimestamp(map);
      } else {
        // Recursively process the map
        return map.map<String, dynamic>(
          (key, value) =>
              MapEntry(key.toString(), _convertFromJsonSerializable(value)),
        );
      }
    } else if (value is List) {
      return value.map(_convertFromJsonSerializable).toList();
    }
    return value;
  }

  Future<void> _loadSubjectsData() async {
    try {
      // Load subjects from Firestore
      final subjectsSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('subjects')
          .get();

      _subjectsData.clear();
      _teacherSubjectsMap.clear();

      for (var doc in subjectsSnapshot.docs) {
        try {
          final data = doc.data();
          final subjectName =
              data['subject_name']?.toString() ?? 'Unknown Subject';
          final teacherIds = List<String>.from(data['teacher_ids'] ?? []);
          final teacherNames = List<String>.from(data['teacher_names'] ?? []);

          _subjectsData.add({
            'id': doc.id,
            'subject_id': data['subject_id']?.toString() ?? '',
            'subject_name': subjectName,
            'teacher_ids': teacherIds,
            'teacher_names': teacherNames,
          });

          // Build teacher to subjects map
          for (var teacherId in teacherIds) {
            if (!_teacherSubjectsMap.containsKey(teacherId)) {
              _teacherSubjectsMap[teacherId] = [];
            }
            _teacherSubjectsMap[teacherId]!.add(subjectName);
          }
        } catch (e) {
          print('Error processing subject document ${doc.id}: $e');
        }
      }

      // Cache subjects data
      await _prefs.setString(
        '${_subjectsCacheKey}_${widget.schoolCode}',
        json.encode(_convertToJsonSerializable(_subjectsData)),
      );

      print('Loaded ${_subjectsData.length} subjects from Firestore');
      print('Teacher subjects map: ${_teacherSubjectsMap.length} teachers');
    } catch (e) {
      print('Error loading subjects data: $e');

      // Try to load from cache
      final cachedSubjects = _prefs.getString(
        '${_subjectsCacheKey}_${widget.schoolCode}',
      );
      if (cachedSubjects != null) {
        try {
          final decoded = json.decode(cachedSubjects) as List<dynamic>;
          final converted = _convertFromJsonSerializable(decoded);
          if (converted is List) {
            // Cast each element to Map<String, dynamic>
            _subjectsData = List<Map<String, dynamic>>.from(
              converted.map((item) {
                if (item is Map) {
                  return Map<String, dynamic>.from(item);
                }
                return <String, dynamic>{};
              }),
            );

            // Rebuild teacher subjects map from cached data
            _teacherSubjectsMap.clear();
            for (var subject in _subjectsData) {
              final subjectName =
                  subject['subject_name']?.toString() ?? 'Unknown Subject';
              final teacherIds = List<String>.from(
                subject['teacher_ids'] ?? [],
              );

              for (var teacherId in teacherIds) {
                if (!_teacherSubjectsMap.containsKey(teacherId)) {
                  _teacherSubjectsMap[teacherId] = [];
                }
                _teacherSubjectsMap[teacherId]!.add(subjectName);
              }
            }
          }
        } catch (e) {
          print('Error loading cached subjects: $e');
        }
      }
    }
  }

  Future<void> _loadTimetableData() async {
    try {
      // Load timetable data for filtering
      final timetablesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('timetables')
          .get();

      _timetableData.clear();
      _teacherAssignments.clear();
      _studentClasses.clear();

      for (var doc in timetablesSnapshot.docs) {
        try {
          final data = doc.data();
          final classId = doc.id;

          // Convert data to JSON-serializable format
          final serializableData = _convertToJsonSerializable(data);

          _timetableData.add({'class_id': classId, ...serializableData});

          // Parse timetable to extract teacher assignments
          final timetable = data['timetable'] as Map<String, dynamic>?;
          if (timetable != null) {
            for (var daySchedule in timetable.values) {
              if (daySchedule is List) {
                for (var period in daySchedule) {
                  if (period is Map) {
                    final teacherId = period['teacher_id']?.toString();
                    final subject = period['subject']?.toString();
                    if (teacherId != null && teacherId.isNotEmpty) {
                      if (!_teacherAssignments.containsKey(teacherId)) {
                        _teacherAssignments[teacherId] = [];
                      }
                      if (!_teacherAssignments[teacherId]!.contains(classId)) {
                        _teacherAssignments[teacherId]!.add(classId);
                      }
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          print('Error processing timetable document ${doc.id}: $e');
          // Continue with next document
        }
      }

      // Load current user's class if student
      if (widget.userRole == 'student') {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data()!;
            _currentUserClassId = userData['class_id']?.toString();

            if (_currentUserClassId != null &&
                _currentUserClassId!.isNotEmpty) {
              // Cache student's class
              await _prefs.setString(
                '${_userClassCacheKey}_${widget.userId}',
                _currentUserClassId!,
              );
            }
          }
        } catch (e) {
          print('Error loading student class: $e');
          // Try to get from cache
          _currentUserClassId = _prefs.getString(
            '${_userClassCacheKey}_${widget.userId}',
          );
        }
      } else if (widget.userRole == 'teacher') {
        // Get teacher's assigned classes from timetable
        final teacherClasses = _teacherAssignments[widget.userId] ?? [];
        // Cache teacher's assigned classes
        await _prefs.setStringList(
          '${_userClassCacheKey}_${widget.userId}',
          teacherClasses,
        );
      }

      // Cache timetable data in JSON-serializable format
      await _prefs.setString(
        '${_timetableCacheKey}_${widget.schoolCode}',
        json.encode(_convertToJsonSerializable(_timetableData)),
      );
    } catch (e) {
      print('Error loading timetable data: $e');
      // Try to load from cache
      // Try to load from cache
      final cachedTimetable = _prefs.getString(
        '${_timetableCacheKey}_${widget.schoolCode}',
      );
      if (cachedTimetable != null) {
        try {
          final decoded = json.decode(cachedTimetable) as List<dynamic>;
          final converted = _convertFromJsonSerializable(decoded);
          if (converted is List) {
            // Cast each element to Map<String, dynamic>
            _timetableData = List<Map<String, dynamic>>.from(
              converted.map((item) {
                if (item is Map) {
                  return Map<String, dynamic>.from(item);
                }
                return <String, dynamic>{};
              }),
            );

            // Rebuild teacher assignments from cached data
            _teacherAssignments.clear();
            for (var timetable in _timetableData) {
              final classId = timetable['class_id']?.toString();
              final timetableData =
                  timetable['timetable'] as Map<String, dynamic>?;
              if (timetableData != null && classId != null) {
                for (var daySchedule in timetableData.values) {
                  if (daySchedule is List) {
                    for (var period in daySchedule) {
                      if (period is Map) {
                        final teacherId = period['teacher_id']?.toString();
                        if (teacherId != null && teacherId.isNotEmpty) {
                          if (!_teacherAssignments.containsKey(teacherId)) {
                            _teacherAssignments[teacherId] = [];
                          }
                          if (!_teacherAssignments[teacherId]!.contains(
                            classId,
                          )) {
                            _teacherAssignments[teacherId]!.add(classId);
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          print('Error loading cached timetable: $e');
        }
      }
    }
  }

  Future<void> _loadRecipientsFromCache() async {
    try {
      // Load teachers
      final cachedTeachers = _prefs.getString(
        '${_teachersCacheKey}_${widget.userRole}_${widget.schoolCode}',
      );
      if (cachedTeachers != null) {
        final decoded = json.decode(cachedTeachers) as List<dynamic>;
        _availableTeachers = decoded.map<Map<String, dynamic>>((item) {
          return Map<String, dynamic>.from(item);
        }).toList();
      }

      // Load students
      final cachedStudents = _prefs.getString(
        '${_studentsCacheKey}_${widget.userRole}_${widget.schoolCode}',
      );
      if (cachedStudents != null) {
        final decoded = json.decode(cachedStudents) as List<dynamic>;
        _availableStudents = decoded.map<Map<String, dynamic>>((item) {
          return Map<String, dynamic>.from(item);
        }).toList();
      }

      // Load admins
      final cachedAdmins = _prefs.getString(
        '${_adminsCacheKey}_${widget.userRole}_${widget.schoolCode}',
      );
      if (cachedAdmins != null) {
        final decoded = json.decode(cachedAdmins) as List<dynamic>;
        _availableAdmins = decoded.map<Map<String, dynamic>>((item) {
          return Map<String, dynamic>.from(item);
        }).toList();
      }

      // Load classes
      final cachedClasses = _prefs.getString(
        '${_classesCacheKey}_${widget.userRole}_${widget.schoolCode}',
      );
      if (cachedClasses != null) {
        final decoded = json.decode(cachedClasses) as List<dynamic>;
        _availableClasses = decoded.map<Map<String, dynamic>>((item) {
          return Map<String, dynamic>.from(item);
        }).toList();
      }

      // Load subjects from cache - FIXED: Proper type conversion
      final cachedSubjects = _prefs.getString(
        '${_subjectsCacheKey}_${widget.schoolCode}',
      );
      if (cachedSubjects != null) {
        try {
          final decoded = json.decode(cachedSubjects) as List<dynamic>;
          final converted = _convertFromJsonSerializable(decoded);
          if (converted is List) {
            // Cast each element to Map<String, dynamic>
            _subjectsData = List<Map<String, dynamic>>.from(
              converted.map((item) {
                if (item is Map) {
                  return Map<String, dynamic>.from(item);
                }
                return <String, dynamic>{};
              }),
            );

            // Rebuild teacher subjects map from cached data
            _teacherSubjectsMap.clear();
            for (var subject in _subjectsData) {
              final subjectName =
                  subject['subject_name']?.toString() ?? 'Unknown Subject';
              final teacherIds = List<String>.from(
                subject['teacher_ids'] ?? [],
              );

              for (var teacherId in teacherIds) {
                if (!_teacherSubjectsMap.containsKey(teacherId)) {
                  _teacherSubjectsMap[teacherId] = [];
                }
                _teacherSubjectsMap[teacherId]!.add(subjectName);
              }
            }
          }
        } catch (e) {
          print('Error loading cached subjects: $e');
        }
      }

      // Load current user class from cache
      if (widget.userRole == 'student') {
        _currentUserClassId = _prefs.getString(
          '${_userClassCacheKey}_${widget.userId}',
        );
      }
    } catch (e) {
      print('Error loading from cache: $e');
    }
  }

  Future<void> _loadRecipientsFromFirestore() async {
    try {
      // Load timetable data first for filtering
      await _loadTimetableData();
      await _loadSubjectsData();

      if (widget.userRole == 'admin') {
        await _loadAdminRecipients();
      } else if (widget.userRole == 'teacher') {
        await _loadTeacherRecipients();
      } else if (widget.userRole == 'student') {
        await _loadStudentRecipients();
      }

      if (widget.userRole == 'teacher' || widget.userRole == 'admin') {
        await _loadClassesFromFirestore();
      }
    } catch (e) {
      print('Error loading recipients from Firestore: $e');
      // Set empty lists to avoid UI errors
      setState(() {
        _availableTeachers = [];
        _availableStudents = [];
        _availableAdmins = [];
        _availableClasses = [];
      });
    }
  }

  // Helper method to get teacher's subjects
  List<String> _getTeacherSubjects(String teacherId) {
    try {
      return _teacherSubjectsMap[teacherId] ?? [];
    } catch (e) {
      print('Error getting teacher subjects: $e');
      return [];
    }
  }

  Future<void> _loadAdminRecipients() async {
    try {
      // Load all teachers
      final teachersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'teacher')
          .get();

      final teachers = <Map<String, dynamic>>[];
      for (var doc in teachersSnapshot.docs) {
        try {
          final data = doc.data();
          final userId = doc.id;

          if (userId == widget.userId) continue;

          // Get teacher's subjects from subjects collection
          final subjects = _getTeacherSubjects(userId);

          teachers.add({
            'id': userId,
            'name': data['full_name'] ?? data['username'] ?? 'Unknown',
            'role': 'teacher',
            'subject': subjects.isNotEmpty
                ? subjects.join(', ')
                : 'No subjects assigned',
          });
        } catch (e) {
          print('Error processing teacher ${doc.id}: $e');
        }
      }

      // Load all students
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .get();

      final students = <Map<String, dynamic>>[];
      for (var doc in studentsSnapshot.docs) {
        try {
          final data = doc.data();
          final userId = doc.id;

          students.add({
            'id': userId,
            'name': data['full_name'] ?? data['username'] ?? 'Unknown',
            'role': 'student',
            'username': data['username'],
            'class_id': data['class_id'],
            'class_name': data['class_name'] ?? 'Unknown Class',
            'section': data['section'] ?? 'Unknown Section',
            'roll_number': data['roll_number'],
          });
        } catch (e) {
          print('Error processing student ${doc.id}: $e');
        }
      }

      // Load all admins
      final adminsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'admin')
          .get();

      final admins = <Map<String, dynamic>>[];
      for (var doc in adminsSnapshot.docs) {
        try {
          final data = doc.data();
          final userId = doc.id;

          if (userId == widget.userId) continue;

          admins.add({
            'id': userId,
            'name': data['full_name'] ?? data['username'] ?? 'Unknown',
            'role': 'admin',
          });
        } catch (e) {
          print('Error processing admin ${doc.id}: $e');
        }
      }

      setState(() {
        _availableTeachers = teachers;
        _availableStudents = students;
        _availableAdmins = admins;
      });
    } catch (e) {
      print('Error loading admin recipients: $e');
      throw e;
    }
  }

  // FIXED: Teacher can now see students from their assigned classes
  Future<void> _loadTeacherRecipients() async {
    try {
      // Load assigned classes for this teacher from timetable
      final assignedClassIds = _teacherAssignments[widget.userId] ?? [];
      print('Teacher assigned classes: $assignedClassIds');

      // Load all admins
      final adminsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'admin')
          .get();

      final admins = <Map<String, dynamic>>[];
      for (var doc in adminsSnapshot.docs) {
        try {
          final data = doc.data();
          admins.add({
            'id': doc.id,
            'name': data['full_name'] ?? data['username'] ?? 'Unknown',
            'role': 'admin',
          });
        } catch (e) {
          print('Error processing admin ${doc.id}: $e');
        }
      }

      // Load students from assigned classes
      final students = <Map<String, dynamic>>[];

      if (assignedClassIds.isNotEmpty) {
        // Query students by class_id
        final studentsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('school_code', isEqualTo: widget.schoolCode)
            .where('role', isEqualTo: 'student')
            .get();

        for (var doc in studentsSnapshot.docs) {
          try {
            final data = doc.data();
            final studentClassId = data['class_id']?.toString();

            // Check if this student is in any of the teacher's assigned classes
            if (studentClassId != null &&
                assignedClassIds.contains(studentClassId)) {
              students.add({
                'id': doc.id,
                'name': data['full_name'] ?? data['username'] ?? 'Unknown',
                'role': 'student',
                'class_id': studentClassId,
                'class_name': data['class_name'] ?? 'Unknown Class',
                'section': data['section'] ?? 'Unknown Section',
              });
            }
          } catch (e) {
            print('Error processing student ${doc.id}: $e');
          }
        }
      } else {
        print('No assigned classes found for teacher ${widget.userId}');
      }

      print('Loaded ${students.length} students for teacher');

      setState(() {
        _availableAdmins = admins;
        _availableStudents = students;
        // Teachers don't need to see other teachers
        _availableTeachers = [];
      });
    } catch (e) {
      print('Error loading teacher recipients: $e');
      setState(() {
        _availableAdmins = [];
        _availableStudents = [];
        _availableTeachers = [];
      });
    }
  }

  Widget? _buildUserSubtitle(Map<String, dynamic> user) {
    final role = user['role']?.toString() ?? '';

    if (_selectedRoleFilter == 'student') {
      final className = user['class_name']?.toString() ?? 'Unknown Class';
      final section = user['section']?.toString() ?? 'Unknown Section';
      return Text(
        '$className - $section',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      );
    } else if (_selectedRoleFilter == 'teacher') {
      final subject = user['subject']?.toString() ?? 'No subjects assigned';
      return Text(
        'Subject: $subject',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      );
    } else if (_selectedRoleFilter == 'admin') {
      return Text(
        'Administrator',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      );
    }
    return null;
  }

  // FIXED: Student can now see teachers from their class and timetable
  Future<void> _loadStudentRecipients() async {
    try {
      // Get student's class
      if (_currentUserClassId == null || _currentUserClassId!.isEmpty) {
        // Try to get class from user document
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data()!;
            _currentUserClassId = userData['class_id']?.toString();
          }
        } catch (e) {
          print('Error getting student class: $e');
        }
      }

      print('Student class ID: $_currentUserClassId');

      // Get teachers assigned to student's class from timetable
      final assignedTeachers = <Map<String, dynamic>>[];

      if (_currentUserClassId != null && _currentUserClassId!.isNotEmpty) {
        // Find all teachers assigned to this class in timetable
        for (var teacherId in _teacherAssignments.keys) {
          if (_teacherAssignments[teacherId]!.contains(_currentUserClassId)) {
            // Get teacher details
            try {
              final teacherDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(teacherId)
                  .get();

              if (teacherDoc.exists) {
                final data = teacherDoc.data()!;
                final subjects = _getTeacherSubjects(teacherId);

                assignedTeachers.add({
                  'id': teacherId,
                  'name': data['full_name'] ?? data['username'] ?? 'Unknown',
                  'role': 'teacher',
                  'subject': subjects.isNotEmpty
                      ? subjects.join(', ')
                      : 'No subjects assigned',
                });
              }
            } catch (e) {
              print('Error loading teacher $teacherId: $e');
            }
          }
        }

        // Also check timetable data directly for additional teachers
        for (var timetable in _timetableData) {
          if (timetable['class_id'] == _currentUserClassId) {
            final timetableData =
                timetable['timetable'] as Map<String, dynamic>?;
            if (timetableData != null) {
              for (var daySchedule in timetableData.values) {
                if (daySchedule is List) {
                  for (var period in daySchedule) {
                    final teacherId = period['teacher_id']?.toString();
                    if (teacherId != null &&
                        teacherId.isNotEmpty &&
                        !assignedTeachers.any((t) => t['id'] == teacherId)) {
                      // Get teacher details
                      try {
                        final teacherDoc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(teacherId)
                            .get();

                        if (teacherDoc.exists) {
                          final data = teacherDoc.data()!;
                          final subjects = _getTeacherSubjects(teacherId);

                          assignedTeachers.add({
                            'id': teacherId,
                            'name':
                                data['full_name'] ??
                                data['username'] ??
                                'Unknown',
                            'role': 'teacher',
                            'subject': subjects.isNotEmpty
                                ? subjects.join(', ')
                                : 'No subjects assigned',
                          });
                        }
                      } catch (e) {
                        print('Error loading teacher $teacherId: $e');
                      }
                    }
                  }
                }
              }
            }
            break;
          }
        }
      }

      // Load all admins
      final adminsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'admin')
          .get();

      final admins = <Map<String, dynamic>>[];
      for (var doc in adminsSnapshot.docs) {
        try {
          final data = doc.data();
          admins.add({
            'id': doc.id,
            'name': data['full_name'] ?? data['username'] ?? 'Unknown',
            'role': 'admin',
          });
        } catch (e) {
          print('Error processing admin ${doc.id}: $e');
        }
      }

      print('Loaded ${assignedTeachers.length} teachers for student');

      setState(() {
        _availableTeachers = assignedTeachers;
        _availableAdmins = admins;
        _availableStudents = [];
      });
    } catch (e) {
      print('Error loading student recipients: $e');
      // Don't throw, just show empty list
      setState(() {
        _availableTeachers = [];
        _availableAdmins = [];
        _availableStudents = [];
      });
    }
  }

  Future<void> _loadClassesFromFirestore() async {
    try {
      List<Map<String, dynamic>> classes = [];

      if (widget.userRole == 'admin') {
        // Admin can see all classes
        final classesSnapshot = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('classes')
            .get();

        for (var doc in classesSnapshot.docs) {
          try {
            final data = doc.data();
            final sections = data['sections'] as List<dynamic>? ?? [];
            classes.add({
              'id': doc.id,
              'name': 'Grade ${data['grade']} (${sections.join(', ')})',
              'grade': data['grade'],
              'sections': sections,
            });
          } catch (e) {
            print('Error processing class ${doc.id}: $e');
          }
        }
      } else if (widget.userRole == 'teacher') {
        // Teacher can only see classes they're assigned to
        final assignedClassIds = _teacherAssignments[widget.userId] ?? [];

        if (assignedClassIds.isNotEmpty) {
          final classesSnapshot = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolCode)
              .collection('classes')
              .where(FieldPath.documentId, whereIn: assignedClassIds)
              .get();

          for (var doc in classesSnapshot.docs) {
            try {
              final data = doc.data();
              final sections = data['sections'] as List<dynamic>? ?? [];
              classes.add({
                'id': doc.id,
                'name': 'Grade ${data['grade']} (${sections.join(', ')})',
                'grade': data['grade'],
                'sections': sections,
              });
            } catch (e) {
              print('Error processing class ${doc.id}: $e');
            }
          }
        }
      }

      setState(() {
        _availableClasses = classes;
      });
    } catch (e) {
      print('Error loading classes: $e');
      // Continue with empty classes list
      setState(() {
        _availableClasses = [];
      });
    }
  }

  Future<void> _cacheRecipients() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Cache teachers
      await _prefs.setString(
        '${_teachersCacheKey}_${widget.userRole}_${widget.schoolCode}',
        json.encode(_availableTeachers),
      );

      // Cache students
      await _prefs.setString(
        '${_studentsCacheKey}_${widget.userRole}_${widget.schoolCode}',
        json.encode(_availableStudents),
      );

      // Cache admins
      await _prefs.setString(
        '${_adminsCacheKey}_${widget.userRole}_${widget.schoolCode}',
        json.encode(_availableAdmins),
      );

      // Cache classes
      await _prefs.setString(
        '${_classesCacheKey}_${widget.userRole}_${widget.schoolCode}',
        json.encode(_availableClasses),
      );

      // Cache subjects data
      await _prefs.setString(
        '${_subjectsCacheKey}_${widget.schoolCode}',
        json.encode(_convertToJsonSerializable(_subjectsData)),
      );

      // Cache timestamp
      await _prefs.setInt(
        '${_cacheTimestampKey}_${widget.userRole}_${widget.schoolCode}',
        now,
      );

      print('Recipients cached successfully');
    } catch (e) {
      print('Error caching recipients: $e');
    }
  }

  Future<void> _clearCache() async {
    try {
      await _prefs.remove(
        '${_teachersCacheKey}_${widget.userRole}_${widget.schoolCode}',
      );
      await _prefs.remove(
        '${_studentsCacheKey}_${widget.userRole}_${widget.schoolCode}',
      );
      await _prefs.remove(
        '${_adminsCacheKey}_${widget.userRole}_${widget.schoolCode}',
      );
      await _prefs.remove(
        '${_classesCacheKey}_${widget.userRole}_${widget.schoolCode}',
      );
      await _prefs.remove('${_subjectsCacheKey}_${widget.schoolCode}');
      await _prefs.remove(
        '${_cacheTimestampKey}_${widget.userRole}_${widget.schoolCode}',
      );
      await _prefs.remove(
        '${_inboxCacheKey}_${widget.userId}_${widget.schoolCode}',
      );
      await _prefs.remove(
        '${_sentCacheKey}_${widget.userId}_${widget.schoolCode}',
      );
      print('Cache cleared successfully');
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  Future<void> _markAsRead(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('messages')
          .doc(messageId)
          .update({
            'read_by': FieldValue.arrayUnion([widget.userId]),
          });

      setState(() {
        final index = _inboxMessages.indexWhere(
          (msg) => msg['id'] == messageId,
        );
        if (index != -1) {
          _inboxMessages[index]['is_read'] = true;
        }
      });
    } catch (e) {
      print('Error marking message as read: $e');
    }
  }

  Future<void> _deleteMessage(String messageId, bool isInbox) async {
    try {
      if (isInbox) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('messages')
            .doc(messageId)
            .update({
              'recipients': FieldValue.arrayRemove([widget.userId]),
            });
      } else {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('messages')
            .doc(messageId)
            .delete();
      }

      setState(() {
        if (isInbox) {
          _inboxMessages.removeWhere((msg) => msg['id'] == messageId);
        } else {
          _sentMessages.removeWhere((msg) => msg['id'] == messageId);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message deleted successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      print('Error deleting message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting message: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_subject.trim().isEmpty || _body.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter subject and message'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    if (_selectedRecipientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a recipient'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSendingMessage = true;
    });

    try {
      List<String> recipientIds = [];
      String? recipientNameForDisplay = _selectedRecipientName;

      if (_selectedRecipientType == 'class') {
        final classId = _selectedRecipientId;
        if (classId != null) {
          final studentsSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('school_code', isEqualTo: widget.schoolCode)
              .where('role', isEqualTo: 'student')
              .where('class_id', isEqualTo: classId)
              .get();

          recipientIds = studentsSnapshot.docs.map((doc) => doc.id).toList();
          recipientNameForDisplay = _selectedRecipientName;
        }
      } else if (_selectedRecipientType == 'individual') {
        if (_selectedRecipientId != null) {
          recipientIds = [_selectedRecipientId!];
          recipientNameForDisplay = _selectedRecipientName;
        }
      }

      recipientIds = recipientIds
          .toSet()
          .where((id) => id != widget.userId)
          .toList();

      if (recipientIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No recipients found'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        setState(() {
          _isSendingMessage = false;
        });
        return;
      }

      final messageData = {
        'sender_id': widget.userId,
        'sender_name': widget.userName,
        'sender_role': widget.userRole,
        'recipients': recipientIds,
        'recipient_name': recipientNameForDisplay,
        'subject': _subject.trim(),
        'body': _body,
        'timestamp': FieldValue.serverTimestamp(),
        'read_by': [],
        'message_type': _selectedRecipientType,
        'school_code': widget.schoolCode,
      };

      // Add message to Firestore
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('messages')
          .add(messageData);

      // Clear form
      _resetComposeForm();

      await _loadSentMessages();
      _tabController.animateTo(1);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Message sent to ${recipientNameForDisplay ?? recipientIds.length} recipient(s)',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      print('Error sending message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending message: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      setState(() {
        _isSendingMessage = false;
      });
    }
  }

  void _applyUserSearch() {
    List<Map<String, dynamic>> sourceList = [];

    if (_selectedRoleFilter == 'teacher') {
      sourceList = widget.userRole == 'admin'
          ? _availableTeachers
          : widget.userRole == 'student'
          ? _availableTeachers
          : [];
    } else if (_selectedRoleFilter == 'student') {
      sourceList = (widget.userRole == 'admin' || widget.userRole == 'teacher')
          ? _availableStudents
          : [];
    } else if (_selectedRoleFilter == 'admin') {
      sourceList =
          (widget.userRole == 'teacher' || widget.userRole == 'student')
          ? _availableAdmins
          : [];
    }

    if (_composeSearchController.text.isEmpty) {
      setState(() {
        _filteredUsers = sourceList;
      });
      return;
    }

    final searchLower = _composeSearchController.text.toLowerCase();

    setState(() {
      _filteredUsers = sourceList.where((user) {
        final name = (user['name'] ?? '').toString().toLowerCase();
        final className = (user['class_name'] ?? '').toString().toLowerCase();
        final section = (user['section'] ?? '').toString().toLowerCase();
        final subject = (user['subject'] ?? '').toString().toLowerCase();

        // Combine class and section for student search
        final classSection = '$className - $section'.toLowerCase();

        return name.contains(searchLower) ||
            className.contains(searchLower) ||
            section.contains(searchLower) ||
            subject.contains(searchLower) ||
            classSection.contains(searchLower);
      }).toList();
    });
  }

  void _selectUser(Map<String, dynamic> user) {
    setState(() {
      _selectedRecipientId = user['id'];
      _selectedRecipientName = user['name'];
      _selectedRecipientType = 'individual';
      _toController.text = user['name'];
      _composeSearchController.clear();
    });
  }

  void _selectClass(Map<String, dynamic> classInfo) {
    setState(() {
      _selectedRecipientId = classInfo['id'];
      _selectedRecipientName = classInfo['name'];
      _selectedRecipientType = 'class';
      _toController.text = classInfo['name'];
      _composeSearchController.clear();
    });
  }

  List<DropdownMenuItem<String>> _getRecipientTypeOptions() {
    List<DropdownMenuItem<String>> items = [];

    if (widget.userRole == 'admin') {
      items = [
        DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
        DropdownMenuItem(value: 'student', child: Text('Student')),
        DropdownMenuItem(value: 'class', child: Text('Class')),
        DropdownMenuItem(value: 'admin', child: Text('Admin')),
      ];
    } else if (widget.userRole == 'teacher') {
      items = [
        DropdownMenuItem(value: 'admin', child: Text('Admin')),
        DropdownMenuItem(value: 'student', child: Text('Student')),
        if (_availableClasses.isNotEmpty)
          DropdownMenuItem(value: 'class', child: Text('Class')),
      ];
    } else if (widget.userRole == 'student') {
      items = [
        DropdownMenuItem(value: 'admin', child: Text('Admin')),
        DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
      ];
    }

    return items;
  }

  String _getDefaultRoleFilter() {
    if (widget.userRole == 'admin') {
      return 'teacher';
    } else if (widget.userRole == 'teacher') {
      return 'admin';
    } else if (widget.userRole == 'student') {
      return 'teacher';
    }
    return '';
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.deepPurple;
      case 'teacher':
        return Colors.blue;
      case 'student':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Modern UI Components
  Widget _buildMessageCard(
    Map<String, dynamic> message,
    bool isInbox,
    int index,
  ) {
    final timestamp = (message['timestamp'] as Timestamp).toDate();
    final recipientDisplay = message['recipient_display'] as List<String>;
    final messageType = message['message_type'];

    return Dismissible(
      key: Key('${message['id']}_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        child: Icon(Icons.delete, color: Colors.white, size: 30),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete Message'),
            content: Text('Are you sure you want to delete this message?'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        _deleteMessage(message['id'], isInbox);
      },
      child: Card(
        elevation: 2,
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: kIsWeb ? 2 : 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          leading: CircleAvatar(
            backgroundColor: isInbox
                ? (message['is_read'] ? Colors.grey[300] : Colors.blue[100])
                : Colors.green[100],
            child: Icon(
              isInbox
                  ? Icons.email
                  : (messageType == 'class' ? Icons.class_ : Icons.send),
              color: isInbox
                  ? (message['is_read'] ? Colors.grey : Colors.blue)
                  : Colors.green,
              size: 20,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  isInbox
                      ? message['sender_name']
                      : recipientDisplay.isNotEmpty
                      ? recipientDisplay.join(', ')
                      : messageType == 'class'
                      ? 'Class'
                      : '${message['recipients'].length} recipient(s)',
                  style: TextStyle(
                    fontWeight: isInbox && !message['is_read']
                        ? FontWeight.bold
                        : FontWeight.w500,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                DateFormat('HH:mm').format(timestamp),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 4),
              Text(
                message['subject'],
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 2),
              Text(
                message['body'].length > 60
                    ? '${message['body'].substring(0, 60)}...'
                    : message['body'],
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (!isInbox && messageType == 'class')
                Container(
                  margin: EdgeInsets.only(top: 4),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Class Message',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          onTap: () {
            if (isInbox) _markAsRead(message['id']);
            _showMessageDetails(message, isInbox: isInbox);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[300]),
          SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'No messages found',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
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
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          SizedBox(height: 16),
          Text(
            'Loading messages...',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildClassSelector() {
    if (_availableClasses.isEmpty) {
      return Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.userRole == 'teacher'
                    ? 'No classes assigned to you in timetable'
                    : 'No classes available',
                style: TextStyle(color: Colors.orange[800], fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Class:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButton<String>(
            value: _selectedRecipientId,
            isExpanded: true,
            underline: SizedBox(),
            hint: Text('Select a class'),
            style: TextStyle(color: Colors.grey[800]),
            items: _availableClasses.map((classInfo) {
              return DropdownMenuItem<String>(
                value: classInfo['id'],
                child: Text(classInfo['name']),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                final classInfo = _availableClasses.firstWhere(
                  (c) => c['id'] == value,
                  orElse: () => {'id': '', 'name': ''},
                );
                _selectClass(classInfo);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecipientSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Recipient Type:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButton<String>(
            value: _selectedRoleFilter.isNotEmpty ? _selectedRoleFilter : null,
            isExpanded: true,
            underline: SizedBox(),
            hint: Text('Select recipient type'),
            style: TextStyle(color: Colors.grey[800]),
            items: _getRecipientTypeOptions(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedRoleFilter = value;
                  _selectedRecipientId = null;
                  _selectedRecipientName = null;
                  _toController.clear();
                  _composeSearchController.clear();
                  _applyUserSearch();
                });
              }
            },
          ),
        ),
        SizedBox(height: 16),

        if (_selectedRoleFilter == 'class') _buildClassSelector(),

        if (_selectedRoleFilter != 'class' && _selectedRoleFilter.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search ${_selectedRoleFilter == 'teacher'
                    ? 'Teachers'
                    : _selectedRoleFilter == 'student'
                    ? 'Students'
                    : 'Admins'}:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 8),
              TextField(
                controller: _composeSearchController,
                decoration: InputDecoration(
                  hintText: 'Search by name',
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                  suffixIcon: _composeSearchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _composeSearchController.clear();
                            _applyUserSearch();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
                onChanged: (value) => _applyUserSearch(),
              ),
              SizedBox(height: 12),

              if (_filteredUsers.isNotEmpty)
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final role = user['role']?.toString() ?? '';
                      final subject = user['subject']?.toString();

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getRoleColor(role),
                          child: Text(
                            user['name'][0].toUpperCase(),
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          user['name'],
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: _buildUserSubtitle(user),
                        trailing: _selectedRecipientId == user['id']
                            ? Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 20,
                              )
                            : null,
                        onTap: () => _selectUser(user),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    },
                  ),
                ),
              if (_filteredUsers.isEmpty &&
                  _composeSearchController.text.isNotEmpty)
                Container(
                  height: 100,
                  alignment: Alignment.center,
                  child: Text(
                    'No users found',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              if (_filteredUsers.isEmpty &&
                  _composeSearchController.text.isEmpty)
                Container(
                  height: 100,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group, size: 40, color: Colors.grey[300]),
                      SizedBox(height: 8),
                      Text(
                        'No ${_selectedRoleFilter}s available',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
            ],
          ),

        if (_selectedRecipientName != null)
          Padding(
            padding: EdgeInsets.only(top: 16),
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _selectedRecipientType == 'class'
                    ? Colors.green[50]
                    : Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedRecipientType == 'class'
                      ? Colors.green[200]!
                      : Colors.blue[200]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedRecipientType == 'class'
                        ? Icons.class_
                        : Icons.person,
                    color: _selectedRecipientType == 'class'
                        ? Colors.green
                        : Colors.blue,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedRecipientName!,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: _selectedRecipientType == 'class'
                                ? Colors.green[800]
                                : Colors.blue[800],
                          ),
                        ),
                        if (_selectedRecipientType == 'class')
                          Text(
                            'All Students',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[600],
                            ),
                          ),
                        if (_selectedRecipientType == 'individual' &&
                            _selectedRoleFilter == 'student')
                          Text(
                            'Class: ${_getSelectedUserClassSection()}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[600],
                            ),
                          ),
                        if (_selectedRecipientType == 'individual' &&
                            _selectedRoleFilter == 'teacher')
                          Text(
                            'Subject: ${_getSelectedUserSubject()}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16),
                    onPressed: () {
                      setState(() {
                        _selectedRecipientId = null;
                        _selectedRecipientName = null;
                        _toController.clear();
                        if (_selectedRecipientType == 'class') {
                          _selectedRoleFilter = _getDefaultRoleFilter();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _getSelectedUserClassSection() {
    if (_selectedRecipientId == null) return 'Unknown Class - Unknown Section';

    List<Map<String, dynamic>> sourceList = [];

    if (_selectedRoleFilter == 'student') {
      sourceList = (widget.userRole == 'admin' || widget.userRole == 'teacher')
          ? _availableStudents
          : [];
    } else if (_selectedRoleFilter == 'teacher') {
      sourceList = widget.userRole == 'admin'
          ? _availableTeachers
          : (widget.userRole == 'student' ? _availableTeachers : []);
    }

    final user = sourceList.firstWhere(
      (u) => u['id'] == _selectedRecipientId,
      orElse: () => {},
    );

    if (_selectedRoleFilter == 'student') {
      final className = user['class_name'] ?? 'Unknown Class';
      final section = user['section'] ?? 'Unknown Section';
      return '$className - $section';
    } else if (_selectedRoleFilter == 'teacher') {
      final subject = user['subject']?.toString();
      return subject ?? 'No subjects assigned';
    }

    return '';
  }

  String _getSelectedUserSubject() {
    if (_selectedRecipientId == null) return 'No subjects assigned';

    List<Map<String, dynamic>> sourceList = [];

    if (_selectedRoleFilter == 'teacher') {
      sourceList = widget.userRole == 'admin'
          ? _availableTeachers
          : (widget.userRole == 'student' ? _availableTeachers : []);
    }

    final user = sourceList.firstWhere(
      (u) => u['id'] == _selectedRecipientId,
      orElse: () => {},
    );

    return user['subject']?.toString() ?? 'No subjects assigned';
  }

  Widget _buildInboxTab() {
    List<Map<String, dynamic>> filteredMessages = _inboxMessages;

    if (_inboxSearchController.text.isNotEmpty) {
      final searchText = _inboxSearchController.text.toLowerCase();
      filteredMessages = _inboxMessages.where((message) {
        final subject = (message['subject'] ?? '').toString().toLowerCase();
        final body = (message['body'] ?? '').toString().toLowerCase();
        final senderName = (message['sender_name'] ?? '')
            .toString()
            .toLowerCase();

        return subject.contains(searchText) ||
            body.contains(searchText) ||
            senderName.contains(searchText);
      }).toList();
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _needsRecipientRefresh = true;
        });
        await _clearCache();
        await _loadInboxMessages();
        await _loadRecipients();
      },
      color: Colors.blue,
      backgroundColor: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.grey[50]!],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _inboxSearchController,
                          decoration: InputDecoration(
                            hintText:
                                'Search by sender, subject, or message...',
                            border: InputBorder.none,
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.grey[500],
                            ),
                            suffixIcon: _inboxSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _inboxSearchController.clear();
                                      });
                                    },
                                  )
                                : null,
                          ),
                          autofocus: false,
                          onChanged: (value) {
                            setState(() {});
                          },
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    Container(height: 40, width: 1, color: Colors.grey[300]),
                    IconButton(
                      icon: Icon(Icons.refresh, color: Colors.blue[600]),
                      onPressed: () async {
                        setState(() {
                          _needsRecipientRefresh = true;
                        });
                        await _clearCache();
                        await _loadInboxMessages();
                        await _loadRecipients();
                      },
                      tooltip: 'Refresh',
                    ),
                    SizedBox(width: 8),
                  ],
                ),
              ),
            ),

            if (_inboxMessages.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Messages',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 6),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            filteredMessages.length.toString(),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: 20),
                    if (_inboxMessages.any((msg) => !msg['is_read']))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Unread',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(width: 6),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _inboxMessages
                                  .where((msg) => !msg['is_read'])
                                  .length
                                  .toString(),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    Spacer(),
                    if (_inboxSearchController.text.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _inboxSearchController.clear();
                          });
                        },
                        icon: Icon(Icons.close, size: 14),
                        label: Text(
                          'Clear Search',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                        ),
                      ),
                  ],
                ),
              ),

            Expanded(
              child: _isLoadingInbox
                  ? _buildLoadingState()
                  : filteredMessages.isEmpty
                  ? _inboxSearchController.text.isNotEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 80,
                                  color: Colors.grey[300],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No messages found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Try different keywords',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[400],
                                  ),
                                ),
                                SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _inboxSearchController.clear();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[50],
                                    foregroundColor: Colors.blue[700],
                                  ),
                                  child: Text('Clear Search'),
                                ),
                              ],
                            ),
                          )
                        : _buildEmptyState('Your Inbox is Empty', Icons.inbox)
                  : ListView.builder(
                      controller: _inboxScrollController,
                      padding: EdgeInsets.only(bottom: 16),
                      itemCount: filteredMessages.length,
                      itemBuilder: (context, index) {
                        return _buildMessageCard(
                          filteredMessages[index],
                          true,
                          index,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSentTab() {
    List<Map<String, dynamic>> filteredSentMessages = _sentMessages;

    if (_sentSearchController.text.isNotEmpty) {
      final searchText = _sentSearchController.text.toLowerCase();
      filteredSentMessages = _sentMessages.where((message) {
        final subject = (message['subject'] ?? '').toString().toLowerCase();
        final body = (message['body'] ?? '').toString().toLowerCase();
        final recipients = (message['recipient_display']?.join(', ') ?? '')
            .toString()
            .toLowerCase();

        return subject.contains(searchText) ||
            body.contains(searchText) ||
            recipients.contains(searchText);
      }).toList();
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _needsRecipientRefresh = true;
        });
        await _clearCache();
        await _loadSentMessages();
        await _loadRecipients();
      },
      color: Colors.green,
      backgroundColor: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.grey[50]!],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _sentSearchController,
                          decoration: InputDecoration(
                            hintText: 'Search sent messages...',
                            border: InputBorder.none,
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.grey[500],
                            ),
                            suffixIcon: _sentSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _sentSearchController.clear();
                                      });
                                    },
                                  )
                                : null,
                          ),
                          autofocus: false,
                          onChanged: (value) {
                            setState(() {});
                          },
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    Container(height: 40, width: 1, color: Colors.grey[300]),
                    IconButton(
                      icon: Icon(Icons.refresh, color: Colors.green[600]),
                      onPressed: () async {
                        setState(() {
                          _needsRecipientRefresh = true;
                        });
                        await _clearCache();
                        await _loadSentMessages();
                        await _loadRecipients();
                      },
                      tooltip: 'Refresh',
                    ),
                    SizedBox(width: 8),
                  ],
                ),
              ),
            ),

            if (_sentMessages.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Sent Messages',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 6),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            filteredSentMessages.length.toString(),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Spacer(),
                    if (_sentSearchController.text.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _sentSearchController.clear();
                          });
                        },
                        icon: Icon(Icons.close, size: 14),
                        label: Text(
                          'Clear Search',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                        ),
                      ),
                  ],
                ),
              ),

            Expanded(
              child: _isLoadingSent
                  ? _buildLoadingState()
                  : filteredSentMessages.isEmpty
                  ? _sentSearchController.text.isNotEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 80,
                                  color: Colors.grey[300],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No sent messages found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Try different keywords',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[400],
                                  ),
                                ),
                                SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _sentSearchController.clear();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[50],
                                    foregroundColor: Colors.green[700],
                                  ),
                                  child: Text('Clear Search'),
                                ),
                              ],
                            ),
                          )
                        : _buildEmptyState('No Sent Messages', Icons.send)
                  : ListView.builder(
                      controller: _sentScrollController,
                      padding: EdgeInsets.only(bottom: 16),
                      itemCount: filteredSentMessages.length,
                      itemBuilder: (context, index) {
                        return _buildMessageCard(
                          filteredSentMessages[index],
                          false,
                          index,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposeTab() {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _needsRecipientRefresh = true;
        });
        await _loadRecipients();
      },
      color: Colors.orange,
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        controller: _composeScrollController,
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(kIsWeb ? 24 : 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height - 200,
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Compose Message',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.refresh, size: 20),
                              color: Colors.blue,
                              onPressed: () async {
                                setState(() {
                                  _needsRecipientRefresh = true;
                                });
                                await _loadRecipients();
                              },
                              tooltip: 'Refresh Recipients',
                            ),
                          ],
                        ),
                        SizedBox(height: 20),

                        if (_isLoadingRecipients)
                          Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.blue,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Loading recipients...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          _buildRecipientSelector(),

                        SizedBox(height: 24),

                        TextField(
                          controller: _subjectController,
                          focusNode: _subjectFocusNode,
                          decoration: InputDecoration(
                            labelText: 'Subject',
                            hintText: 'Enter message subject',
                            prefixIcon: Icon(Icons.subject),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          maxLines: 1,
                        ),

                        SizedBox(height: 20),

                        TextField(
                          controller: _bodyController,
                          focusNode: _bodyFocusNode,
                          decoration: InputDecoration(
                            labelText: 'Message',
                            hintText: 'Type your message here...',
                            alignLabelWithHint: true,
                            prefixIcon: Icon(Icons.message),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          maxLines: 8,
                          minLines: 6,
                        ),

                        SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isSendingMessage ? null : _sendMessage,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[600],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                              shadowColor: Colors.blue.withOpacity(0.3),
                            ),
                            child: _isSendingMessage
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text('Sending...'),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.send, size: 20),
                                      SizedBox(width: 12),
                                      Text(
                                        'Send Message',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        toolbarHeight: 100,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 8),
            Text(
              'Messages',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
          ],
        ),

        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              labelPadding: EdgeInsets.symmetric(vertical: 12),
              tabs: [
                Tab(
                  icon: Badge(
                    label: Text(
                      _inboxMessages
                          .where((msg) => !msg['is_read'])
                          .length
                          .toString(),
                      style: TextStyle(fontSize: 10),
                    ),
                    isLabelVisible:
                        _inboxMessages
                            .where((msg) => !msg['is_read'])
                            .isNotEmpty &&
                        _tabController.index != 0,
                    child: Icon(Icons.inbox, size: 22),
                  ),
                  text: 'Inbox',
                ),
                Tab(icon: Icon(Icons.send, size: 22), text: 'Sent'),
                Tab(icon: Icon(Icons.edit, size: 22), text: 'Compose'),
              ],
              indicatorColor: Colors.blue,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey[600],
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue[700]!, Colors.blue[500]!],
            ),
          ),
        ),
      ),
      body: isDesktop && _tabController.index == 2
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Material(
                          color: Colors.white,
                          child: TabBar(
                            tabs: [
                              Tab(
                                icon: Badge(
                                  label: Text(
                                    _inboxMessages
                                        .where((msg) => !msg['is_read'])
                                        .length
                                        .toString(),
                                    style: TextStyle(fontSize: 10),
                                  ),
                                  isLabelVisible: _inboxMessages
                                      .where((msg) => !msg['is_read'])
                                      .isNotEmpty,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inbox, size: 18),
                                      SizedBox(width: 4),
                                      Text('Inbox'),
                                    ],
                                  ),
                                ),
                              ),
                              Tab(
                                icon: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.send, size: 18),
                                    SizedBox(width: 4),
                                    Text('Sent'),
                                  ],
                                ),
                              ),
                            ],
                            indicatorColor: Colors.blue,
                            labelColor: Colors.blue,
                            unselectedLabelColor: Colors.grey[600],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [_buildInboxTab(), _buildSentTab()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: Colors.grey[300]),
                Expanded(flex: 3, child: _buildComposeTab()),
              ],
            )
          : TabBarView(
              controller: _tabController,
              children: [_buildInboxTab(), _buildSentTab(), _buildComposeTab()],
            ),
      floatingActionButton: _tabController.index != 2 && !isDesktop
          ? FloatingActionButton(
              onPressed: () {
                _resetComposeForm();
                setState(() {
                  _needsRecipientRefresh = true;
                });
                _tabController.animateTo(2);
                _loadRecipients();
              },
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.edit),
            )
          : null,
    );
  }

  void _showMessageDetails(
    Map<String, dynamic> message, {
    required bool isInbox,
  }) {
    final timestamp = (message['timestamp'] as Timestamp).toDate();
    final recipientDisplay = message['recipient_display'] as List<String>;
    final messageType = message['message_type'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: isInbox
                            ? Colors.blue[100]
                            : Colors.green[100],
                        child: Icon(
                          isInbox
                              ? Icons.email
                              : (messageType == 'class'
                                    ? Icons.class_
                                    : Icons.send),
                          color: isInbox ? Colors.blue : Colors.green,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message['subject'],
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              isInbox
                                  ? 'From: ${message['sender_name']}'
                                  : recipientDisplay.isNotEmpty
                                  ? 'To: ${recipientDisplay.join(', ')}'
                                  : messageType == 'class'
                                  ? 'To: Class'
                                  : 'To: ${message['recipients'].length} recipient(s)',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Divider(color: Colors.grey[300]),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey[500],
                      ),
                      SizedBox(width: 8),
                      Text(
                        DateFormat(
                          'EEE, MMM d, yyyy • h:mm a',
                        ).format(timestamp),
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      Spacer(),
                      if (isInbox && !message['is_read'])
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'NEW',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Message:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Text(
                      message['body'],
                      style: TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                  SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                          child: Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
