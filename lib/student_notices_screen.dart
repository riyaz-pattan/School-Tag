import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'message_detail_screen.dart';
import 'student_dashboard_screen.dart';

class StudentNoticesScreen extends StatefulWidget {
  final String schoolCode;
  final String userId;
  final String schoolName;
  final String studentId;
  final String studentName;

  const StudentNoticesScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentNoticesScreen> createState() => _StudentNoticesScreenState();
}

class _StudentNoticesScreenState extends State<StudentNoticesScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  bool _showNotices = true;
  Set<String> _readMessages = {};
  String? _newestMessageId;
  DateTime? _lastNewMessageTime;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // Cache management
  final Map<String, dynamic> _noticesCache = {};
  final Map<String, dynamic> _announcementsCache = {};

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  void initState() {
    super.initState();
    _loadData();
    _printLog('Screen initialized for student: ${widget.studentName}');
  }

  void _printLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    print('[$timestamp] StudentNotices: $message');
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    _printLog('Starting data load...');

    await Future.wait([
      _loadReadMessages(),
      _loadNewestMessageInfo(),
      _loadCachedMessages(),
    ]);

    setState(() {
      _isLoading = false;
    });

    _printLog('Data load completed');
  }

  Future<void> _loadReadMessages() async {
    _printLog('Loading read messages from cache...');
    final prefs = await SharedPreferences.getInstance();
    final key = 'readMessages_${widget.schoolCode}_${widget.studentId}';
    final readMessagesList = prefs.getStringList(key) ?? [];
    setState(() {
      _readMessages = Set<String>.from(readMessagesList);
    });
    _printLog('Loaded ${_readMessages.length} read messages from cache');
  }

  Future<void> _loadNewestMessageInfo() async {
    _printLog('Loading newest message info from cache...');
    final prefs = await SharedPreferences.getInstance();
    final newestMessageIdKey =
        'newestMessageId_${widget.schoolCode}_${widget.studentId}';
    final lastNewMessageTimeKey =
        'lastNewMessageTime_${widget.schoolCode}_${widget.studentId}';

    setState(() {
      _newestMessageId = prefs.getString(newestMessageIdKey);
      final lastTimeMillis = prefs.getInt(lastNewMessageTimeKey);
      _lastNewMessageTime = lastTimeMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(lastTimeMillis)
          : null;
    });
    _printLog(
      'Newest message ID: $_newestMessageId, Last update: $_lastNewMessageTime',
    );
  }

  Future<void> _loadCachedMessages() async {
    _printLog('Loading cached messages...');
    final prefs = await SharedPreferences.getInstance();

    // Load cached notices
    final noticesKey = 'cachedNotices_${widget.schoolCode}_${widget.studentId}';
    final noticesTimestampKey =
        'cachedNoticesTimestamp_${widget.schoolCode}_${widget.studentId}';

    final cachedNotices = prefs.getString(noticesKey);
    final noticesTimestamp = prefs.getInt(noticesTimestampKey);

    if (cachedNotices != null && noticesTimestamp != null) {
      final cacheAge = DateTime.now().millisecondsSinceEpoch - noticesTimestamp;
      if (cacheAge < 5 * 60 * 1000) {
        // 5 minutes cache
        try {
          final decodedData = jsonDecode(cachedNotices);
          _noticesCache['data'] = decodedData;
          _noticesCache['timestamp'] = noticesTimestamp;
          _printLog(
            'Loaded ${decodedData.length} notices from cache (age: ${cacheAge ~/ 1000}s)',
          );
        } catch (e) {
          _printLog('Error decoding notices cache: $e');
          // Clear invalid cache
          await prefs.remove(noticesKey);
          await prefs.remove(noticesTimestampKey);
        }
      } else {
        _printLog('Notices cache expired (age: ${cacheAge ~/ 1000}s)');
      }
    }

    // Load cached announcements
    final announcementsKey =
        'cachedAnnouncements_${widget.schoolCode}_${widget.studentId}';
    final announcementsTimestampKey =
        'cachedAnnouncementsTimestamp_${widget.schoolCode}_${widget.studentId}';

    final cachedAnnouncements = prefs.getString(announcementsKey);
    final announcementsTimestamp = prefs.getInt(announcementsTimestampKey);

    if (cachedAnnouncements != null && announcementsTimestamp != null) {
      final cacheAge =
          DateTime.now().millisecondsSinceEpoch - announcementsTimestamp;
      if (cacheAge < 5 * 60 * 1000) {
        // 5 minutes cache
        try {
          final decodedData = jsonDecode(cachedAnnouncements);
          _announcementsCache['data'] = decodedData;
          _announcementsCache['timestamp'] = announcementsTimestamp;
          _printLog(
            'Loaded ${decodedData.length} announcements from cache (age: ${cacheAge ~/ 1000}s)',
          );
        } catch (e) {
          _printLog('Error decoding announcements cache: $e');
          // Clear invalid cache
          await prefs.remove(announcementsKey);
          await prefs.remove(announcementsTimestampKey);
        }
      } else {
        _printLog('Announcements cache expired (age: ${cacheAge ~/ 1000}s)');
      }
    }
  }

  Future<void> _updateNewestMessageInfo(
    String messageId,
    DateTime messageTime,
  ) async {
    _printLog('Updating newest message info: $messageId');
    final prefs = await SharedPreferences.getInstance();
    final newestMessageIdKey =
        'newestMessageId_${widget.schoolCode}_${widget.studentId}';
    final lastNewMessageTimeKey =
        'lastNewMessageTime_${widget.schoolCode}_${widget.studentId}';

    await prefs.setString(newestMessageIdKey, messageId);
    await prefs.setInt(
      lastNewMessageTimeKey,
      messageTime.millisecondsSinceEpoch,
    );

    setState(() {
      _newestMessageId = messageId;
      _lastNewMessageTime = messageTime;
    });
  }

  Future<void> _markAsRead(String messageId) async {
    _printLog('Marking message as read: $messageId');
    setState(() {
      _readMessages.add(messageId);
    });

    final prefs = await SharedPreferences.getInstance();
    final key = 'readMessages_${widget.schoolCode}_${widget.studentId}';
    await prefs.setStringList(key, _readMessages.toList());
  }

  // Convert Firestore data to serializable format
  Map<String, dynamic> _convertToSerializable(Map<String, dynamic> data) {
    final converted = Map<String, dynamic>.from(data);

    // Convert Timestamp to milliseconds since epoch
    if (converted['created_at'] is Timestamp) {
      converted['created_at'] =
          (converted['created_at'] as Timestamp).millisecondsSinceEpoch;
    }

    // Convert any other Timestamp fields if they exist
    converted.forEach((key, value) {
      if (value is Timestamp) {
        converted[key] = value.millisecondsSinceEpoch;
      }
    });

    return converted;
  }

  // Convert serialized data back to Firestore format
  Map<String, dynamic> _convertFromSerializable(Map<String, dynamic> data) {
    final converted = Map<String, dynamic>.from(data);

    // Convert milliseconds back to DateTime for display
    if (converted['created_at'] is int) {
      converted['created_at'] = DateTime.fromMillisecondsSinceEpoch(
        converted['created_at'],
      );
    }

    return converted;
  }

  String _safeConvertToString(
    dynamic value, {
    String defaultValue = 'Unknown',
  }) {
    if (value == null) return defaultValue;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? defaultValue : trimmed;
    }
    return value.toString().trim();
  }

  Future<void> _cacheMessages(
    List<DocumentSnapshot> messages,
    bool isNotices,
  ) async {
    _printLog(
      'Caching ${messages.length} ${isNotices ? 'notices' : 'announcements'}',
    );
    final prefs = await SharedPreferences.getInstance();

    final messagesData = messages.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {'id': doc.id, 'data': _convertToSerializable(data)};
    }).toList();

    final key = isNotices
        ? 'cachedNotices_${widget.schoolCode}_${widget.studentId}'
        : 'cachedAnnouncements_${widget.schoolCode}_${widget.studentId}';

    final timestampKey = isNotices
        ? 'cachedNoticesTimestamp_${widget.schoolCode}_${widget.studentId}'
        : 'cachedAnnouncementsTimestamp_${widget.schoolCode}_${widget.studentId}';

    try {
      await prefs.setString(key, jsonEncode(messagesData));
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);

      if (isNotices) {
        _noticesCache['data'] = messagesData;
        _noticesCache['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      } else {
        _announcementsCache['data'] = messagesData;
        _announcementsCache['timestamp'] =
            DateTime.now().millisecondsSinceEpoch;
      }
      _printLog('Cache saved successfully');
    } catch (e) {
      _printLog('Error saving cache: $e');
    }
  }

  bool _isNewMessage(String messageId) {
    return messageId == _newestMessageId;
  }

  bool _isUnread(String messageId) {
    return !_readMessages.contains(messageId);
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return DateFormat('MMM dd, yyyy HH:mm').format(timestamp.toDate());
    } else if (timestamp is DateTime) {
      return DateFormat('MMM dd, yyyy HH:mm').format(timestamp);
    } else if (timestamp is int) {
      return DateFormat(
        'MMM dd, yyyy HH:mm',
      ).format(DateTime.fromMillisecondsSinceEpoch(timestamp));
    } else {
      return 'Unknown date';
    }
  }

  void _openMessageDetail(
    Map<String, dynamic> message,
    String messageId,
    bool isNotice,
  ) {
    _markAsRead(messageId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MessageDetailScreen(
          message: message,
          isNotice: isNotice,
          userType: 'student',
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar with auto-slide
        _StudentInfoSidebar(
          schoolName: widget.schoolName,
          studentName: widget.studentName,
        ),
        // Main Content
        Expanded(
          child: Column(
            children: [
              _buildDesktopTopBar(),
              Expanded(
                child: _showNotices
                    ? _buildMessagesStream(true)
                    : _buildMessagesStream(false),
              ),
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
              color: Color.fromARGB(255, 21, 101, 192),
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
          Text(
            _showNotices ? 'Personal Notices' : 'School Announcements',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
          // Toggle buttons for desktop
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildDesktopToggleButton('Notices', true),
                _buildDesktopToggleButton('Announcements', false),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _refreshData,
            tooltip: 'Refresh Messages',
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopToggleButton(String title, bool isNotices) {
    final isSelected = _showNotices == isNotices;
    return GestureDetector(
      onTap: () {
        setState(() {
          _showNotices = isNotices;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[700] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem(DocumentSnapshot doc, bool isNotice) {
    final message = doc.data() as Map<String, dynamic>;
    final messageId = doc.id;
    final timestamp = message['created_at'];
    final date = _formatTimestamp(timestamp);
    final isUnread = _isUnread(messageId);
    final isNew = _isNewMessage(messageId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openMessageDetail(message, messageId, isNotice),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row with red dot for unread messages
              Row(
                children: [
                  if (isUnread)
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      margin: const EdgeInsets.only(right: 12),
                    ),
                  Expanded(
                    child: Text(
                      message['title'] ?? 'No Title',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isUnread ? Colors.blue[900] : Colors.grey[800],
                      ),
                    ),
                  ),
                  if (isNew)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            size: 14,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'NEW',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message['is_urgent'] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'URGENT',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                message['content'] ?? 'No Content',
                style: const TextStyle(fontSize: 16, height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Divider(color: Colors.grey[300]),
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'By: ${_safeConvertToString(message['sender_name'], defaultValue: 'Admin')}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    date,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isNotice ? Colors.blue[50] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isNotice ? Colors.blue : Colors.blue,
                    width: 1,
                  ),
                ),
                child: Text(
                  isNotice
                      ? '🔒 Sent specifically to you'
                      : '📢 Sent to all students',
                  style: TextStyle(
                    fontSize: 12,
                    color: isNotice ? Colors.blue[700] : Colors.blue[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCachedMessageItem(
    Map<String, dynamic> cachedMessage,
    bool isNotice,
  ) {
    final messageId = cachedMessage['id'];
    final serializedData = cachedMessage['data'] as Map<String, dynamic>;
    final message = _convertFromSerializable(serializedData);
    final timestamp = message['created_at'];
    final date = _formatTimestamp(timestamp);
    final isUnread = _isUnread(messageId);
    final isNew = _isNewMessage(messageId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.grey[50],
      child: InkWell(
        onTap: () => _openMessageDetail(message, messageId, isNotice),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isUnread)
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      margin: const EdgeInsets.only(right: 12),
                    ),
                  Expanded(
                    child: Text(
                      message['title'] ?? 'No Title',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isUnread ? Colors.blue[900] : Colors.grey[800],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Text(
                      'CACHED',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                message['content'] ?? 'No Content',
                style: const TextStyle(fontSize: 16, height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Divider(color: Colors.grey[300]),
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'By: ${_safeConvertToString(message['sender_name'], defaultValue: 'Admin')}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    date,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesStream(bool isNotices) {
    _printLog('Building ${isNotices ? 'notices' : 'announcements'} stream');

    // Show cached data while loading
    final cachedData = isNotices
        ? _noticesCache['data']
        : _announcementsCache['data'];
    final hasCachedData =
        cachedData != null && cachedData is List && cachedData.isNotEmpty;

    return StreamBuilder<QuerySnapshot>(
      stream: isNotices
          ? FirebaseFirestore.instance
                .collection('schools')
                .doc(widget.schoolCode)
                .collection('notices')
                .where('recipients', arrayContains: widget.studentId)
                .orderBy('created_at', descending: true)
                .snapshots()
          : FirebaseFirestore.instance
                .collection('schools')
                .doc(widget.schoolCode)
                .collection('announcements')
                .where('recipient_groups', arrayContains: 'student')
                .orderBy('created_at', descending: true)
                .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          _printLog(
            'Stream waiting - ${hasCachedData ? 'showing cached data' : 'no cache available'}',
          );

          if (hasCachedData) {
            return ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: cachedData.length,
              itemBuilder: (context, index) {
                final cachedMessage = cachedData[index];
                return _buildCachedMessageItem(cachedMessage, isNotices);
              },
            );
          }

          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          _printLog('Stream error: ${snapshot.error}');

          if (hasCachedData) {
            _printLog('Showing cached data due to error');
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Showing cached data (connection issue)',
                          style: TextStyle(color: Colors.orange[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: cachedData.length,
                    itemBuilder: (context, index) {
                      final cachedMessage = cachedData[index];
                      return _buildCachedMessageItem(cachedMessage, isNotices);
                    },
                  ),
                ),
              ],
            );
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Error loading messages',
                  style: TextStyle(fontSize: 16, color: Colors.red),
                ),
                Text(
                  snapshot.error.toString(),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          _printLog('No data available from stream');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isNotices
                      ? Icons.notifications_none
                      : Icons.campaign_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  isNotices
                      ? 'No notices received'
                      : 'No announcements received',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  isNotices
                      ? 'Notices sent specifically to you will appear here'
                      : 'Announcements sent to all students will appear here',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final messages = snapshot.data!.docs;
        _printLog(
          'Received ${messages.length} ${isNotices ? 'notices' : 'announcements'} from Firebase',
        );

        // Cache the messages
        _cacheMessages(messages, isNotices);

        // Check for new messages and update newest message info
        if (messages.isNotEmpty) {
          final latestMessage = messages.first;
          final latestMessageId = latestMessage.id;
          final latestMessageData =
              latestMessage.data() as Map<String, dynamic>;
          final latestTimestamp = latestMessageData['created_at'];
          DateTime latestMessageTime;

          if (latestTimestamp is Timestamp) {
            latestMessageTime = latestTimestamp.toDate();
          } else if (latestTimestamp is DateTime) {
            latestMessageTime = latestTimestamp;
          } else {
            latestMessageTime = DateTime.now();
          }

          // Update if this is a newer message than what we have stored
          if (_newestMessageId == null ||
              _lastNewMessageTime == null ||
              latestMessageTime.isAfter(_lastNewMessageTime!)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateNewestMessageInfo(latestMessageId, latestMessageTime);
            });
          }
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final messageDoc = messages[index];
            return _buildMessageItem(messageDoc, isNotices);
          },
        );
      },
    );
  }

  Future<void> _refreshData() async {
    _printLog('Manual refresh triggered');

    // Clear cache
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(
      'cachedNotices_${widget.schoolCode}_${widget.studentId}',
    );
    await prefs.remove(
      'cachedNoticesTimestamp_${widget.schoolCode}_${widget.studentId}',
    );
    await prefs.remove(
      'cachedAnnouncements_${widget.schoolCode}_${widget.studentId}',
    );
    await prefs.remove(
      'cachedAnnouncementsTimestamp_${widget.schoolCode}_${widget.studentId}',
    );

    setState(() {
      _noticesCache.clear();
      _announcementsCache.clear();
    });

    await _loadData();
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.notifications, color: Colors.white),
            SizedBox(width: 12),
            Text(
              '${widget.schoolName} - Messages',
              style: TextStyle(fontSize: _isDesktop ? 20 : 18),
            ),
          ],
        ),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh Messages',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : Column(
              children: [
                // Toggle between Notices and Announcements
                Card(
                  margin: _isDesktop ? EdgeInsets.all(20) : EdgeInsets.all(16),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _showNotices = true;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _showNotices
                                  ? Colors.blue[700]
                                  : Colors.grey[200],
                              foregroundColor: _showNotices
                                  ? Colors.white
                                  : Colors.grey[700],
                              elevation: _showNotices ? 4 : 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_active),
                                SizedBox(height: 8),
                                StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('schools')
                                      .doc(widget.schoolCode)
                                      .collection('notices')
                                      .where(
                                        'recipients',
                                        arrayContains: widget.studentId,
                                      )
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    final count = snapshot.hasData
                                        ? snapshot.data!.docs.length
                                        : 0;
                                    final unreadCount = snapshot.hasData
                                        ? snapshot.data!.docs
                                              .where((doc) => _isUnread(doc.id))
                                              .length
                                        : 0;

                                    return Column(
                                      children: [
                                        Text('Notices ($count)'),
                                        if (unreadCount > 0) ...[
                                          SizedBox(height: 4),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$unreadCount',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _showNotices = false;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: !_showNotices
                                  ? Colors.blue[700]
                                  : Colors.grey[200],
                              foregroundColor: !_showNotices
                                  ? Colors.white
                                  : Colors.grey[700],
                              elevation: !_showNotices ? 4 : 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.campaign),
                                SizedBox(height: 8),
                                StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('schools')
                                      .doc(widget.schoolCode)
                                      .collection('announcements')
                                      .where(
                                        'recipient_groups',
                                        arrayContains: 'student',
                                      )
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    final count = snapshot.hasData
                                        ? snapshot.data!.docs.length
                                        : 0;
                                    final unreadCount = snapshot.hasData
                                        ? snapshot.data!.docs
                                              .where((doc) => _isUnread(doc.id))
                                              .length
                                        : 0;

                                    return Column(
                                      children: [
                                        Text('Announcements ($count)'),
                                        if (unreadCount > 0) ...[
                                          SizedBox(height: 4),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$unreadCount',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _showNotices
                      ? _buildMessagesStream(true)
                      : _buildMessagesStream(false),
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
          CircularProgressIndicator(strokeWidth: 3),
          SizedBox(height: 16),
          Text(
            'Loading Messages...',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          SizedBox(height: 8),
          Text(
            'Checking cache and fetching updates',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
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
class _StudentInfoSidebar extends StatefulWidget {
  final String schoolName;
  final String studentName;

  const _StudentInfoSidebar({
    required this.schoolName,
    required this.studentName,
  });

  @override
  State<_StudentInfoSidebar> createState() => _StudentInfoSidebarState();
}

class _StudentInfoSidebarState extends State<_StudentInfoSidebar> {
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
            'Understanding Your Messages',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.notifications_active,
            'Personal Notices',
            'Messages sent specifically to you by school administration',
          ),
          _buildInfoItem(
            Icons.campaign,
            'Announcements',
            'Important updates sent to all students in the school',
          ),
          _buildInfoItem(
            Icons.circle,
            'Red Dot Indicator',
            'Shows unread messages that you haven\'t opened yet',
          ),
          _buildInfoItem(
            Icons.local_fire_department,
            'NEW Badge',
            'Highlights the most recent messages you\'ve received',
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
            'Tips for Students',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            '👁️',
            'Check both notices and announcements regularly',
          ),
          _buildTipItem(
            '🔔',
            'Pay special attention to messages with URGENT badges',
          ),
          _buildTipItem(
            '📱',
            'Messages are automatically cached for offline reading',
          ),
          _buildTipItem(
            '🔄',
            'Use the refresh button to get the latest messages',
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
              'Always read messages carefully as they may contain important information about classes, exams, or school events.',
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
              color: Colors.blue[50],
              border: Border(bottom: BorderSide(color: Colors.blue[100]!)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.notifications,
                  size: 40,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Student Messages',
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
                const SizedBox(height: 8),
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
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
