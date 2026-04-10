// demo_bookings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DemoBookingsScreen extends StatefulWidget {
  final String userId;

  const DemoBookingsScreen({super.key, required this.userId});

  @override
  State<DemoBookingsScreen> createState() => _DemoBookingsScreenState();
}

class _DemoBookingsScreenState extends State<DemoBookingsScreen>
    with TickerProviderStateMixin {
  String _filterStatus = 'all'; // all, pending, contacted, done
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  // Colors for status badges
  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'contacted':
        return Colors.blue;
      case 'done':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.schedule;
      case 'contacted':
        return Icons.phone_in_talk;
      case 'done':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  Future<void> _updateStatus(String docId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('demo_bookings')
          .doc(docId)
          .update({
            'status': newStatus,
            'updated_at': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to ${newStatus.toUpperCase()}'),
            backgroundColor: _statusColor(newStatus),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showStatusDialog(String docId, String currentStatus) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Colors.blue),
            SizedBox(width: 8),
            Text('Update Status'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusOption(docId, 'pending', currentStatus),
            const SizedBox(height: 8),
            _buildStatusOption(docId, 'contacted', currentStatus),
            const SizedBox(height: 8),
            _buildStatusOption(docId, 'done', currentStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOption(
    String docId,
    String status,
    String currentStatus,
  ) {
    final isSelected = status == currentStatus;
    return InkWell(
      onTap: isSelected
          ? null
          : () {
              Navigator.pop(context);
              _updateStatus(docId, status);
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? _statusColor(status).withOpacity(0.12)
              : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? _statusColor(status).withOpacity(0.4)
                : Colors.grey.withOpacity(0.15),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _statusIcon(status),
              color: _statusColor(status),
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              status[0].toUpperCase() + status.substring(1),
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15,
                color: isSelected ? _statusColor(status) : null,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check, color: _statusColor(status), size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteBooking(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Booking'),
          ],
        ),
        content: const Text('Are you sure you want to delete this booking?'),
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

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('demo_bookings')
            .doc(docId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Booking deleted'),
              backgroundColor: Colors.red[400],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFF),
      appBar: AppBar(
        title: const Text('Demo Bookings', style: TextStyle(color: Color(0xFF001F2A), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00113A)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF00113A)),
            tooltip: 'Filter by status',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: const Color(0xFFFFFFFF),
            onSelected: (value) {
              setState(() => _filterStatus = value);
            },
            itemBuilder: (context) => [
              _buildFilterItem('all', 'All Bookings', Icons.list_rounded),
              _buildFilterItem('pending', 'Pending', Icons.schedule_rounded),
              _buildFilterItem('contacted', 'Contacted', Icons.phone_in_talk_rounded),
              _buildFilterItem('done', 'Done', Icons.check_circle_rounded),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chip bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              boxShadow: [
                 BoxShadow(
                   color: const Color(0xFF001F2A).withOpacity(0.04),
                   blurRadius: 16,
                   offset: const Offset(0, 4),
                 ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All Bookings'),
                  const SizedBox(width: 8),
                  _buildFilterChip('pending', 'Pending'),
                  const SizedBox(width: 8),
                  _buildFilterChip('contacted', 'Contacted'),
                  const SizedBox(width: 8),
                  _buildFilterChip('done', 'Done'),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('demo_bookings')
                    .orderBy('created_at', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF00113A)));
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(
                            'Error loading bookings',
                            style: TextStyle(fontSize: 16, color: const Color(0xFF757682)),
                          ),
                        ],
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  final filteredDocs = _filterStatus == 'all'
                      ? docs
                      : docs.where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          return data['status'] == _filterStatus;
                        }).toList();

                  if (filteredDocs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _filterStatus == 'all'
                                ? Icons.calendar_today_rounded
                                : _statusIcon(_filterStatus),
                            size: 64,
                            color: const Color(0xFFC5C6D2),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _filterStatus == 'all'
                                ? 'No demo bookings yet'
                                : 'No ${_filterStatus} bookings',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF001F2A)),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Bookings from the website will appear here',
                            style: TextStyle(fontSize: 14, color: Color(0xFF757682)),
                          ),
                        ],
                      ),
                    );
                  }

                  final pendingCount = docs.where((d) => (d.data() as Map)['status'] == 'pending').length;
                  final contactedCount = docs.where((d) => (d.data() as Map)['status'] == 'contacted').length;
                  final doneCount = docs.where((d) => (d.data() as Map)['status'] == 'done').length;

                  return RefreshIndicator(
                    onRefresh: () async {
                      await Future.delayed(const Duration(milliseconds: 500));
                    },
                    color: const Color(0xFF00113A),
                    backgroundColor: Colors.white,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      children: [
                        // Premium Stats Row
                        Row(
                          children: [
                            _buildMiniStat('Total', docs.length.toString(), const Color(0xFF00113A), Icons.list_alt_rounded),
                            const SizedBox(width: 12),
                            _buildMiniStat('Pending', pendingCount.toString(), Colors.orange, Icons.schedule_rounded),
                            const SizedBox(width: 12),
                            _buildMiniStat('Contacted', contactedCount.toString(), Colors.blue, Icons.phone_in_talk_rounded),
                            const SizedBox(width: 12),
                            _buildMiniStat('Done', doneCount.toString(), const Color(0xFF006D36), Icons.check_circle_rounded),
                          ],
                        ),
                        const SizedBox(height: 24),

                        ...filteredDocs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildBookingCard(doc.id, data);
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00113A) : const Color(0xFFF4FAFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00113A) : const Color(0xFFE6F6FF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF757682),
          ),
        ),
      ),
    );
  }

  PopupMenuEntry<String> _buildFilterItem(String value, String label, IconData icon) {
    final isSelected = _filterStatus == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: isSelected ? const Color(0xFF00113A) : const Color(0xFF757682)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF001F2A) : const Color(0xFF001F2A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF001F2A).withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              count,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF757682)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(String docId, Map<String, dynamic> data) {
    final email = data['email'] ?? 'No email';
    final date = data['date'] ?? 'N/A';
    final time = data['time'] ?? 'N/A';
    final status = data['status'] ?? 'pending';
    final createdAt = data['created_at'] as Timestamp?;

    String formattedCreated = 'Unknown';
    if (createdAt != null) {
      formattedCreated = DateFormat('MMM d, yyyy – h:mm a').format(createdAt.toDate().toLocal());
    }

    String formattedDate = date;
    try {
      final parsedDate = DateTime.parse(date);
      formattedDate = DateFormat('EEE, MMM d, yyyy').format(parsedDate);
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF001F2A).withOpacity(0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F6FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.email_rounded, color: Color(0xFF00113A), size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF001F2A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Booked: $formattedCreated',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF757682)),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showStatusDialog(docId, status),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _statusColor(status).withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_statusIcon(status), size: 14, color: _statusColor(status)),
                        const SizedBox(width: 6),
                        Text(
                          status[0].toUpperCase() + status.substring(1),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _statusColor(status)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF4FAFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF00113A)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            formattedDate,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF001F2A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: const Color(0xFFC5C6D2),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF399E9D)),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF001F2A)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (status == 'pending') ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _updateStatus(docId, 'contacted'),
                      icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                      label: const Text('Mark Contacted', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: const BorderSide(color: Colors.blue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (status == 'contacted') ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _updateStatus(docId, 'done'),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text('Mark Done', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006D36),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                IconButton(
                  onPressed: () => _deleteBooking(docId),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  tooltip: 'Delete Booking',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
