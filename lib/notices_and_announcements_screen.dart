import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

class NoticesAndAnnouncementsScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String adminId;

  const NoticesAndAnnouncementsScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.adminId,
  });

  @override
  State<NoticesAndAnnouncementsScreen> createState() =>
      _NoticesAndAnnouncementsScreenState();
}

class _NoticesAndAnnouncementsScreenState
    extends State<NoticesAndAnnouncementsScreen> {
  final _noticeTitleController = TextEditingController();
  final _noticeContentController = TextEditingController();
  final _announcementTitleController = TextEditingController();
  final _announcementContentController = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  List<String> _selectedUserIds = [];
  List<String> _selectedRoles = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  String _adminName = 'Admin';
  bool _showNotices = true;

  // Timer for auto-dismissing messages
  Timer? _messageTimer;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // Caching variables
  static const String _usersCacheKey = 'notices_users_cache';
  static const String _adminCacheKey = 'notices_admin_cache';
  static const String _noticesCacheKey = 'notices_messages_cache';
  static const String _announcementsCacheKey = 'announcements_messages_cache';
  SharedPreferences? _prefs;
  final Map<String, dynamic> _cache = {};

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  // Local capitalize function
  String capitalize(String s) {
    if (s.isEmpty) return s;
    return "${s[0].toUpperCase()}${s.substring(1).toLowerCase()}";
  }

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
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

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadUsers();
    _loadAdminName();
  }

  Future<void> _saveToCache(
    String key,
    dynamic data, {
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final preparedData = _prepareDataForCache(data);
      _cache[key] = {
        'data': preparedData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Also save to persistent storage for important data
      if (_prefs != null &&
          (key.contains(_usersCacheKey) || key.contains(_adminCacheKey))) {
        await _prefs!.setString(key, json.encode(preparedData));
      }
    } catch (e) {
      // Silent cache error - no logging
    }
  }

  dynamic _getFromCache(
    String key, {
    Duration maxAge = const Duration(hours: 1),
  }) {
    // Check memory cache first
    final cached = _cache[key];
    if (cached != null) {
      final timestamp = cached['timestamp'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age <= maxAge.inMilliseconds) {
        return _restoreDataFromCache(cached['data']);
      } else {
        _cache.remove(key);
      }
    }

    // Try persistent storage
    if (_prefs != null && _prefs!.containsKey(key)) {
      try {
        final dataString = _prefs!.getString(key);
        if (dataString != null) {
          final data = json.decode(dataString);
          final restoredData = _restoreDataFromCache(data);
          _cache[key] = {
            'data': data,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          return restoredData;
        }
      } catch (e) {
        _prefs!.remove(key);
      }
    }

    return null;
  }

  // Convert data for caching - handle Timestamp objects
  dynamic _prepareDataForCache(dynamic data) {
    if (data is Timestamp) {
      return {
        '__type': 'timestamp',
        'seconds': data.seconds,
        'nanoseconds': data.nanoseconds,
      };
    } else if (data is Map) {
      final result = <String, dynamic>{};
      for (final key in data.keys) {
        result[key] = _prepareDataForCache(data[key]);
      }
      return result;
    } else if (data is List) {
      return data.map(_prepareDataForCache).toList();
    }
    return data;
  }

  // Restore data from cache - convert back Timestamp objects
  dynamic _restoreDataFromCache(dynamic data) {
    if (data is Map) {
      if (data['__type'] == 'timestamp') {
        return Timestamp(data['seconds'], data['nanoseconds']);
      }
      final result = <String, dynamic>{};
      for (final key in data.keys) {
        result[key] = _restoreDataFromCache(data[key]);
      }
      return result;
    } else if (data is List) {
      return data.map(_restoreDataFromCache).toList();
    }
    return data;
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    // Try cache first
    final cacheKey = '${_usersCacheKey}_${widget.schoolCode}';
    final cachedUsers = _getFromCache(
      cacheKey,
      maxAge: const Duration(hours: 2),
    );
    if (cachedUsers != null) {
      setState(() {
        _users = List<Map<String, dynamic>>.from(cachedUsers);
        _isLoading = false;
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', whereIn: ['teacher', 'student'])
          .get();

      final usersList = snapshot.docs.map((doc) {
        final data = doc.data();

        // Debug: Print the actual data to see what fields exist
        print('User Data: $data');

        // Get the actual values from Firestore - check what fields actually exist
        final dynamic usernameValue = data['username'];
        final dynamic fullNameValue = data['full_name'];
        final dynamic roleValue = data['role'];
        final dynamic rollNumberValue = data['roll_number'];

        // Convert to strings with proper null handling
        final String username =
            _convertToString(usernameValue) ?? 'User ${doc.id}';
        final String fullName = _convertToString(fullNameValue) ?? '';
        final String role = _convertToString(roleValue) ?? 'unknown';
        final String rollNumber = _convertToString(rollNumberValue) ?? '';

        // Use full_name if available, otherwise use username
        final String displayName = fullName.isNotEmpty ? fullName : username;

        // Create display text with proper formatting
        String displayText;
        if (role == 'student') {
          if (rollNumber.isNotEmpty && rollNumber != 'N/A') {
            displayText = '$rollNumber. $displayName ($role)';
          } else {
            displayText = '$displayName ($role)';
          }
        } else {
          displayText = '$displayName ($role)';
        }

        return {
          'id': doc.id,
          'username': username,
          'full_name': fullName,
          'display_name': displayName,
          'role': role,
          'roll_number': rollNumber,
          'display_text': displayText,
        };
      }).toList();

      await _saveToCache(cacheKey, usersList);

      setState(() {
        _users = usersList;
        _isLoading = false;
      });

      // Debug: Print the final user list
      print('Loaded ${usersList.length} users');
      for (var user in usersList) {
        print('User: ${user['display_text']}');
      }
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        _showMessage('Error loading users: ${e.toString()}', true);
        _isLoading = false;
      });
    }
  }

  // Helper method to safely convert dynamic values to string
  String? _convertToString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.trim();
    return value.toString().trim();
  }

  Future<void> _forceRefreshUsers() async {
    // Clear cache for users
    final cacheKey = '${_usersCacheKey}_${widget.schoolCode}';
    _cache.remove(cacheKey);
    if (_prefs != null && _prefs!.containsKey(cacheKey)) {
      await _prefs!.remove(cacheKey);
    }

    // Reload users
    await _loadUsers();

    _showMessage('Users data refreshed', false);
  }

  Future<void> _loadAdminName() async {
    // Try cache first
    final cacheKey = '${_adminCacheKey}_${widget.adminId}';
    final cachedAdminName = _getFromCache(
      cacheKey,
      maxAge: const Duration(hours: 24),
    );
    if (cachedAdminName != null) {
      setState(() {
        _adminName = cachedAdminName;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.adminId)
          .get();

      final data = doc.data();
      if (data != null) {
        // Get full_name if available, otherwise use username
        final fullName = data['full_name']?.toString().trim();
        final username = data['username']?.toString().trim();

        // Ensure we always have a non-null string
        String adminName;
        if (fullName != null && fullName.isNotEmpty) {
          adminName = fullName;
        } else if (username != null && username.isNotEmpty) {
          adminName = username;
        } else {
          adminName = 'Admin';
        }

        await _saveToCache(cacheKey, adminName);

        setState(() {
          _adminName = adminName;
        });
      } else {
        setState(() {
          _adminName = 'Admin';
        });
      }
    } catch (e) {
      // Silent fail, use default
      setState(() {
        _adminName = 'Admin';
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredUsers() {
    if (_searchQuery.isEmpty) return _users;

    final searchLower = _searchQuery.toLowerCase();

    return _users.where((user) {
      final username = user['username']?.toString().toLowerCase() ?? '';
      final fullName = user['full_name']?.toString().toLowerCase() ?? '';
      final displayName = user['display_name']?.toString().toLowerCase() ?? '';

      return username.contains(searchLower) ||
          fullName.contains(searchLower) ||
          displayName.contains(searchLower);
    }).toList();
  }

  Future<void> _sendNotice() async {
    if (_noticeTitleController.text.isEmpty ||
        _noticeContentController.text.isEmpty ||
        _selectedUserIds.isEmpty) {
      _showMessage(
        'Please fill in all fields and select at least one recipient',
        true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('notices')
          .add({
            'title': _noticeTitleController.text,
            'content': _noticeContentController.text,
            'recipients': _selectedUserIds,
            'sender_id': widget.adminId,
            'sender_name': _adminName,
            'created_at': FieldValue.serverTimestamp(),
            'type': 'notice',
          });

      // Invalidate notices cache
      final noticesCacheKey = '${_noticesCacheKey}_${widget.schoolCode}';
      _cache.remove(noticesCacheKey);
      if (_prefs != null && _prefs!.containsKey(noticesCacheKey)) {
        await _prefs!.remove(noticesCacheKey);
      }

      _showMessage('Notice sent successfully', false);
      setState(() {
        _isLoading = false;
        _noticeTitleController.clear();
        _noticeContentController.clear();
        _selectedUserIds.clear();
        _searchQuery = '';
        _searchController.clear();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Error sending notice: ${e.toString()}', true);
    }
  }

  Future<void> _sendAnnouncement() async {
    if (_announcementTitleController.text.isEmpty ||
        _announcementContentController.text.isEmpty ||
        _selectedRoles.isEmpty) {
      _showMessage(
        'Please fill in all fields and select at least one recipient group',
        true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('announcements')
          .add({
            'title': _announcementTitleController.text,
            'content': _announcementContentController.text,
            'recipient_groups': _selectedRoles,
            'sender_id': widget.adminId,
            'sender_name': _adminName,
            'created_at': FieldValue.serverTimestamp(),
            'type': 'announcement',
          });

      // Invalidate announcements cache
      final announcementsCacheKey =
          '${_announcementsCacheKey}_${widget.schoolCode}';
      _cache.remove(announcementsCacheKey);
      if (_prefs != null && _prefs!.containsKey(announcementsCacheKey)) {
        await _prefs!.remove(announcementsCacheKey);
      }

      _showMessage('Announcement sent successfully', false);
      setState(() {
        _isLoading = false;
        _announcementTitleController.clear();
        _announcementContentController.clear();
        _selectedRoles.clear();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Error sending announcement: ${e.toString()}', true);
    }
  }

  Future<void> _deleteMessage(String messageId, bool isNotice) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this message?'),
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

    if (!confirm) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection(isNotice ? 'notices' : 'announcements')
          .doc(messageId)
          .delete();

      // Invalidate the appropriate cache
      final cacheKey = isNotice
          ? '${_noticesCacheKey}_${widget.schoolCode}'
          : '${_announcementsCacheKey}_${widget.schoolCode}';
      _cache.remove(cacheKey);
      if (_prefs != null && _prefs!.containsKey(cacheKey)) {
        await _prefs!.remove(cacheKey);
      }

      _showMessage('Message deleted successfully', false);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Error deleting message: ${e.toString()}', true);
    }
  }

  void _toggleView(bool showNotices) {
    setState(() {
      _showNotices = showNotices;
      _clearMessages();
      _searchController.clear();
      _searchQuery = '';
      _selectedUserIds.clear();
      _selectedRoles.clear();
      _noticeTitleController.clear();
      _noticeContentController.clear();
      _announcementTitleController.clear();
      _announcementContentController.clear();
    });
  }

  Future<void> _clearCache() async {
    _cache.clear();
    if (_prefs != null) {
      await _prefs!.clear();
    }
    _showMessage('Refreshed successfully', false);
    // Reload data
    _loadUsers();
    _loadAdminName();
  }

  // Main content that won't rebuild with sidebar
  Widget _buildMainContent() {
    return Column(
      children: [
        _buildDesktopTopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                          onPressed: _clearMessages,
                        ),
                      ],
                    ),
                  ),

                // Success Message
                if (_successMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_successMessage!)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _clearMessages,
                        ),
                      ],
                    ),
                  ),

                // Notice Form
                if (_showNotices) _buildNoticeForm(),
                // Announcement Form
                if (!_showNotices) _buildAnnouncementForm(),

                const SizedBox(height: 24),

                // Display Sent Messages
                _buildMessagesSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoticeForm() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send Personal Notice',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 21, 101, 192),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _noticeTitleController,
              decoration: const InputDecoration(
                labelText: 'Notice Title *',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noticeContentController,
              decoration: const InputDecoration(
                labelText: 'Notice Content *',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search Users',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Recipients *',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            _buildUserSelector(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sendNotice,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
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
                    : const Text(
                        'Send Notice',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncementForm() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send Announcement',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 21, 101, 192),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _announcementTitleController,
              decoration: const InputDecoration(
                labelText: 'Announcement Title *',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _announcementContentController,
              decoration: const InputDecoration(
                labelText: 'Announcement Content *',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Recipient Groups *',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: ['teacher', 'student'].map((role) {
                return FilterChip(
                  label: Text(capitalize(role)),
                  selected: _selectedRoles.contains(role),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedRoles.add(role);
                      } else {
                        _selectedRoles.remove(role);
                      }
                    });
                  },
                  selectedColor: Colors.blue[100],
                  checkmarkColor: Colors.blue[700],
                  labelStyle: TextStyle(
                    color: _selectedRoles.contains(role)
                        ? Colors.blue[700]
                        : Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sendAnnouncement,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
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
                    : const Text(
                        'Send Announcement',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _showNotices ? 'Sent Notices' : 'Sent Announcements',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 21, 101, 192),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: _buildMessagesStream(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesStream() {
    final collection = _showNotices ? 'notices' : 'announcements';
    final cacheKey = _showNotices
        ? '${_noticesCacheKey}_${widget.schoolCode}'
        : '${_announcementsCacheKey}_${widget.schoolCode}';

    // Try cache first for initial data
    final cachedMessages = _getFromCache(
      cacheKey,
      maxAge: const Duration(minutes: 5),
    );

    // If we have valid cached data, use it directly
    if (cachedMessages != null &&
        cachedMessages is List &&
        cachedMessages.isNotEmpty) {
      return _buildMessagesList(cachedMessages);
    }

    // Only use StreamBuilder if we don't have cached data
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection(collection)
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading messages: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              _showNotices
                  ? 'No notices sent yet'
                  : 'No announcements sent yet',
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }

        final docs = snapshot.data!.docs;
        final messages = docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {'id': doc.id, ...data};
        }).toList();

        // Cache the messages for future use
        _saveToCache(cacheKey, messages);

        return _buildMessagesList(messages);
      },
    );
  }

  Widget _buildMessagesList(List<dynamic> messages) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final data = messages[index] as Map<String, dynamic>;
        final timestamp = data['created_at'] as Timestamp?;
        final date = timestamp != null
            ? DateFormat('MMM dd, yyyy HH:mm').format(timestamp.toDate())
            : 'Unknown';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Delete button in a row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          data['title'] ?? 'No Title',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                          size: 20,
                        ),
                        onPressed: () =>
                            _deleteMessage(data['id'], _showNotices),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Message content
                  Text(
                    data['content'] ?? 'No Content',
                    style: const TextStyle(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Metadata
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'By: ${data['sender_name'] ?? 'Admin'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              date,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (_showNotices)
                        Text(
                          'To: ${data['recipients']?.length ?? 0} user(s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      if (!_showNotices)
                        Text(
                          'To: ${(data['recipient_groups'] as List<dynamic>?)?.map((e) => capitalize(e.toString())).join(', ') ?? 'Unknown'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserSelector() {
    final filteredUsers = _getFilteredUsers();
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: _users.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No users available'),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: filteredUsers.length,
              itemBuilder: (context, index) {
                final user = filteredUsers[index];
                final isSelected = _selectedUserIds.contains(user['id']);

                // Safely get display text with fallback
                final displayText =
                    user['display_text'] ??
                    '${user['display_name'] ?? 'Unknown User'} (${user['role'] ?? 'unknown'})';

                return CheckboxListTile(
                  title: Text(displayText),
                  value: isSelected,
                  onChanged: (selected) {
                    setState(() {
                      if (selected!) {
                        _selectedUserIds.add(user['id']);
                      } else {
                        _selectedUserIds.remove(user['id']);
                      }
                    });
                  },
                );
              },
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
              Navigator.of(context).pop();
            },
            tooltip: 'Back to Dashboard',
          ),
          Text(
            _showNotices ? 'Send Notices' : 'Send Announcements',
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
          // Refresh users button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _forceRefreshUsers,
            tooltip: 'Refresh Users',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.clear_all, color: Colors.blue),
            onPressed: _clearCache,
            tooltip: 'Clear All Cache',
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopToggleButton(String title, bool isNotices) {
    final isSelected = _showNotices == isNotices;
    return GestureDetector(
      onTap: () => _toggleView(isNotices),
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

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar with auto-slide that doesn't affect main content
        _InfoSidebar(schoolName: widget.schoolName),
        // Main Content - separated to prevent rebuilds
        Expanded(child: _buildMainContent()),
      ],
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isMobile
              ? 'Messages'
              : '${widget.schoolName} - ${_showNotices ? 'Notices' : 'Announcements'}',
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color.fromARGB(255, 21, 101, 192),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showNotices ? Icons.campaign : Icons.notifications),
            onPressed: () => _toggleView(!_showNotices),
            tooltip: _showNotices
                ? 'Switch to Announcements'
                : 'Switch to Notices',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear_cache') {
                _clearCache();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'clear_cache',
                child: Text('refresh'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(_isMobile ? 16 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toggle between Notices and Announcements
                  if (!_isDesktop)
                    Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _toggleView(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _showNotices
                                      ? Colors.blue[700]
                                      : Colors.grey[200],
                                  foregroundColor: _showNotices
                                      ? Colors.white
                                      : Colors.grey[700],
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('Notices'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _toggleView(false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: !_showNotices
                                      ? Colors.blue[700]
                                      : Colors.grey[200],
                                  foregroundColor: !_showNotices
                                      ? Colors.white
                                      : Colors.grey[700],
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('Announcements'),
                              ),
                            ),
                          ],
                        ),
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
                          const Icon(Icons.error, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_errorMessage!)),
                        ],
                      ),
                    ),

                  // Success Message
                  if (_successMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_successMessage!)),
                        ],
                      ),
                    ),

                  // Notice Form
                  if (_showNotices) _buildNoticeForm(),
                  // Announcement Form
                  if (!_showNotices) _buildAnnouncementForm(),

                  const SizedBox(height: 20),

                  // Display Sent Messages
                  _buildMessagesSection(),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _noticeTitleController.dispose();
    _noticeContentController.dispose();
    _announcementTitleController.dispose();
    _announcementContentController.dispose();
    _searchController.dispose();
    _messageTimer?.cancel();
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
class _InfoSidebar extends StatefulWidget {
  final String schoolName;

  const _InfoSidebar({required this.schoolName});

  @override
  State<_InfoSidebar> createState() => _InfoSidebarState();
}

class _InfoSidebarState extends State<_InfoSidebar> {
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
            'How to Use Notices & Announcements',
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
            'Send targeted messages to specific users or groups',
          ),
          _buildInfoItem(
            Icons.campaign,
            'Broadcast Announcements',
            'Send messages to all teachers or students at once',
          ),
          _buildInfoItem(
            Icons.search,
            'User Selection',
            'Search and select specific recipients for notices',
          ),
          _buildInfoItem(
            Icons.delete,
            'Manage Messages',
            'View and delete sent notices and announcements',
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
            'Best Practices & Tips',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            '📝',
            'Use clear and concise titles for better readability',
          ),
          _buildTipItem(
            '🎯',
            'Send notices for individual communication, announcements for group messages',
          ),
          _buildTipItem(
            '🔍',
            'Use the search feature to quickly find specific users',
          ),
          _buildTipItem(
            '💾',
            'The app automatically caches data to reduce loading times',
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
              'Deleted messages cannot be recovered. Make sure before deleting any message.',
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
                  'Notices & Announcements',
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
