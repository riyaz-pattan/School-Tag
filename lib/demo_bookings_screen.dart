import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'theme/glass_card.dart';

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

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'contacted':
        return Colors.blue;
      case 'done':
        return AppTheme.secondary;
      default:
        return AppTheme.outline;
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
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.onPrimary),
                const SizedBox(width: 12),
                Text('Status updated to ${newStatus.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            backgroundColor: _statusColor(newStatus),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showStatusDialog(String docId, String currentStatus) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.edit_note_rounded, color: Colors.blue),
            ),
            const SizedBox(width: 16),
            Text('Update Status', style: AppTheme.lightTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusOption(docId, 'pending', currentStatus),
            const SizedBox(height: 12),
            _buildStatusOption(docId, 'contacted', currentStatus),
            const SizedBox(height: 12),
            _buildStatusOption(docId, 'done', currentStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOption(String docId, String status, String currentStatus) {
    final isSelected = status == currentStatus;
    return InkWell(
      onTap: isSelected
          ? null
          : () {
              Navigator.pop(context);
              _updateStatus(docId, status);
            },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? _statusColor(status).withOpacity(0.12)
              : AppTheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? _statusColor(status).withOpacity(0.4)
                : AppTheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _statusIcon(status),
              color: _statusColor(status),
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              status[0].toUpperCase() + status.substring(1),
              style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? _statusColor(status) : AppTheme.onSurface,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: _statusColor(status), size: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteBooking(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
            ),
            const SizedBox(width: 16),
            Text('Delete Booking', style: AppTheme.lightTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text('Are you sure you want to permanently delete this booking?', style: AppTheme.lightTheme.textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.outline)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: AppTheme.onPrimary,
              elevation: 0,
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
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
              content: const Text('Booking deleted', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: AppTheme.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Demo Bookings', style: AppTheme.lightTheme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.onSurface),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list_rounded, color: AppTheme.primary),
            tooltip: 'Filter by status',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: AppTheme.surfaceContainerLowest,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
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
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.error),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Error loading bookings',
                            style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(color: AppTheme.onSurfaceVariant),
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
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(color: AppTheme.surfaceContainer, shape: BoxShape.circle),
                            child: Icon(
                              _filterStatus == 'all'
                                  ? Icons.calendar_today_rounded
                                  : _statusIcon(_filterStatus),
                              size: 64,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _filterStatus == 'all'
                                ? 'No demo bookings yet'
                                : 'No ${_filterStatus} bookings',
                            style: AppTheme.lightTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Bookings from the website will appear here',
                            style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(color: AppTheme.onSurfaceVariant),
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
                    color: AppTheme.primary,
                    backgroundColor: AppTheme.surfaceContainerLowest,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Row(
                          children: [
                            _buildMiniStat('Total', docs.length.toString(), AppTheme.primary, Icons.list_alt_rounded),
                            const SizedBox(width: 12),
                            _buildMiniStat('Pending', pendingCount.toString(), Colors.orange, Icons.schedule_rounded),
                            const SizedBox(width: 12),
                            _buildMiniStat('Contacted', contactedCount.toString(), Colors.blue, Icons.phone_in_talk_rounded),
                            const SizedBox(width: 12),
                            _buildMiniStat('Done', doneCount.toString(), AppTheme.secondary, Icons.check_circle_rounded),
                          ],
                        ),
                        const SizedBox(height: 32),

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
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          boxShadow: isSelected ? [
            BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))
          ] : [],
        ),
        child: Text(
          label,
          style: AppTheme.lightTheme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: isSelected ? AppTheme.onPrimary : AppTheme.onSurfaceVariant,
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
          Icon(icon, size: 22, color: isSelected ? AppTheme.primary : AppTheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? AppTheme.primary : AppTheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String count, Color color, IconData icon) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              count,
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.lightTheme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: AppTheme.onSurfaceVariant),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Stack(
        children: [
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.person_rounded, color: AppTheme.primary, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            email,
                            style: AppTheme.lightTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Requested: $formattedCreated',
                            style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(color: AppTheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showStatusDialog(docId, status),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_statusIcon(status), size: 16, color: _statusColor(status)),
                            const SizedBox(width: 8),
                            Text(
                              status[0].toUpperCase() + status.substring(1),
                              style: AppTheme.lightTheme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: _statusColor(status)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLowest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.primary),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                formattedDate,
                                style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1.5,
                        height: 32,
                        color: AppTheme.outlineVariant,
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: AppTheme.onTertiaryContainer.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.access_time_rounded, size: 18, color: AppTheme.onTertiaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            time,
                            style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (status == 'pending') ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _updateStatus(docId, 'contacted'),
                          icon: const Icon(Icons.phone_in_talk_rounded, size: 20),
                          label: const Text('Mark Contacted', style: TextStyle(fontWeight: FontWeight.w800)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue, width: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    if (status == 'contacted') ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _updateStatus(docId, 'done'),
                          icon: const Icon(Icons.check_circle_rounded, size: 20),
                          label: const Text('Mark Done', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.onPrimary)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.secondary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: IconButton(
                        onPressed: () => _deleteBooking(docId),
                        icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                        tooltip: 'Delete Booking',
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Status Ribbon
          Positioned(
            left: 0,
            top: 24,
            bottom: 24,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: _statusColor(status),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                )
              ),
            ),
          ),
        ],
      ),
    );
  }
}
