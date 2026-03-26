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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Demo Bookings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, color: Colors.blue[700]),
            tooltip: 'Filter by status',
            onSelected: (value) {
              setState(() => _filterStatus = value);
            },
            itemBuilder: (context) => [
              _buildFilterItem('all', 'All Bookings', Icons.list),
              _buildFilterItem('pending', 'Pending', Icons.schedule),
              _buildFilterItem('contacted', 'Contacted', Icons.phone_in_talk),
              _buildFilterItem('done', 'Done', Icons.check_circle),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chip bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All'),
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
          // Bookings list
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
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: Colors.red[300]),
                          const SizedBox(height: 12),
                          Text(
                            'Error loading bookings',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  // Filter
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
                                ? Icons.calendar_today
                                : _statusIcon(_filterStatus),
                            size: 56,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _filterStatus == 'all'
                                ? 'No demo bookings yet'
                                : 'No ${_filterStatus} bookings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _filterStatus == 'all'
                                ? 'Bookings from the website will appear here'
                                : 'Try a different filter',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Stats summary
                  final pendingCount =
                      docs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return data['status'] == 'pending';
                      }).length;
                  final contactedCount =
                      docs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return data['status'] == 'contacted';
                      }).length;
                  final doneCount =
                      docs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return data['status'] == 'done';
                      }).length;

                  return RefreshIndicator(
                    onRefresh: () async {
                      // StreamBuilder auto-refreshes
                      await Future.delayed(const Duration(milliseconds: 500));
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Stats row
                        Row(
                          children: [
                            _buildMiniStat(
                              'Total',
                              docs.length.toString(),
                              Colors.blue,
                              Icons.list_alt,
                            ),
                            const SizedBox(width: 10),
                            _buildMiniStat(
                              'Pending',
                              pendingCount.toString(),
                              Colors.orange,
                              Icons.schedule,
                            ),
                            const SizedBox(width: 10),
                            _buildMiniStat(
                              'Contacted',
                              contactedCount.toString(),
                              Colors.blue,
                              Icons.phone_in_talk,
                            ),
                            const SizedBox(width: 10),
                            _buildMiniStat(
                              'Done',
                              doneCount.toString(),
                              Colors.green,
                              Icons.check_circle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Booking cards
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
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[700] : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.blue[700]!
                : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  PopupMenuEntry<String> _buildFilterItem(
    String value,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: _filterStatus == value ? Colors.blue[700] : Colors.grey),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight:
                  _filterStatus == value ? FontWeight.w700 : FontWeight.w400,
              color: _filterStatus == value ? Colors.blue[700] : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(
    String label,
    String count,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              count,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
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
      formattedCreated = DateFormat('MMM d, yyyy – h:mm a')
          .format(createdAt.toDate().toLocal());
    }

    // Format date display
    String formattedDate = date;
    try {
      final parsedDate = DateTime.parse(date);
      formattedDate = DateFormat('EEE, MMM d, yyyy').format(parsedDate);
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: email + status
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.email_outlined,
                      color: Colors.blue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Booked: $formattedCreated',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                GestureDetector(
                  onTap: () => _showStatusDialog(docId, status),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _statusColor(status).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _statusIcon(status),
                          size: 14,
                          color: _statusColor(status),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          status[0].toUpperCase() + status.substring(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _statusColor(status),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Date & Time row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 16, color: Colors.blue[400]),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.grey[300],
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 16, color: Colors.purple[400]),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Actions
            Row(
              children: [
                if (status == 'pending') ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _updateStatus(docId, 'contacted'),
                      icon: const Icon(Icons.phone_in_talk, size: 16),
                      label: const Text('Mark Contacted'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue[700],
                        side: BorderSide(color: Colors.blue[200]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (status == 'contacted') ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _updateStatus(docId, 'done'),
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('Mark Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                IconButton(
                  onPressed: () => _deleteBooking(docId),
                  icon: Icon(Icons.delete_outline, color: Colors.red[300]),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
