import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MessageDetailScreen extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isNotice;
  final String userType;

  const MessageDetailScreen({
    super.key,
    required this.message,
    required this.isNotice,
    required this.userType,
  });

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  bool _isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;
  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool _isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return DateFormat('MMM dd, yyyy HH:mm').format(timestamp.toDate());
    } else if (timestamp is DateTime) {
      return DateFormat('MMM dd, yyyy HH:mm').format(timestamp);
    } else {
      return 'Unknown date';
    }
  }

  // Helper method to safely get display name
  String _getDisplayName(Map<String, dynamic> message) {
    final senderName = message['sender_name'];
    if (senderName == null) return 'Admin';

    final nameString = senderName.toString().trim();
    return nameString.isEmpty ? 'Admin' : nameString;
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Info Sidebar
          _buildDesktopSidebar(context),
          // Main Content
          Expanded(
            child: Column(
              children: [
                _buildDesktopTopBar(context),
                Expanded(child: _buildMessageContent(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context) {
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
                Icon(
                  isNotice ? Icons.notifications_active : Icons.campaign,
                  size: 40,
                  color: const Color.fromARGB(255, 21, 101, 192),
                ),
                const SizedBox(height: 8),
                Text(
                  isNotice ? 'Notice Details' : 'Announcement Details',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Message Information',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Info Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About This Message',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 21, 101, 192),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoItem(
                    Icons.person,
                    'Sender',
                    _getDisplayName(message),
                  ),
                  _buildInfoItem(
                    Icons.access_time,
                    'Sent',
                    _formatTimestamp(message['created_at']),
                  ),
                  _buildInfoItem(
                    isNotice ? Icons.lock : Icons.public,
                    'Audience',
                    isNotice
                        ? '🔒 Personal Message'
                        : userType == 'student'
                        ? '📢 All Students'
                        : '📢 All Teachers',
                  ),
                  if (message['is_urgent'] == true)
                    _buildInfoItem(
                      Icons.warning,
                      'Priority',
                      'URGENT - Requires Immediate Attention',
                      isUrgent: true,
                    ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: const Text(
                      'This message contains important information from your school administration. Please read it carefully.',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
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

  Widget _buildInfoItem(
    IconData icon,
    String label,
    String value, {
    bool isUrgent = false,
  }) {
    // Safely handle the value to ensure proper display
    final displayValue = value.trim().isEmpty ? 'Admin' : value;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: isUrgent ? Colors.red : Colors.blue[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: 14,
                    color: isUrgent ? Colors.red : Colors.grey[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTopBar(BuildContext context) {
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
            tooltip: 'Back to Messages',
          ),
          Expanded(
            child: Text(
              message['title'] ?? 'Message Details',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 21, 101, 192),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (message['is_urgent'] == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, size: 16, color: Colors.red),
                  SizedBox(width: 4),
                  Text(
                    'URGENT',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message content card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message['title'] ?? 'No Title',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    message['content'] ?? 'No Content',
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTabletLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isNotice ? 'Notice Details' : 'Announcement Details'),
        backgroundColor: userType == 'student'
            ? Colors.blue[700]
            : Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(_isMobile(context) ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and badges
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message['title'] ?? 'No Title',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (message['is_urgent'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'URGENT',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Metadata row
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _buildMetadataChip(
                          Icons.person,
                          'From: ${_getDisplayName(message)}',
                        ),
                        _buildMetadataChip(
                          Icons.access_time,
                          'Sent: ${_formatTimestamp(message['created_at'])}',
                        ),
                        _buildMetadataChip(
                          isNotice ? Icons.lock : Icons.public,
                          isNotice
                              ? 'Personal Message'
                              : userType == 'student'
                              ? 'All Students'
                              : 'All Teachers',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Message content
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  message['content'] ?? 'No Content',
                  style: const TextStyle(fontSize: 16, height: 1.6),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Additional information
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Message Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 21, 101, 192),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Type', isNotice ? 'Notice' : 'Announcement'),
                    _buildInfoRow(
                      'Audience',
                      isNotice
                          ? 'Sent specifically to you'
                          : userType == 'student'
                          ? 'Sent to all students'
                          : 'Sent to all teachers',
                    ),
                    _buildInfoRow('Sender', _getDisplayName(message)),
                    _buildInfoRow(
                      'Date Sent',
                      _formatTimestamp(message['created_at']),
                    ),
                    if (message['is_urgent'] == true)
                      _buildInfoRow('Priority', 'High Priority - Urgent'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataChip(IconData icon, String text) {
    // Ensure the text is properly formatted
    final displayText = text.trim().isEmpty ? 'Unknown' : text;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    // Ensure the value is properly formatted
    final displayValue = value.trim().isEmpty ? 'Unknown' : value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop(context)) {
      return _buildDesktopLayout(context);
    } else {
      return _buildMobileTabletLayout(context);
    }
  }
}
