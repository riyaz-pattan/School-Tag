// admin_fee_structure_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/fee_models.dart';
import 'services/fee_service.dart';
import 'admin_fee_reports_screen.dart';
import 'admin_payment_settings_screen.dart';

class AdminFeeStructureScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String adminId;

  const AdminFeeStructureScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.adminId,
  });

  @override
  State<AdminFeeStructureScreen> createState() =>
      _AdminFeeStructureScreenState();
}

class _AdminFeeStructureScreenState extends State<AdminFeeStructureScreen> {
  List<String> _availableClasses = [];
  bool _loadingClasses = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final classes = await FeeService.getClassList(widget.schoolCode);
      if (mounted) {
        setState(() {
          _availableClasses = classes;
          _loadingClasses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingClasses = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'Fee Management',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Payment Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminPaymentSettingsScreen(
                    schoolCode: widget.schoolCode,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Fee Reports',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminFeeReportsScreen(
                    schoolCode: widget.schoolCode,
                    schoolName: widget.schoolName,
                    adminId: widget.adminId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateStructureSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New Fee', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<FeeStructure>>(
        stream: FeeService.streamFeeStructures(widget.schoolCode),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final structures = snapshot.data ?? [];

          if (structures.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No Fee Structures',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to create your first fee structure',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: structures.length,
            itemBuilder: (context, index) {
              final structure = structures[index];
              return _buildStructureCard(structure);
            },
          );
        },
      ),
    );
  }

  Widget _buildStructureCard(FeeStructure structure) {
    final isPublished = structure.isPublished;
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: isPublished ? Colors.green.withOpacity(0.3) : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPublished
                    ? [Colors.green[50]!, Colors.green[25] ?? Colors.green[50]!]
                    : [Colors.blue[50]!, Colors.blue[25] ?? Colors.blue[50]!],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isPublished
                        ? Colors.green[100]
                        : Colors.blue[100],
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isPublished
                        ? Icons.check_circle
                        : Icons.edit_note,
                    color: isPublished ? Colors.green[700] : Colors.blue[700],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        structure.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        structure.academicYear,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isPublished ? Colors.green : Colors.amber,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isPublished ? 'PUBLISHED' : 'DRAFT',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Details
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildDetailRow(
                  Icons.currency_rupee,
                  'Total Amount',
                  formatter.format(structure.totalAmount),
                  Colors.green,
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  Icons.class_,
                  'Classes',
                  structure.applicableClasses.join(', '),
                  Colors.blue,
                ),
                const SizedBox(height: 12),
                _buildDetailRow(
                  Icons.calendar_month,
                  'Installments',
                  '${structure.installments.length} terms',
                  Colors.orange,
                ),

                // Installment breakdown
                if (structure.installments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  ...structure.installments.map((inst) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.subdirectory_arrow_right,
                              size: 18, color: Colors.grey[400]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              inst.label,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            formatter.format(inst.amount),
                            style: TextStyle(
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            DateFormat('dd MMM yyyy').format(inst.dueDate),
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),

          // Action buttons
          if (isPublished)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmPublish(structure),
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Sync Students'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (!isPublished)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showEditStructureSheet(context, structure),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDelete(structure),
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      label: const Text('Delete',
                          style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmPublish(structure),
                      icon: const Icon(Icons.publish, size: 18),
                      label: const Text('Publish & Assign'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ─── Create / Edit Bottom Sheet ──────────────────────────────────────────

  void _showCreateStructureSheet(BuildContext context) {
    _showStructureSheet(context, null);
  }

  void _showEditStructureSheet(BuildContext context, FeeStructure structure) {
    _showStructureSheet(context, structure);
  }

  void _showStructureSheet(BuildContext context, FeeStructure? existing) {
    final isEdit = existing != null;
    final titleController =
        TextEditingController(text: existing?.title ?? '');
    final yearController =
        TextEditingController(text: existing?.academicYear ?? '');
    final totalController = TextEditingController(
        text: existing != null ? existing.totalAmount.toStringAsFixed(0) : '');

    List<String> selectedClasses =
        List.from(existing?.applicableClasses ?? []);
    List<Installment> installments =
        List.from(existing?.installments ?? []);
    bool isSaving = false;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void addInstallment() {
              final instId =
                  'inst_${DateTime.now().millisecondsSinceEpoch}';
              setSheetState(() {
                installments.add(Installment(
                  id: instId,
                  label: 'Term ${installments.length + 1}',
                  amount: 0,
                  dueDate: DateTime.now().add(const Duration(days: 30)),
                ));
              });
            }

            void removeInstallment(int index) {
              setSheetState(() => installments.removeAt(index));
            }

            Future<void> save({bool publish = false}) async {
              final title = titleController.text.trim();
              final year = yearController.text.trim();
              final total =
                  double.tryParse(totalController.text.trim()) ?? 0;

              if (title.isEmpty || year.isEmpty) {
                setSheetState(
                    () => errorMessage = 'Title and Academic Year are required');
                return;
              }
              if (selectedClasses.isEmpty) {
                setSheetState(() => errorMessage = 'Select at least one class');
                return;
              }
              if (installments.isEmpty) {
                setSheetState(
                    () => errorMessage = 'Add at least one installment');
                return;
              }

              // Validate installment amounts sum
              final installmentSum =
                  installments.fold(0.0, (sum, i) => sum + i.amount);

              if (total <= 0) {
                setSheetState(
                    () => errorMessage = 'Total amount must be greater than 0');
                return;
              }

              if ((installmentSum - total).abs() > 0.01) {
                setSheetState(() => errorMessage =
                    'Installment amounts (₹${installmentSum.toStringAsFixed(0)}) must equal total (₹${total.toStringAsFixed(0)})');
                return;
              }

              setSheetState(() {
                isSaving = true;
                errorMessage = null;
              });

              try {
                if (isEdit) {
                  await FeeService.updateFeeStructure(
                    schoolCode: widget.schoolCode,
                    structureId: existing.id,
                    updates: {
                      'title': title,
                      'academicYear': year,
                      'applicableClasses': selectedClasses,
                      'totalAmount': total,
                      'installments':
                          installments.map((e) => e.toMap()).toList(),
                    },
                  );
                } else {
                  await FeeService.createFeeStructure(
                    schoolCode: widget.schoolCode,
                    title: title,
                    academicYear: year,
                    applicableClasses: selectedClasses,
                    totalAmount: total,
                    installments: installments,
                    adminId: widget.adminId,
                  );
                }

                if (context.mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit
                          ? 'Fee structure updated'
                          : 'Fee structure created'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                setSheetState(() {
                  isSaving = false;
                  errorMessage = 'Error: $e';
                });
              }
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(
                          isEdit ? Icons.edit : Icons.add_circle,
                          color: Colors.blue[700],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isEdit ? 'Edit Fee Structure' : 'New Fee Structure',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Scrollable form
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          TextField(
                            controller: titleController,
                            decoration: InputDecoration(
                              labelText: 'Fee Structure Title',
                              hintText:
                                  'e.g. Annual Tuition Fee 2025-26',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              prefixIcon: const Icon(Icons.title),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Academic Year
                          TextField(
                            controller: yearController,
                            decoration: InputDecoration(
                              labelText: 'Academic Year',
                              hintText: 'e.g. 2025-26',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              prefixIcon: const Icon(Icons.date_range),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Total Amount
                          TextField(
                            controller: totalController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Total Fee Amount (₹)',
                              hintText: 'e.g. 50000',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              prefixIcon:
                                  const Icon(Icons.currency_rupee),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Class selection
                          const Text(
                            'Applicable Classes',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_loadingClasses)
                            const Center(
                                child: CircularProgressIndicator())
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                // "ALL" chip
                                FilterChip(
                                  label: const Text('ALL'),
                                  selected: selectedClasses
                                      .contains('ALL'),
                                  onSelected: (selected) {
                                    setSheetState(() {
                                      if (selected) {
                                        selectedClasses = ['ALL'];
                                      } else {
                                        selectedClasses.remove('ALL');
                                      }
                                    });
                                  },
                                  selectedColor:
                                      Colors.blue[100],
                                  checkmarkColor:
                                      Colors.blue[700],
                                ),
                                ..._availableClasses.map((cls) {
                                  return FilterChip(
                                    label: Text(cls),
                                    selected: selectedClasses
                                            .contains(cls) ||
                                        selectedClasses
                                            .contains('ALL'),
                                    onSelected: selectedClasses
                                            .contains('ALL')
                                        ? null
                                        : (selected) {
                                            setSheetState(() {
                                              if (selected) {
                                                selectedClasses
                                                    .add(cls);
                                              } else {
                                                selectedClasses
                                                    .remove(cls);
                                              }
                                            });
                                          },
                                    selectedColor:
                                        Colors.blue[100],
                                    checkmarkColor:
                                        Colors.blue[700],
                                  );
                                }),
                              ],
                            ),

                          const SizedBox(height: 24),

                          // Installments section
                          Row(
                            children: [
                              const Icon(Icons.payments_outlined,
                                  size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Installments',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: addInstallment,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          if (installments.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius:
                                    BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.grey[200]!),
                              ),
                              child: Center(
                                child: Text(
                                  'No installments added yet',
                                  style: TextStyle(
                                      color: Colors.grey[400]),
                                ),
                              ),
                            )
                          else
                            ...installments
                                .asMap()
                                .entries
                                .map((entry) {
                              final idx = entry.key;
                              final inst = entry.value;
                              return _buildInstallmentEditor(
                                inst,
                                idx,
                                (updated) {
                                  setSheetState(() =>
                                      installments[idx] = updated);
                                },
                                () => removeInstallment(idx),
                                setSheetState,
                              );
                            }),

                          // Installment sum validation
                          if (installments.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Builder(builder: (context) {
                              final total = double.tryParse(
                                      totalController.text.trim()) ??
                                  0;
                              final sum = installments.fold(
                                  0.0, (s, i) => s + i.amount);
                              final match =
                                  (sum - total).abs() < 0.01;
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: match
                                      ? Colors.green[50]
                                      : Colors.red[50],
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      match
                                          ? Icons.check_circle
                                          : Icons.warning,
                                      color: match
                                          ? Colors.green
                                          : Colors.red,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        match
                                            ? 'Installments total matches fee amount'
                                            : 'Installments total: ₹${sum.toStringAsFixed(0)} ≠ Fee: ₹${total.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          color: match
                                              ? Colors.green[800]
                                              : Colors.red[800],
                                          fontWeight:
                                              FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],

                          // Error message
                          if (errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius:
                                    BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.red[200]!),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error,
                                      color: Colors.red, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      errorMessage!,
                                      style: const TextStyle(
                                          color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),

                  // Bottom action buttons
                  Container(
                    padding: EdgeInsets.fromLTRB(
                        20,
                        12,
                        20,
                        MediaQuery.of(context).padding.bottom + 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                isSaving ? null : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: isSaving ? null : () => save(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[700],
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white),
                                    ),
                                  )
                                : Text(
                                    isEdit
                                        ? 'Save Changes'
                                        : 'Save as Draft',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInstallmentEditor(
    Installment installment,
    int index,
    Function(Installment) onUpdate,
    VoidCallback onRemove,
    StateSetter setSheetState,
  ) {

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.orange[800],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: ValueKey('label_${installment.id}'),
                  initialValue: installment.label,
                  decoration: InputDecoration(
                    labelText: 'Label',
                    hintText: 'e.g. Term 1',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    onUpdate(installment.copyWith(label: value));
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle, color: Colors.red),
                iconSize: 24,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('amount_${installment.id}'),
                  initialValue: installment.amount > 0
                      ? installment.amount.toStringAsFixed(0)
                      : '',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount (₹)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                    prefixText: '₹ ',
                  ),
                  onChanged: (value) {
                    final amount = double.tryParse(value) ?? 0;
                    onUpdate(installment.copyWith(amount: amount));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: installment.dueDate,
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      onUpdate(installment.copyWith(dueDate: picked));
                      setSheetState(() {});
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            DateFormat('dd MMM yyyy')
                                .format(installment.dueDate),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Confirm dialogs ─────────────────────────────────────────────────────

  void _confirmPublish(FeeStructure structure) {
    showDialog(
      context: context,
      builder: (context) {
        bool isPublishing = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(
                    structure.isPublished ? Icons.sync : Icons.publish,
                    color: structure.isPublished
                        ? Colors.blue[700]
                        : Colors.green[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      structure.isPublished
                          ? 'Sync Students'
                          : 'Publish Fee Structure',
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
                    structure.isPublished
                        ? 'This will check for any students in the selected classes who don\'t have dues yet and create them. Existing dues will not be affected.'
                        : 'This will create fee dues for ALL students in the selected classes. This action cannot be undone.',
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.amber[800], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Classes: ${structure.applicableClasses.join(", ")}',
                            style: TextStyle(
                              color: Colors.amber[900],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isPublishing ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isPublishing
                      ? null
                      : () async {
                          setDialogState(() => isPublishing = true);
                          try {
                            await FeeService.publishFeeStructure(
                              schoolCode: widget.schoolCode,
                              structureId: structure.id,
                            );
                            if (context.mounted) Navigator.pop(context);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Fee structure published! Dues created for all students.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isPublishing = false);
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
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                  child: isPublishing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('Publish'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(FeeStructure structure) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Delete Fee Structure',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
            'Are you sure you want to delete "${structure.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FeeService.deleteFeeStructure(
                  schoolCode: widget.schoolCode,
                  structureId: structure.id,
                );
                if (context.mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('Fee structure deleted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
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
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
