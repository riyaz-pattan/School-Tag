// admin_fee_reports_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'models/fee_models.dart';
import 'services/fee_service.dart';
import 'services/pdf_receipt_service.dart';

class AdminFeeReportsScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String adminId;

  const AdminFeeReportsScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.adminId,
  });

  @override
  State<AdminFeeReportsScreen> createState() => _AdminFeeReportsScreenState();
}

class _AdminFeeReportsScreenState extends State<AdminFeeReportsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _summary = {};
  bool _summaryLoading = true;
  String? _classFilter;
  List<String> _availableClasses = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadSummary();
    _loadClasses();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final summary =
          await FeeService.getFeeSummary(schoolCode: widget.schoolCode);
      if (mounted) {
        setState(() {
          _summary = summary;
          _summaryLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  Future<void> _loadClasses() async {
    try {
      final classes = await FeeService.getClassList(widget.schoolCode);
      if (mounted) setState(() => _availableClasses = classes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'Fee Reports',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue[700],
          unselectedLabelColor: Colors.grey[500],
          indicatorColor: Colors.blue[700],
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard, size: 20), text: 'Summary'),
            Tab(icon: Icon(Icons.check_circle, size: 20), text: 'Paid'),
            Tab(icon: Icon(Icons.warning, size: 20), text: 'Defaulters'),
            Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'Transactions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryTab(),
          _buildCollectionsTab(),
          _buildDefaultersTab(),
          _buildTransactionsTab(),
        ],
      ),
    );
  }

  // ─── Tab 1: Summary Dashboard ────────────────────────────────────────────

  Widget _buildSummaryTab() {
    if (_summaryLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final totalExpected = _summary['totalExpected'] ?? 0.0;
    final totalCollected = _summary['totalCollected'] ?? 0.0;
    final totalOutstanding = _summary['totalOutstanding'] ?? 0.0;
    final collectionRate = _summary['collectionRate'] ?? 0.0;

    return RefreshIndicator(
      onRefresh: _loadSummary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Cards
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: MediaQuery.of(context).size.width < 600 ? 1.2 : 1.5,
              children: [
                _buildKPICard(
                  'Total Expected',
                  formatter.format(totalExpected),
                  Icons.account_balance,
                  Colors.blue,
                ),
                _buildKPICard(
                  'Total Collected',
                  formatter.format(totalCollected),
                  Icons.check_circle,
                  Colors.green,
                ),
                _buildKPICard(
                  'Outstanding',
                  formatter.format(totalOutstanding),
                  Icons.pending_actions,
                  Colors.orange,
                ),
                _buildKPICard(
                  'Collection Rate',
                  '${collectionRate.toStringAsFixed(1)}%',
                  Icons.trending_up,
                  collectionRate >= 80
                      ? Colors.green
                      : collectionRate >= 50
                          ? Colors.orange
                          : Colors.red,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Quick stats
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment Status Overview',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStatRow(
                    'Paid',
                    '${_summary['totalPaid'] ?? 0}',
                    Colors.green,
                  ),
                  const Divider(height: 20),
                  _buildStatRow(
                    'Pending',
                    '${_summary['totalPending'] ?? 0}',
                    Colors.amber,
                  ),
                  const Divider(height: 20),
                  _buildStatRow(
                    'Overdue',
                    '${_summary['totalOverdue'] ?? 0}',
                    Colors.red,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Collection Progress bar
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Collection Progress',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: collectionRate / 100,
                      minHeight: 16,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        collectionRate >= 80
                            ? Colors.green
                            : collectionRate >= 50
                                ? Colors.orange
                                : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${collectionRate.toStringAsFixed(1)}% collected',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
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

  Widget _buildKPICard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: color,
          ),
        ),
      ],
    );
  }

  // ─── Tab 2: Collections (Paid) ───────────────────────────────────────────

  Widget _buildCollectionsTab() {
    return Column(
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _classFilter,
                  decoration: InputDecoration(
                    labelText: 'Filter by Class',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Classes')),
                    ..._availableClasses.map((cls) =>
                        DropdownMenuItem(value: cls, child: Text(cls))),
                  ],
                  onChanged: (value) =>
                      setState(() => _classFilter = value),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Export CSV',
                onPressed: () => _exportCSV('paid'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<StudentDue>>(
            stream: FeeService.streamAllDues(
              schoolCode: widget.schoolCode,
              className: _classFilter,
              status: 'paid',
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final dues = snapshot.data ?? [];
              if (dues.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 60, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('No paid fees found',
                          style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: dues.length,
                itemBuilder: (context, index) =>
                    _buildDueListTile(dues[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Tab 3: Defaulters ───────────────────────────────────────────────────

  Widget _buildDefaultersTab() {
    return Column(
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _classFilter,
                  decoration: InputDecoration(
                    labelText: 'Filter by Class',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Classes')),
                    ..._availableClasses.map((cls) =>
                        DropdownMenuItem(value: cls, child: Text(cls))),
                  ],
                  onChanged: (value) =>
                      setState(() => _classFilter = value),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Export CSV',
                onPressed: () => _exportCSV('pending'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<StudentDue>>(
            stream: FeeService.streamAllDues(
              schoolCode: widget.schoolCode,
              className: _classFilter,
              status: 'pending',
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final dues = snapshot.data ?? [];
              if (dues.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.celebration,
                          size: 60, color: Colors.green[300]),
                      const SizedBox(height: 12),
                      Text('No defaulters! All fees paid.',
                          style: TextStyle(color: Colors.green[600])),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  // Bulk send reminder
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: ElevatedButton.icon(
                      onPressed: () => _sendBulkReminders(dues),
                      icon: const Icon(Icons.notifications_active, size: 18),
                      label: Text('Send All Reminders (${dues.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: dues.length,
                      itemBuilder: (context, index) {
                        final due = dues[index];
                        final daysOverdue =
                            DateTime.now().difference(due.dueDate).inDays;
                        final isOverdue = daysOverdue > 0;

                        return _buildDefaulterTile(due, daysOverdue, isOverdue);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDefaulterTile(StudentDue due, int daysOverdue, bool isOverdue) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue ? Colors.red.withOpacity(0.3) : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isOverdue ? Colors.red[50] : Colors.amber[50],
          child: Icon(
            isOverdue ? Icons.error : Icons.schedule,
            color: isOverdue ? Colors.red : Colors.amber[700],
          ),
        ),
        title: Text(
          due.studentName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${due.className} • ${due.installmentLabel}'),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  formatter.format(due.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(width: 8),
                if (isOverdue)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$daysOverdue days overdue',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.notifications_active, color: Colors.orange[700]),
          tooltip: 'Send Reminder',
          onPressed: () async {
            try {
              final msg = await FeeService.sendFeeReminder(
                schoolCode: widget.schoolCode,
                dueId: due.id,
                studentId: due.studentId,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: msg.contains('Cannot send') || msg.contains('not found') ? Colors.orange : Colors.green,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to send reminder. $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
      ),
    );
  }

  // ─── Tab 4: Transactions (Full Audit Log) ────────────────────────────────

  Widget _buildTransactionsTab() {
    return StreamBuilder<List<FeeTransaction>>(
      stream: FeeService.streamTransactions(schoolCode: widget.schoolCode),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final transactions = snapshot.data ?? [];
        if (transactions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text('No transactions yet',
                    style: TextStyle(color: Colors.grey[500])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final txn = transactions[index];
            return _buildTransactionTile(txn);
          },
        );
      },
    );
  }

  Widget _buildTransactionTile(FeeTransaction txn) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    Color statusColor;
    IconData statusIcon;
    switch (txn.status) {
      case 'captured':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'refund_initiated':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_bottom;
        break;
      case 'refunded':
        statusColor = Colors.purple;
        statusIcon = Icons.replay;
        break;
      case 'waived':
        statusColor = Colors.teal;
        statusIcon = Icons.remove_circle;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.pending;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(statusIcon, color: statusColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                txn.studentName,
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                txn.status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${txn.className} • ${formatter.format(txn.amount)}'),
            Text(
              dateFormat.format(txn.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            if (txn.razorpayPaymentId != null &&
                txn.razorpayPaymentId!.isNotEmpty)
              Text(
                'Txn: ${txn.razorpayPaymentId}',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            if (txn.failureReason != null && txn.failureReason!.isNotEmpty)
              Text(
                'Reason: ${txn.failureReason}',
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
          ],
        ),
        trailing: txn.isCaptured
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.download, color: Colors.blue[700]),
                    tooltip: 'Download Invoice',
                    onPressed: () {
                      PdfReceiptService.generateInvoiceFromTransaction(
                        txn,
                        widget.schoolName,
                      ).catchError((e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to generate invoice: $e')),
                          );
                        }
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.replay, color: Colors.orange),
                    tooltip: 'Refund',
                    onPressed: () => _showRefundDialog(txn),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  // ─── Refund Dialog ───────────────────────────────────────────────────────

  void _showRefundDialog(FeeTransaction txn) {
    final reasonController = TextEditingController();
    bool isRefunding = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.replay, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Initiate Refund',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Refund ${NumberFormat.currency(locale: "en_IN", symbol: "₹").format(txn.amount)} to ${txn.studentName}?',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Refunds take 5-7 business days to process.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Reason for refund',
                      hintText: 'Enter the reason...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isRefunding ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isRefunding
                      ? null
                      : () async {
                          if (reasonController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a reason'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setDialogState(() => isRefunding = true);
                          try {
                            await FeeService.initiateRefund(
                              schoolCode: widget.schoolCode,
                              dueId: txn.dueId,
                              reason: reasonController.text.trim(),
                            );
                            if (context.mounted) Navigator.pop(context);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text('Refund initiated'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isRefunding = false);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[700],
                    foregroundColor: Colors.white,
                  ),
                  child: isRefunding
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white)),
                        )
                      : const Text('Initiate Refund'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── Helper: Due List Tile (for Collections tab) ─────────────────────────

  Widget _buildDueListTile(StudentDue due) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final dateFormat = DateFormat('dd MMM yyyy');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.green[50],
          child: Icon(Icons.check_circle, color: Colors.green[600]),
        ),
        title: Text(
          due.studentName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${due.className} • ${due.installmentLabel}'),
            if (due.paidAt != null)
              Text(
                'Paid on ${dateFormat.format(due.paidAt!)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
          ],
        ),
        trailing: Text(
          formatter.format(due.amount),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.green[700],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Future<void> _exportCSV(String statusFilter) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('student_dues')
          .where('status', isEqualTo: statusFilter)
          .get();

      final dues =
          snapshot.docs.map((doc) => StudentDue.fromFirestore(doc)).toList();

      if (dues.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data to export')),
          );
        }
        return;
      }

      List<List<dynamic>> rows = [
        [
          'Student Name',
          'Class',
          'Installment',
          'Amount',
          'Status',
          'Due Date',
          'Paid Date',
          'Transaction ID',
        ],
      ];

      for (final due in dues) {
        rows.add([
          due.studentName,
          due.className,
          due.installmentLabel,
          due.amount,
          due.status,
          DateFormat('dd/MM/yyyy').format(due.dueDate),
          due.paidAt != null ? DateFormat('dd/MM/yyyy').format(due.paidAt!) : '',
          due.razorpayPaymentId ?? '',
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);

      if (kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Fee Report CSV',
          fileName: 'fee_report_${statusFilter}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
          type: FileType.custom,
          allowedExtensions: ['csv'],
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsString(csv);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Export saved successfully!'), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        // Fallback for mobile devices
        final dir = await getTemporaryDirectory();
        final file = File(
            '${dir.path}/fee_report_${statusFilter}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
        await file.writeAsString(csv);
        await OpenFile.open(file.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendBulkReminders(List<StudentDue> dues) async {
    int sent = 0;
    for (final due in dues) {
      await FeeService.sendFeeReminder(
        schoolCode: widget.schoolCode,
        dueId: due.id,
        studentId: due.studentId,
      );
      sent++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reminders sent to $sent students'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
