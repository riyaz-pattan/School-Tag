import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'admin_dashboard_screen.dart';

class ClassManagementScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;

  const ClassManagementScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<ClassManagementScreen> createState() => _ClassManagementScreenState();
}

class _ClassManagementScreenState extends State<ClassManagementScreen> {
  final _gradeController = TextEditingController();
  final _sectionsController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // Sidebar info page controller
  final PageController _infoPageController = PageController();
  int _currentInfoPage = 0;

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _gradeController.dispose();
    _sectionsController.dispose();
    _infoPageController.dispose();
    super.dispose();
  }

  void _onSidebarItemTapped(int index) {
    switch (index) {
      case 0: // Dashboard Overview
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => AdminDashboardScreen(
              userId: widget.userId,
              schoolCode: widget.schoolCode,
              schoolName: widget.schoolName,
            ),
          ),
          (route) => false,
        );
        break;
    }
  }

  void _showSuccessSnackBar(String message) {
    // Remove any existing snackbars first
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.fixed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  List<String> _normalizeSectionsInput(String input) {
    if (input.trim().isEmpty) return [];
    final parts = input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    // remove duplicates while preserving order (case-insensitive)
    final seen = <String>{};
    final out = <String>[];
    for (final p in parts) {
      final key = p.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        out.add(p);
      }
    }
    return out;
  }

  /// Returns list of section names (case-insensitive) that already exist for the given grade
  /// in other class documents (optionally excluding a classId).
  Future<List<String>> _existingSectionsForGrade(
    String grade, {
    String? excludeClassId,
  }) async {
    final query = FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolCode)
        .collection('classes')
        .where('grade', isEqualTo: grade);

    final snapshot = await query.get();
    final existing = <String>[];
    for (final doc in snapshot.docs) {
      if (excludeClassId != null && doc.id == excludeClassId) continue;
      final data = doc.data();
      final rawSections = data['sections'];
      if (rawSections is String) {
        final parts = rawSections
            .split(',')
            .map((s) => s.toString().trim())
            .where((s) => s.isNotEmpty);
        existing.addAll(parts);
      } else if (rawSections is List) {
        existing.addAll(rawSections.map((e) => e.toString().trim()));
      }
    }
    // return unique lowercase-normalized list preserving original casing of first occurrence
    final seenLower = <String>{};
    final out = <String>[];
    for (final s in existing) {
      final k = s.toLowerCase();
      if (!seenLower.contains(k)) {
        seenLower.add(k);
        out.add(s);
      }
    }
    return out;
  }

  Future<void> _addClass() async {
    final grade = _gradeController.text.trim();
    final sectionsInput = _sectionsController.text.trim();

    if (grade.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a grade';
      });
      return;
    }

    final sections = _normalizeSectionsInput(sectionsInput.toUpperCase());

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check for duplicate section names across other class docs with same grade
      if (sections.isNotEmpty) {
        final existing = await _existingSectionsForGrade(grade);
        final dupLower = <String>{};
        for (final s in sections) {
          if (existing.map((e) => e.toLowerCase()).contains(s.toLowerCase())) {
            dupLower.add(s);
          }
        }
        if (dupLower.isNotEmpty) {
          setState(() {
            _errorMessage =
                'Cannot add class. Sections already exist for Grade $grade: ${dupLower.join(', ')}';
            _isLoading = false;
          });
          return;
        }
      }

      final classId = '${grade}_${DateTime.now().millisecondsSinceEpoch}';
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .doc(classId)
          .set({
            'grade': grade,
            'sections': sections,
            'created_at': FieldValue.serverTimestamp(),
          });

      _gradeController.clear();
      _sectionsController.clear();

      // Show success snackbar instead of inline message
      _showSuccessSnackBar('Class $grade added successfully');
    } catch (e) {
      setState(() {
        _errorMessage = 'Error adding class: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateClass(
    String classId,
    Map<String, dynamic> classData,
  ) async {
    final _editGradeController = TextEditingController(
      text: classData['grade']?.toString() ?? '',
    );
    final existingSections =
        (classData['sections'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final _editSectionsController = TextEditingController(
      text: existingSections.join(', '),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Class'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _editGradeController,
              decoration: const InputDecoration(
                labelText: 'Grade',
                hintText: 'Enter grade (e.g., 5)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _editSectionsController,
              decoration: const InputDecoration(
                labelText: 'Sections',
                hintText: 'Enter sections (e.g., A, B, C)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final grade = _editGradeController.text.trim();
              final sections = _normalizeSectionsInput(
                _editSectionsController.text.trim(),
              );

              if (grade.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Grade is required'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                // Validate that these sections do not conflict with other class docs of same grade
                if (sections.isNotEmpty) {
                  final existing = await _existingSectionsForGrade(
                    grade,
                    excludeClassId: classId,
                  );
                  final dup = <String>[];
                  final existingLower = existing
                      .map((e) => e.toLowerCase())
                      .toSet();
                  for (final s in sections) {
                    if (existingLower.contains(s.toLowerCase())) dup.add(s);
                  }
                  if (dup.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Conflicting sections for Grade $grade: ${dup.join(', ')}',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }

                await FirebaseFirestore.instance
                    .collection('schools')
                    .doc(widget.schoolCode)
                    .collection('classes')
                    .doc(classId)
                    .update({
                      'grade': grade,
                      'sections': sections,
                      'updated_at': FieldValue.serverTimestamp(),
                    });
                Navigator.pop(context);
                _showSuccessSnackBar('Class updated successfully');
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error updating class: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteClass(String classId, String grade) async {
    bool confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Class'),
        content: Text('Are you sure you want to delete class $grade?'),
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

    if (confirmDelete == true) {
      try {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolCode)
            .collection('classes')
            .doc(classId)
            .delete();
        _showSuccessSnackBar('Class deleted successfully');
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting class: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isDesktop ? null : _buildAppBar(),
      body: _isDesktop ? _buildDesktopLayout() : _buildMobileTabletLayout(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text('Manage Classes - ${widget.schoolName}'),
      backgroundColor: Colors.white,
      foregroundColor: const Color.fromARGB(255, 21, 101, 192),
      elevation: 0,
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar
        _buildDesktopSidebar(),
        // Main Content
        Expanded(
          child: Column(
            children: [
              _buildDesktopTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildMainContent(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSidebar() {
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
                  Icons.class_,
                  size: 40,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Class Management',
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

          // Info Pages
          Expanded(
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

          // Page Indicator
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPageIndicator(0),
                const SizedBox(width: 8),
                _buildPageIndicator(1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPage1() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How to Manage Classes',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.add_circle,
            'Add New Classes',
            'Create new classes by entering grade and sections',
          ),
          _buildInfoItem(
            Icons.edit,
            'Edit Existing Classes',
            'Update class details including grade and sections',
          ),
          _buildInfoItem(
            Icons.delete,
            'Delete Classes',
            'Remove classes that are no longer needed',
          ),
          _buildInfoItem(
            Icons.list,
            'View All Classes',
            'See all existing classes in your school',
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
            'Class Management Tips',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem('🏫', 'Organize classes by grade levels (1-12)'),
          _buildTipItem(
            '📚',
            'Use sections (A, B, C) to manage multiple classes of same grade',
          ),
          _buildTipItem(
            '⚠️',
            'Double-check before deleting classes as it affects student assignments',
          ),
          _buildTipItem(
            '📱',
            'Class data syncs across all devices in real-time',
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
              'Need help? Contact your system administrator for assistance with class management.',
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

  Widget _buildPageIndicator(int pageIndex) {
    return GestureDetector(
      onTap: () {
        _infoPageController.animateToPage(
          pageIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _currentInfoPage == pageIndex
              ? const Color.fromARGB(255, 21, 101, 192)
              : Colors.grey[300],
        ),
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
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminDashboardScreen(
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
          const SizedBox(width: 16),
          const Text(
            'Class Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildMobileTabletLayout() {
    return Column(
      children: [
        if (_isTablet) _buildTabletTopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(_isMobile ? 16 : 20),
            child: _buildMainContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildTabletTopBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Text(
            'Manage Classes - ${widget.schoolName}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_isDesktop) ...[
          Text(
            'Class Management',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Add Class Form
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: EdgeInsets.all(_isMobile ? 16 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add New Class',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _gradeController,
                  decoration: const InputDecoration(
                    labelText: 'Grade',
                    hintText: 'Enter grade (e.g., 5)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.school),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _sectionsController,
                  decoration: const InputDecoration(
                    labelText: 'Sections',
                    hintText: 'Enter sections (e.g., A, B, C)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.list),
                  ),
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SizedBox(
                        width: _isDesktop ? 200 : double.infinity,
                        child: ElevatedButton(
                          onPressed: _addClass,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(
                              255,
                              21,
                              101,
                              192,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Add Class',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _buildErrorMessage(_errorMessage!),
                ],
                // Success message removed - now using SnackBar
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Class List Header
        Row(
          children: [
            Text(
              'Existing Classes',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 21, 101, 192),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Class List
        _buildClassList(),
      ],
    );
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final classes = snapshot.data!.docs;

        if (classes.isEmpty) {
          return _buildEmptyState();
        }

        return _buildClassListView(classes);
      },
    );
  }

  Widget _buildClassListView(List<QueryDocumentSnapshot> classes) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: classes.length,
      itemBuilder: (context, index) {
        final classData = classes[index].data() as Map<String, dynamic>;
        final classId = classes[index].id;
        final grade = classData['grade']?.toString() ?? 'Unknown';
        final sections =
            (classData['sections'] as List<dynamic>?)?.join(', ') ?? 'None';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue[100],
              child: Icon(Icons.class_, color: Colors.blue[700]),
            ),
            title: Text(
              'Grade $grade',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text('Sections: $sections'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.orange),
                  onPressed: () => _updateClass(classId, classData),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteClass(classId, grade),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.class_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Classes Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first class using the form above',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
