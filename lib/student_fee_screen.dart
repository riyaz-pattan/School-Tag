// student_fee_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/fee_models.dart';
import 'services/fee_service.dart';
import 'services/pdf_receipt_service.dart';
import 'student_fee_payment_screen.dart';

class StudentFeeScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String studentName;

  const StudentFeeScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.studentName,
  });

  @override
  State<StudentFeeScreen> createState() => _StudentFeeScreenState();
}

class _StudentFeeScreenState extends State<StudentFeeScreen> {
  final NumberFormat _formatter =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: StreamBuilder<List<StudentDue>>(
        stream: FeeService.streamStudentDues(
          schoolCode: widget.schoolCode,
          studentId: widget.userId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'Error loading fees: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final dues = snapshot.data ?? [];

          if (dues.isEmpty) {
            return _buildEmptyState();
          }

          // Calculate summary
          double totalFee = 0;
          double totalPaid = 0;
          double totalOutstanding = 0;
          StudentDue? nextDue;

          for (final due in dues) {
            if (due.isWaived) continue;
            totalFee += due.amount;
            if (due.isPaid) {
              totalPaid += due.amount;
            } else if (!due.isRefunded) {
              totalOutstanding += due.amount;
              if (nextDue == null && (due.isPending || due.isOverdue)) {
                nextDue = due;
              }
            }
          }

          return CustomScrollView(
            slivers: [
              // Gradient AppBar
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.blue[800]!,
                          Colors.blue[600]!,
                          Colors.indigo[600]!,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'My Fees',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Summary Cards Row
                            Row(
                              children: [
                                Expanded(
                                  child: _buildSummaryBox(
                                    'Total',
                                    _formatter.format(totalFee),
                                    Colors.white.withOpacity(0.2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildSummaryBox(
                                    'Paid',
                                    _formatter.format(totalPaid),
                                    Colors.green.withOpacity(0.3),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildSummaryBox(
                                    'Due',
                                    _formatter.format(totalOutstanding),
                                    totalOutstanding > 0
                                        ? Colors.red.withOpacity(0.3)
                                        : Colors.green.withOpacity(0.3),
                                  ),
                                ),
                              ],
                            ),
                            if (nextDue != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      nextDue.isOverdue
                                          ? Icons.warning
                                          : Icons.calendar_today,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        nextDue.isOverdue
                                            ? 'Overdue since ${DateFormat('dd MMM').format(nextDue.dueDate)}'
                                            : 'Next due: ${DateFormat('dd MMM yyyy').format(nextDue.dueDate)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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
                  ),
                ),
              ),

              // Pay Now CTA
              if (nextDue != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: ElevatedButton(
                      onPressed: () => _navigateToPayment(nextDue!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.payment, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Pay Now — ${_formatter.format(nextDue.amount)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Installment cards
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    'Installments',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey[800],
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final due = dues[index];
                    return _buildInstallmentCard(due);
                  },
                  childCount: dues.length,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryBox(String label, String amount, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallmentCard(StudentDue due) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (due.isPaid) {
      statusColor = Colors.green;
      statusLabel = 'PAID';
      statusIcon = Icons.check_circle;
    } else if (due.isOverdue) {
      statusColor = Colors.red;
      statusLabel = 'OVERDUE';
      statusIcon = Icons.error;
    } else if (due.isRefundInitiated) {
      statusColor = Colors.orange;
      statusLabel = 'REFUND PENDING';
      statusIcon = Icons.hourglass_bottom;
    } else if (due.isRefunded) {
      statusColor = Colors.purple;
      statusLabel = 'REFUNDED';
      statusIcon = Icons.replay;
    } else if (due.isWaived) {
      statusColor = Colors.teal;
      statusLabel = 'WAIVED';
      statusIcon = Icons.remove_circle;
    } else {
      statusColor = Colors.amber;
      statusLabel = 'PENDING';
      statusIcon = Icons.schedule;
    }

    final daysLeft = due.dueDate.difference(DateTime.now()).inDays;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: statusColor.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        due.installmentLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Due: ${DateFormat('dd MMM yyyy').format(due.dueDate)}',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatter.format(due.amount),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Contextual actions
            if (due.isPending || due.isOverdue) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (due.isOverdue)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${due.dueDate.difference(DateTime.now()).inDays.abs()} days overdue',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$daysLeft days left',
                        style: TextStyle(
                          color: Colors.blue[700],
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => _navigateToPayment(due),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Pay Now',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],

            // Receipt download
            if (due.isPaid) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (due.paidAt != null)
                    Text(
                      'Paid on ${DateFormat('dd MMM yyyy').format(due.paidAt!)}',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      PdfReceiptService.generateAndDownloadReceipt(
                        due,
                        widget.schoolName,
                      ).catchError((e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to generate receipt: $e')),
                          );
                        }
                      });
                    },
                    icon: Icon(Icons.download, size: 16, color: Colors.blue[700]),
                    label: Text(
                      'Receipt',
                      style: TextStyle(color: Colors.blue[700]),
                    ),
                  ),
                ],
              ),
            ],

            // Note
            if (due.note != null && due.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        due.note!,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Fees',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F6FA),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No Fees Assigned',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your fee dues will appear here once assigned',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPayment(StudentDue due) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentFeePaymentScreen(
          userId: widget.userId,
          schoolCode: widget.schoolCode,
          schoolName: widget.schoolName,
          studentName: widget.studentName,
          due: due,
        ),
      ),
    );
  }
}
