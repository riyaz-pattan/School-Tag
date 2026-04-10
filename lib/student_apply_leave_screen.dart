// student_apply_leave_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class StudentApplyLeaveScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String studentName;
  final String? classId;
  final String? section;

  const StudentApplyLeaveScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.studentName,
    this.classId,
    this.section,
  });

  @override
  State<StudentApplyLeaveScreen> createState() =>
      _StudentApplyLeaveScreenState();
}

class _StudentApplyLeaveScreenState extends State<StudentApplyLeaveScreen>
    with TickerProviderStateMixin {
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  
  final TextEditingController _reasonController = TextEditingController();
  
  String _selectedLeaveType = 'Sick Leave';
  final List<String> _leaveTypes = [
    'Sick Leave',
    'Family Emergency',
    'Vacation',
    'Extracurricular',
    'Other'
  ];

  File? _attachment;
  String? _attachmentName;

  bool _isSubmitting = false;
  bool _isSuccess = false;
  late AnimationController _successAnimController;
  late Animation<double> _successScaleAnim;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  List<Map<String, dynamic>> _pastLeaves = [];
  bool _isLoadingPast = true;

  @override
  void initState() {
    super.initState();
    _successAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _successScaleAnim = CurvedAnimation(
      parent: _successAnimController,
      curve: Curves.elasticOut,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
    _loadPastLeaves();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _successAnimController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadPastLeaves() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('leave_applications')
          .where('student_id', isEqualTo: widget.userId)
          .orderBy('applied_at', descending: true)
          .limit(20)
          .get();

      final leaves = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'date': data['date'] ?? '',
          'type': data['type'] ?? 'Other',
          'reason': data['reason'] ?? '',
          'applied_at': data['applied_at'],
          'status': data['status'] ?? 'applied',
          'attachment_url': data['attachment_url'],
        };
      }).toList();

      if (mounted) {
        setState(() {
          _pastLeaves = leaves;
          _isLoadingPast = false;
        });
      }
    } catch (e) {
      print('Error loading past leaves: $e');
      if (mounted) {
        setState(() => _isLoadingPast = false);
      }
    }
  }

  Future<void> _pickAttachment() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _attachment = File(result.files.single.path!);
          _attachmentName = result.files.single.name;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting file: $e')),
      );
    }
  }

  Future<void> _submitLeave() async {
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Please select at least one date'),
            ],
          ),
          backgroundColor: Colors.orange[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Please enter a reason for leave'),
            ],
          ),
          backgroundColor: Colors.orange[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? attachmentUrl;

      // Ensure storage initialized and upload attachment if any
      if (_attachment != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final ext = p.extension(_attachment!.path);
        final ref = FirebaseStorage.instance
            .ref('schools/${widget.schoolCode}/leave_attachments/${widget.userId}_$timestamp$ext');
        final uploadTask = await ref.putFile(_attachment!);
        attachmentUrl = await uploadTask.ref.getDownloadURL();
      }

      final start = _startDate!;
      final end = _endDate ?? _startDate!;

      List<DateTime> dates = [];
      DateTime current = start;
      while (current.isBefore(end) || _isSameDay(current, end)) {
        dates.add(current);
        current = current.add(const Duration(days: 1));
      }

      final batch = FirebaseFirestore.instance.batch();

      for (var date in dates) {
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final docId = '${widget.userId}_$dateStr';

        final docRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('leave_applications')
            .doc(docId);

        batch.set(docRef, {
          'student_id': widget.userId,
          'student_name': widget.studentName,
          'class_id': widget.classId ?? '',
          'section': widget.section ?? '',
          'date': dateStr,
          'type': _selectedLeaveType,
          'reason': reason,
          'attachment_url': attachmentUrl,
          'attachment_name': _attachmentName,
          'applied_at': FieldValue.serverTimestamp(),
          'status': 'applied',
        });
      }

      await batch.commit();

      setState(() {
        _isSubmitting = false;
        _isSuccess = true;
      });
      
      _successAnimController.forward();
      _reasonController.clear();
      _attachment = null;
      _attachmentName = null;
      _startDate = null;
      _endDate = null;

      _loadPastLeaves();

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _isSuccess = false);
          _successAnimController.reset();
        }
      });
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error applying for leave: $e')),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _navigateMonth(int direction) {
    setState(() {
      _currentMonth =
          DateTime(_currentMonth.year, _currentMonth.month + direction);
    });
  }

  bool _isSameDay(DateTime a, DateTime? b) {
    if (b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isDateInPast(DateTime date) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return date.isBefore(todayOnly);
  }

  bool _hasLeaveOnDate(DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _pastLeaves.any((leave) => leave['date'] == dateStr);
  }

  bool _isDateInRange(DateTime date) {
    if (_startDate == null) return false;
    final target = DateTime(date.year, date.month, date.day);
    final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);

    if (_endDate == null) {
      return _isSameDay(target, start);
    }
    
    final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
    return (target.isAtSameMomentAs(start) || target.isAtSameMomentAs(end) ||
           (target.isAfter(start) && target.isBefore(end)));
  }

  void _onDateTapped(DateTime date) {
    if (_isDateInPast(date)) return;
    if (_hasLeaveOnDate(date)) return;

    setState(() {
      if (_startDate == null) {
        _startDate = date;
        _endDate = null;
      } else if (_startDate != null && _endDate == null) {
        if (date.isBefore(_startDate!)) {
          _startDate = date;
        } else if (_isSameDay(date, _startDate)) {
          _startDate = null;
        } else {
          _endDate = date;
        }
      } else {
        _startDate = date;
        _endDate = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          // Gradient App Bar
          SliverAppBar(
            expandedHeight: isMobile ? 140 : 160,
            pinned: true,
            elevation: 0,
            backgroundColor: const Color(0xFF6C63FF),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(56, 8, 20, 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.event_busy_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Apply Leave',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Select single date or a range',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Body Content
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 32,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    children: [
                      // Calendar Card
                      _buildCalendarCard(),
                      const SizedBox(height: 20),

                      if (_startDate != null) ...[
                        _buildSelectedDateInfo(),
                        const SizedBox(height: 20),
                      ],

                      _buildLeaveTypeSelector(),
                      const SizedBox(height: 20),

                      _buildReasonField(),
                      const SizedBox(height: 20),

                      _buildAttachmentPicker(),
                      const SizedBox(height: 24),

                      // Submit Button or Success
                      _isSuccess ? _buildSuccessWidget() : _buildSubmitButton(),
                      const SizedBox(height: 32),

                      // Past Leaves Section
                      _buildPastLeavesSection(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCard() {
    final daysInMonth = DateUtils.getDaysInMonth(
        _currentMonth.year, _currentMonth.month);
    final firstDayOfMonth =
        DateTime(_currentMonth.year, _currentMonth.month, 1);
    final firstWeekday = firstDayOfMonth.weekday % 7; 

    final monthName = DateFormat('MMMM yyyy').format(_currentMonth);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6C63FF).withOpacity(0.05),
                  const Color(0xFF4ECDC4).withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => _navigateMonth(-1),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.chevron_left, color: Color(0xFF6C63FF), size: 22),
                  ),
                ),
                Text(
                  monthName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2D3A),
                  ),
                ),
                IconButton(
                  onPressed: () => _navigateMonth(1),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.chevron_right, color: Color(0xFF6C63FF), size: 22),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                  .map((day) => Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              day,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.0,
              ),
              itemCount: (firstWeekday + daysInMonth),
              itemBuilder: (context, index) {
                if (index < firstWeekday) return const SizedBox.shrink();

                final day = index - firstWeekday + 1;
                final date = DateTime(_currentMonth.year, _currentMonth.month, day);
                final isSelected = _isDateInRange(date);
                final isStartOrEnd = _isSameDay(date, _startDate) || _isSameDay(date, _endDate);
                final isToday = _isSameDay(date, DateTime.now());
                final isPast = _isDateInPast(date);
                final hasLeave = _hasLeaveOnDate(date);

                return GestureDetector(
                  onTap: () => _onDateTapped(date),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      gradient: isStartOrEnd
                          ? const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)])
                          : isSelected
                              ? LinearGradient(colors: [
                                  const Color(0xFF6C63FF).withOpacity(0.15),
                                  const Color(0xFF4ECDC4).withOpacity(0.15),
                                ])
                              : null,
                      color: isSelected ? null : hasLeave
                              ? const Color(0xFFFF6B6B).withOpacity(0.15)
                              : isToday
                                  ? const Color(0xFF6C63FF).withOpacity(0.08)
                                  : null,
                      borderRadius: BorderRadius.circular(12),
                      border: isToday && !isSelected
                          ? Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4), width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isStartOrEnd || isToday ? FontWeight.bold : FontWeight.normal,
                              color: isStartOrEnd
                                  ? Colors.white
                                  : isSelected
                                      ? const Color(0xFF6C63FF)
                                      : isPast
                                          ? Colors.grey[400]
                                          : hasLeave
                                              ? const Color(0xFFFF6B6B)
                                              : const Color(0xFF2D2D3A),
                            ),
                          ),
                          if (hasLeave)
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF6B6B),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSelectedDateInfo() {
    if (_startDate == null) return const SizedBox.shrink();

    String formattedDate = DateFormat('MMM d, yyyy').format(_startDate!);
    if (_endDate != null && !_isSameDay(_startDate!, _endDate)) {
      formattedDate += ' - ${DateFormat('MMM d, yyyy').format(_endDate!)}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: Color(0xFF6C63FF),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D2D3A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _endDate != null ? 'Date Range Selected' : 'Single Date Selected',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveTypeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedLeaveType,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF6C63FF)),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D2D3A),
          ),
          items: _leaveTypes.map((type) {
            IconData icon = Icons.sick;
            Color iconColor = Colors.orange;
            if (type == 'Family Emergency') {
              icon = Icons.family_restroom;
              iconColor = Colors.redAccent;
            } else if (type == 'Vacation') {
              icon = Icons.flight_takeoff;
              iconColor = Colors.lightBlue;
            } else if (type == 'Extracurricular') {
              icon = Icons.sports_basketball;
              iconColor = Colors.green;
            } else if (type == 'Other') {
              icon = Icons.more_horiz;
              iconColor = Colors.grey;
            }

            return DropdownMenuItem<String>(
              value: type,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(type),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedLeaveType = val);
            }
          },
        ),
      ),
    );
  }

  Widget _buildReasonField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ECDC4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.edit_note_rounded,
                    color: Color(0xFF4ECDC4),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Reason for Leave',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D2D3A),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: TextField(
              controller: _reasonController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Provide details about your absence...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentPicker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.attach_file, color: Colors.blue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _attachmentName ?? 'Attach Document (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: _attachmentName != null ? FontWeight.bold : FontWeight.normal,
                    color: _attachmentName != null ? const Color(0xFF2D2D3A) : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_attachmentName != null)
                  Text(
                    'Will be uploaded on submit',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
          if (_attachmentName != null)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => setState(() {
                _attachment = null;
                _attachmentName = null;
              }),
            )
          else
            TextButton(
              onPressed: _pickAttachment,
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Browse'),
            ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isSubmitting || _startDate == null ? null : _submitLeave,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.grey[300],
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: EdgeInsets.zero,
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _isSubmitting || _startDate == null
                ? null
                : const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)]),
            color: _isSubmitting || _startDate == null ? Colors.grey[300] : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            alignment: Alignment.center,
            child: _isSubmitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Confirm Application',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessWidget() {
    return ScaleTransition(
      scale: _successScaleAnim,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF4ECDC4).withOpacity(0.1),
              const Color(0xFF6C63FF).withOpacity(0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4ECDC4).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF4ECDC4), size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'Leave Applied Successfully! 🎉',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D3A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your request has been recorded.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPastLeavesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.history_rounded, color: Color(0xFFFF6B6B), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Leave History',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D3A),
              ),
            ),
            const Spacer(),
            if (_pastLeaves.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_pastLeaves.length}',
                  style: const TextStyle(
                    color: Color(0xFF6C63FF),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (_isLoadingPast)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C63FF)),
            ),
          )
        else if (_pastLeaves.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.event_available, size: 40, color: Colors.grey[300]),
                  const SizedBox(height: 10),
                  Text(
                    'No leave history yet',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else
          ...List.generate(_pastLeaves.length, (index) {
            final leave = _pastLeaves[index];
            final dateStr = leave['date'] as String;
            DateTime? date;
            try {
              date = DateFormat('yyyy-MM-dd').parse(dateStr);
            } catch (_) {}

            final formattedDate = date != null ? DateFormat('MMM d, yyyy').format(date) : dateStr;
            final type = leave['type'] ?? 'Other';
            final hasAttachment = leave['attachment_url'] != null;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2)),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6C63FF).withOpacity(0.12),
                        const Color(0xFF4ECDC4).withOpacity(0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.event_note, color: Color(0xFF6C63FF), size: 22),
                ),
                title: Text(
                  formattedDate,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF2D2D3A)),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$type • ${leave['reason'] ?? 'No reason'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (hasAttachment)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            Icon(Icons.attach_file, size: 12, color: Colors.blue[400]),
                            const SizedBox(width: 4),
                            Text('Attachment present', style: TextStyle(fontSize: 11, color: Colors.blue[400])),
                          ],
                        ),
                      )
                  ],
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ECDC4).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Applied',
                    style: TextStyle(color: Color(0xFF4ECDC4), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
