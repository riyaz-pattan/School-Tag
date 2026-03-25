import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class StudentManagementScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;

  const StudentManagementScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  String? _errorMessage;
  String? _successMessage;

  // Search & filter state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String? _filterGrade;
  String? _filterSection;

  // Scroll controller to preserve position
  final ScrollController _scrollController = ScrollController();

  // Bulk selection state
  final Set<String> _selectedStudents = {};
  bool _isBulkMode = false;

  // Refresh state
  bool _isRefreshing = false;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // Sidebar info page controller
  final PageController _infoPageController = PageController();
  int _currentInfoPage = 0;

  // Timer for auto-dismissing messages
  Timer? _messageTimer;

  // Global key for student content to trigger refresh
  final GlobalKey<_StudentManagementContentState> _studentContentKey =
      GlobalKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _infoPageController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  // Helper methods to get screen size categories - called in build method to ensure updates on resize
  bool _isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;

  bool _isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

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

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    // Clear selections and filters
    setState(() {
      _selectedStudents.clear();
      _isBulkMode = false;
      _searchQuery = '';
      _filterGrade = null;
      _filterSection = null;
      _searchController.clear();
    });

    // Trigger refresh in the student content
    if (_studentContentKey.currentState != null) {
      await _studentContentKey.currentState!._refreshData();
    }

    setState(() {
      _isRefreshing = false;
    });

    _showMessage('Data refreshed successfully', false);
  }

  void _toggleBulkMode() {
    setState(() {
      _isBulkMode = !_isBulkMode;
      if (!_isBulkMode) {
        _selectedStudents.clear();
      }
    });
  }

  void _toggleStudentSelection(String studentId, bool selected) {
    setState(() {
      if (selected) {
        _selectedStudents.add(studentId);
      } else {
        _selectedStudents.remove(studentId);
      }
    });
  }

  void _selectAllStudents(List<String> studentIds) {
    setState(() {
      _selectedStudents.clear();
      _selectedStudents.addAll(studentIds);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedStudents.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use LayoutBuilder to get real-time constraints updates
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = _isMobile(context);
        final bool isTablet = _isTablet(context);
        final bool isDesktop = _isDesktop(context);

        return Scaffold(
          appBar: isDesktop ? null : _buildAppBar(isMobile, isTablet),
          body: isDesktop
              ? _buildDesktopLayout(context)
              : _buildMobileTabletLayout(context),
        );
      },
    );
  }

  AppBar _buildAppBar(bool isMobile, bool isTablet) {
    return AppBar(
      title: Text(
        isMobile ? 'Students' : 'Student Management - ${widget.schoolName}',
        style: TextStyle(fontSize: isMobile ? 18 : 20),
      ),
      backgroundColor: Colors.white,
      foregroundColor: const Color.fromARGB(255, 21, 101, 192),
      elevation: 0,
      actions: [
        if (_isBulkMode) ...[
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear selection',
            onPressed: _selectedStudents.isNotEmpty ? _clearSelection : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '${_selectedStudents.length}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
        ],
        IconButton(
          icon: Icon(_isBulkMode ? Icons.cancel : Icons.checklist),
          tooltip: _isBulkMode ? 'Exit bulk mode' : 'Bulk selection',
          onPressed: _toggleBulkMode,
        ),
        if (!_isBulkMode) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshData,
            tooltip: 'Refresh Data',
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final isDesktop = _isDesktop(context);

    return Row(
      children: [
        // Sidebar - only show if screen is wide enough
        if (isDesktop) _buildDesktopSidebar(),
        // Main Content
        Expanded(
          child: Column(
            children: [
              _buildDesktopTopBar(context),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildMainContent(context),
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
                  Icons.school,
                  size: 40,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Student Management',
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
            'How to Manage Students',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildSidebarInfoItem(
            Icons.search,
            'Search Students',
            'Find students by name or username using the search bar',
          ),
          _buildSidebarInfoItem(
            Icons.filter_list,
            'Filter by Class & Section',
            'Use filters to view students by specific classes and sections',
          ),
          _buildSidebarInfoItem(
            Icons.assignment,
            'Assign to Classes',
            'Assign students to classes and sections individually or in bulk',
          ),
          _buildSidebarInfoItem(
            Icons.checklist,
            'Bulk Operations',
            'Select multiple students for batch assignments and updates',
          ),
          _buildSidebarInfoItem(
            Icons.edit,
            'Edit Assignments',
            'Update class assignments for individual students as needed',
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
            'Student Management Tips',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            '👥',
            'Use bulk operations for efficient class assignments',
          ),
          _buildTipItem(
            '🔍',
            'Combine search and filters to quickly find specific students',
          ),
          _buildTipItem(
            '📚',
            'Ensure students are properly assigned to classes for grade tracking',
          ),
          _buildTipItem(
            '🔄',
            'Regularly review and update student class assignments',
          ),
          _buildTipItem(
            '📱',
            'All changes sync in real-time across all devices',
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
              'Need help? Contact your system administrator for assistance with student management.',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarInfoItem(
    IconData icon,
    String title,
    String description,
  ) {
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
        if (_infoPageController.hasClients) {
          _infoPageController.animateToPage(
            pageIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
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

  Widget _buildDesktopTopBar(BuildContext context) {
    final isDesktop = _isDesktop(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white,
      child: Row(
        children: [
          // Back button and title
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.15),
                child: const Text(
                  'Student Management',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Bulk action bar with responsive constraints
          if (_isBulkMode && _selectedStudents.isNotEmpty)
            Flexible(
              flex: 2,
              child: Container(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.5),
                child: _buildDesktopBulkActionBar(),
              ),
            ),

          const Spacer(),

          // Action buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isBulkMode) ...[
                IconButton(
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, color: Colors.blue),
                  onPressed: _isRefreshing ? null : _refreshData,
                  tooltip: 'Refresh Data',
                ),
                const SizedBox(width: 8),
              ],
              // Bulk mode toggle button - adaptive text
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ElevatedButton.icon(
                  icon: Icon(_isBulkMode ? Icons.cancel : Icons.checklist),
                  label: Text(
                    _isBulkMode
                        ? screenWidth < 1000
                              ? 'Exit'
                              : 'Exit Bulk'
                        : screenWidth < 1000
                        ? 'Bulk'
                        : 'Bulk Select',
                  ),
                  onPressed: _toggleBulkMode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isBulkMode
                        ? Colors.grey[600]
                        : const Color.fromARGB(255, 21, 101, 192),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
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

  Widget _buildDesktopBulkActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group, color: Colors.blue[700], size: 18),
          const SizedBox(width: 6),
          Text(
            '${_selectedStudents.length}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.blue[700],
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.assignment, size: 16),
                    label: const Text('Assign'),
                    onPressed: () => _showBulkAssignDialog(context),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      backgroundColor: const Color.fromARGB(255, 21, 101, 192),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cancel, size: 16),
                    label: const Text('Unassign'),
                    onPressed: _unassignSelectedStudents,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      side: BorderSide(color: Colors.red[400]!),
                      foregroundColor: Colors.red[600],
                    ),
                  ),
                  if (_selectedStudents.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Clear'),
                      onPressed: _clearSelection,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        side: BorderSide(color: Colors.grey[400]!),
                        foregroundColor: Colors.grey[700],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTabletLayout(BuildContext context) {
    final isTablet = _isTablet(context);

    return Column(
      children: [
        if (isTablet) _buildTabletTopBar(),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(_isMobile(context) ? 16 : 20),
            child: _buildMainContent(context),
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
            'Student Management - ${widget.schoolName}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
          if (_isBulkMode && _selectedStudents.isNotEmpty)
            _buildBulkActionBar(),
        ],
      ),
    );
  }

  Widget _buildBulkActionBar() {
    return _buildMobileBulkActionBar();
  }

  Widget _buildMobileBulkActionBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.group, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                '${_selectedStudents.length} selected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.assignment, size: 18),
                  label: const Text('Assign'),
                  onPressed: () => _showBulkAssignDialog(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cancel, size: 18),
                  label: const Text('Unassign'),
                  onPressed: _unassignSelectedStudents,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: Colors.red[400]!),
                    foregroundColor: Colors.red[600],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    final isMobile = _isMobile(context);
    final isTablet = _isTablet(context);
    final isDesktop = _isDesktop(context);

    return Column(
      children: [
        // Messages
        if (_errorMessage != null)
          _buildMessageContainer(
            _errorMessage!,
            Colors.red[50]!,
            Icons.error,
            Colors.red,
          ),
        if (_successMessage != null)
          _buildMessageContainer(
            _successMessage!,
            Colors.green[50]!,
            Icons.check_circle,
            Colors.green,
          ),

        const SizedBox(height: 16),

        // Bulk action bar for mobile (shown below messages)
        if (_isBulkMode && _selectedStudents.isNotEmpty && !isDesktop)
          _buildMobileBulkActionBar(),

        const SizedBox(height: 16),

        // Main content
        Expanded(
          child: _StudentManagementContent(
            key: _studentContentKey,
            schoolCode: widget.schoolCode,
            searchController: _searchController,
            searchFocusNode: _searchFocusNode,
            searchQuery: _searchQuery,
            filterGrade: _filterGrade,
            filterSection: _filterSection,
            scrollController: _scrollController,
            isBulkMode: _isBulkMode,
            selectedStudents: _selectedStudents,
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            onFilterGradeChanged: (v) => setState(() {
              _filterGrade = v;
              _filterSection = null;
            }),
            onFilterSectionChanged: (v) => setState(() => _filterSection = v),
            onMessage: _showMessage,
            onClearMessages: _clearMessages,
            onStudentSelectionChanged: _toggleStudentSelection,
            onSelectAllStudents: _selectAllStudents,
            isDesktop: isDesktop,
            isMobile: isMobile,
            isTablet: isTablet,
          ),
        ),
      ],
    );
  }

  Widget _buildMessageContainer(
    String message,
    Color backgroundColor,
    IconData icon,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: iconColor.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: iconColor),
            onPressed: _clearMessages,
          ),
        ],
      ),
    );
  }

  void _showBulkAssignDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _BulkAssignDialog(
        schoolCode: widget.schoolCode,
        studentIds: _selectedStudents.toList(),
        onSuccess: (message) {
          _showMessage(message, false);
          _toggleBulkMode();
        },
        onError: (message) {
          _showMessage(message, true);
        },
      ),
    );
  }

  void _unassignSelectedStudents() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unassign Students'),
        content: Text(
          'Are you sure you want to unassign ${_selectedStudents.length} students from their current classes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performBulkUnassign();
            },
            child: const Text('Unassign', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performBulkUnassign() async {
    try {
      final batch = FirebaseFirestore.instance.batch();

      for (final studentId in _selectedStudents) {
        final studentRef = FirebaseFirestore.instance
            .collection('users')
            .doc(studentId);
        batch.update(studentRef, {
          'class_id': null,
          'class_name': null,
          'section': null,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      _showMessage(
        'Unassigned ${_selectedStudents.length} students successfully',
        false,
      );
      setState(() {
        _selectedStudents.clear();
        _isBulkMode = false;
      });
    } catch (e) {
      _showMessage('Error unassigning students: ${e.toString()}', true);
    }
  }
}

class _BulkAssignDialog extends StatefulWidget {
  final String schoolCode;
  final List<String> studentIds;
  final ValueChanged<String> onSuccess;
  final ValueChanged<String> onError;

  const _BulkAssignDialog({
    required this.schoolCode,
    required this.studentIds,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<_BulkAssignDialog> createState() => _BulkAssignDialogState();
}

class _BulkAssignDialogState extends State<_BulkAssignDialog> {
  String? _selectedGrade;
  String? _selectedSection;
  bool _isLoading = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classDocs = [];
  Map<String, Map<String, dynamic>> _gradeGroups = {};
  List<String> _gradeKeys = [];

  @override
  void initState() {
    super.initState();
    _loadClassesData();
  }

  Future<void> _loadClassesData() async {
    try {
      final cache = await SharedPreferences.getInstance();
      final cacheKey = 'classes_${widget.schoolCode}';
      final cacheTimestampKey = 'classes_timestamp_${widget.schoolCode}';

      // Check if cache is fresh (less than 5 minutes old)
      final lastUpdate = cache.getInt(cacheTimestampKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final isCacheValid = (now - lastUpdate) < 5 * 60 * 1000; // 5 minutes

      if (isCacheValid) {
        final cachedData = cache.getString(cacheKey);
        if (cachedData != null) {
          // Parse cached data (in a real app, you'd use proper serialization)
          // For now, we'll fetch fresh data
        }
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();

      setState(() {
        _classDocs = snapshot.docs
            .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
        _gradeGroups = _buildGradeGroups(_classDocs);
        _gradeKeys = _gradeGroups.keys.toList()..sort();
      });

      // Update cache
      await cache.setInt(cacheTimestampKey, now);
    } catch (e) {
      widget.onError('Error loading classes: ${e.toString()}');
    }
  }

  Map<String, Map<String, dynamic>> _buildGradeGroups(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> classDocs,
  ) {
    final Map<String, Map<String, dynamic>> gradeGroups = {};
    for (final doc in classDocs) {
      final data = doc.data() ?? <String, dynamic>{};
      final gradeRaw = (data['grade']?.toString() ?? '').trim();
      final gradeKey = gradeRaw.isNotEmpty ? gradeRaw : '(Unknown)';

      final sectionsList = _parseSections(data['sections']);

      if (!gradeGroups.containsKey(gradeKey)) {
        gradeGroups[gradeKey] = {
          'classIds': <String>[],
          'sections': <String>{},
        };
      }

      (gradeGroups[gradeKey]!['classIds'] as List<String>).add(doc.id);
      (gradeGroups[gradeKey]!['sections'] as Set<String>).addAll(sectionsList);
    }
    return gradeGroups;
  }

  List<String> _parseSections(dynamic raw) {
    if (raw == null) return [];
    if (raw is String) {
      return raw
          .split(',')
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      return [];
    }
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _findClassDocByGradeAndSection(
    String grade,
    String? section,
  ) {
    QueryDocumentSnapshot<Map<String, dynamic>>? firstGradeMatch;
    for (final doc in _classDocs) {
      final data = doc.data() ?? <String, dynamic>{};
      final docGrade = (data['grade'] ?? '').toString().trim();
      if (docGrade != grade) continue;
      firstGradeMatch ??= doc;

      final sections = _parseSections(data['sections']);
      if (section != null && section.isNotEmpty) {
        if (sections.any((s) => s.toLowerCase() == section.toLowerCase())) {
          return doc;
        }
      }
    }
    return firstGradeMatch;
  }

  Future<void> _assignStudents() async {
    if (_selectedGrade == null) {
      widget.onError('Please select a class (grade) before assigning.');
      return;
    }

    final matchedClassDoc = _findClassDocByGradeAndSection(
      _selectedGrade!,
      _selectedSection,
    );

    if (matchedClassDoc == null) {
      widget.onError('No class document found for selected grade/section.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final classData = matchedClassDoc.data() ?? <String, dynamic>{};
      final gradeVal = (classData['grade']?.toString() ?? '').trim();
      final sectionToSave = _selectedSection ?? '';

      for (final studentId in widget.studentIds) {
        final studentRef = FirebaseFirestore.instance
            .collection('users')
            .doc(studentId);
        batch.update(studentRef, {
          'class_id': matchedClassDoc.id,
          'class_name': gradeVal.isNotEmpty ? 'Grade $gradeVal' : null,
          'section': sectionToSave.isNotEmpty ? sectionToSave : null,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      widget.onSuccess(
        'Assigned ${widget.studentIds.length} students to class successfully',
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      widget.onError('Error assigning students: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isDesktop ? 500 : double.maxFinite,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.group, color: Colors.blue[700], size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Assign Students to Class',
                    style: TextStyle(
                      fontSize: isDesktop ? 20 : 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Assign ${widget.studentIds.length} students to a class:',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: isDesktop ? 16 : 14,
              ),
            ),
            const SizedBox(height: 24),
            _isLoading
                ? const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Assigning students...'),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String?>(
                        value: _selectedGrade,
                        hint: const Text('Select Class (Grade)'),
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        items: _gradeKeys.map((gradeKey) {
                          final display = gradeKey == '(Unknown)'
                              ? 'Grade (Unknown)'
                              : 'Grade $gradeKey';
                          return DropdownMenuItem<String?>(
                            value: gradeKey,
                            child: Text(display),
                          );
                        }).toList(),
                        onChanged: (selectedGrade) {
                          setState(() {
                            _selectedGrade = selectedGrade;
                            _selectedSection = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_selectedGrade != null &&
                          _gradeGroups.containsKey(_selectedGrade))
                        DropdownButtonFormField<String?>(
                          value: _selectedSection,
                          hint: const Text('Select Section'),
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No Section'),
                            ),
                            ...((_gradeGroups[_selectedGrade]!['sections']
                                        as Set<String>)
                                    .toList()
                                  ..sort())
                                .map(
                                  (section) => DropdownMenuItem<String?>(
                                    value: section,
                                    child: Text(section),
                                  ),
                                ),
                          ],
                          onChanged: (section) {
                            setState(() {
                              _selectedSection = section;
                            });
                          },
                        ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                side: BorderSide(color: Colors.grey[400]!),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isLoading || _selectedGrade == null
                                  ? null
                                  : _assignStudents,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                backgroundColor: const Color.fromARGB(
                                  255,
                                  21,
                                  101,
                                  192,
                                ),
                                foregroundColor: Colors.white,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Assign Students'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

class _StudentManagementContent extends StatefulWidget {
  final String schoolCode;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final String searchQuery;
  final String? filterGrade;
  final String? filterSection;
  final ScrollController scrollController;
  final bool isBulkMode;
  final Set<String> selectedStudents;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onFilterGradeChanged;
  final ValueChanged<String?> onFilterSectionChanged;
  final ValueChanged2<String, bool> onMessage;
  final VoidCallback onClearMessages;
  final ValueChanged2<String, bool> onStudentSelectionChanged;
  final ValueChanged<List<String>> onSelectAllStudents;
  final bool isDesktop;
  final bool isMobile;
  final bool isTablet;

  const _StudentManagementContent({
    super.key,
    required this.schoolCode,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchQuery,
    required this.filterGrade,
    required this.filterSection,
    required this.scrollController,
    required this.isBulkMode,
    required this.selectedStudents,
    required this.onSearchChanged,
    required this.onFilterGradeChanged,
    required this.onFilterSectionChanged,
    required this.onMessage,
    required this.onClearMessages,
    required this.onStudentSelectionChanged,
    required this.onSelectAllStudents,
    required this.isDesktop,
    required this.isMobile,
    required this.isTablet,
  });

  @override
  State<_StudentManagementContent> createState() =>
      _StudentManagementContentState();
}

class _StudentManagementContentState extends State<_StudentManagementContent> {
  // Track which student is currently being edited - MOVED HERE to prevent parent rebuilds
  String? _currentlyEditingStudentId;

  // Cache for classes data
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _cachedClassDocs;
  Map<String, Map<String, dynamic>>? _cachedGradeGroups;
  List<String>? _cachedGradeKeys;
  DateTime? _lastClassesUpdate;

  // Refresh state
  bool _isRefreshing = false;

  // NEW: Classes loading state
  bool _isClassesLoading = true;
  String? _classesError;

  // NEW: Separate stream for students to prevent unnecessary rebuilds
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _studentsStream;

  @override
  void initState() {
    super.initState();

    // Initialize the stream once in initState to prevent recreation
    _studentsStream = FirebaseFirestore.instance
        .collection('users')
        .where('school_code', isEqualTo: widget.schoolCode)
        .where('role', isEqualTo: 'student')
        .orderBy('full_name')
        .snapshots();

    _loadClassesData(); // 👈 Load classes once when widget initializes
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    // Clear cache
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('classes_') && key.contains(widget.schoolCode)) {
        await prefs.remove(key);
      }
    }

    // Reload data using the same loader
    await _loadClassesData(force: true);

    setState(() {
      _isRefreshing = false;
    });
  }

  // UPDATED: _loadClassesData method with proper state management
  Future<void> _loadClassesData({bool force = false}) async {
    // Check if cache is still valid (5 minutes)
    final now = DateTime.now();
    if (!force &&
        _cachedClassDocs != null &&
        _lastClassesUpdate != null &&
        now.difference(_lastClassesUpdate!).inMinutes < 5) {
      return;
    }

    setState(() {
      _isClassesLoading = true;
      _classesError = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();

      final classDocs = snapshot.docs
          .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();

      // Update cache
      setState(() {
        _cachedClassDocs = classDocs;
        _cachedGradeGroups = _buildGradeGroups(classDocs);
        _cachedGradeKeys = _cachedGradeGroups!.keys.toList()
          ..sort((a, b) {
            final na = num.tryParse(a.replaceAll(RegExp('[^0-9-]'), ''));
            final nb = num.tryParse(b.replaceAll(RegExp('[^0-9-]'), ''));
            if (na != null && nb != null) return na.compareTo(nb);
            return a.compareTo(b);
          });
        _lastClassesUpdate = now;
        _isClassesLoading = false;
      });
    } catch (e) {
      setState(() {
        _isClassesLoading = false;
        _classesError = 'Error loading classes: $e';
      });
      widget.onMessage('Error loading classes: ${e.toString()}', true);
    }
  }

  List<String> _parseSections(dynamic raw) {
    if (raw == null) return [];
    if (raw is String) {
      return raw
          .split(',')
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      return [];
    }
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _findClassDocById(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> classDocs,
    String id,
  ) {
    for (final d in classDocs) {
      if (d.id == id) return d;
    }
    return null;
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _findClassDocByGradeAndSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> classDocs,
    String grade,
    String? section,
  ) {
    QueryDocumentSnapshot<Map<String, dynamic>>? firstGradeMatch;
    for (final doc in classDocs) {
      final data = doc.data() ?? <String, dynamic>{};
      final docGrade = (data['grade'] ?? '').toString().trim();
      if (docGrade != grade) continue;
      firstGradeMatch ??= doc;

      final sections = _parseSections(data['sections']);
      if (section != null && section.isNotEmpty) {
        if (sections.any((s) => s.toLowerCase() == section.toLowerCase())) {
          return doc;
        }
      }
    }
    return firstGradeMatch;
  }

  bool _sectionExistsInClass(
    List<String> classSections,
    String sectionToCheck,
  ) {
    return classSections.any(
      (section) => section.toLowerCase() == sectionToCheck.toLowerCase(),
    );
  }

  void _setEditingStudent(String? studentId) {
    setState(() {
      _currentlyEditingStudentId = studentId;
    });
  }

  // NEW: Optimized method to handle student selection without rebuilding everything
  void _handleStudentSelection(String studentId, bool selected) {
    widget.onStudentSelectionChanged(studentId, selected);
  }

  Map<String, Map<String, dynamic>> _buildGradeGroups(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> classDocs,
  ) {
    final Map<String, Map<String, dynamic>> gradeGroups = {};
    for (final doc in classDocs) {
      final data = doc.data() ?? <String, dynamic>{};
      final gradeRaw = (data['grade']?.toString() ?? '').trim();
      final gradeKey = gradeRaw.isNotEmpty ? gradeRaw : '(Unknown)';

      final sectionsList = _parseSections(data['sections']);

      if (!gradeGroups.containsKey(gradeKey)) {
        gradeGroups[gradeKey] = {
          'classIds': <String>[],
          'sections': <String>{},
        };
      }

      (gradeGroups[gradeKey]!['classIds'] as List<String>).add(doc.id);
      (gradeGroups[gradeKey]!['sections'] as Set<String>).addAll(sectionsList);
    }
    return gradeGroups;
  }

  // UPDATED: Build method without FutureBuilder
  @override
  Widget build(BuildContext context) {
    // Show loading indicator if classes are still loading and we have no cached data
    if (_isClassesLoading && _cachedClassDocs == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show error if classes failed to load and we have no cached data
    if (_classesError != null && _cachedClassDocs == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              _classesError!,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _loadClassesData(force: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final classDocs = _cachedClassDocs!;
    final gradeGroups = _cachedGradeGroups!;
    final gradeKeys = _cachedGradeKeys!;

    final allSectionsSet = <String>{};
    for (final g in gradeGroups.keys) {
      allSectionsSet.addAll(
        (gradeGroups[g]!['sections'] as Set<String>?) ?? <String>{},
      );
    }
    final allSections = allSectionsSet.toList()..sort();

    return Column(
      children: [
        // Filter bar - This rarely changes, so it's stable
        _buildFilterBar(gradeKeys, allSections, gradeGroups),
        const SizedBox(height: 16),

        // Bulk selection header - Only shown in bulk mode
        if (widget.isBulkMode)
          _BulkSelectionHeader(
            schoolCode: widget.schoolCode,
            classDocs: classDocs,
            selectedStudents: widget.selectedStudents,
            onSelectAllStudents: widget.onSelectAllStudents,
            isDesktop: widget.isDesktop,
            searchQuery: widget.searchQuery,
            filterGrade: widget.filterGrade,
            filterSection: widget.filterSection,
            findClassDocById: _findClassDocById,
            shouldShowStudent: _shouldShowStudent,
          ),

        // Students list - The main content that needs to be stable
        Expanded(
          child: _StudentsListView(
            schoolCode: widget.schoolCode,
            classDocs: classDocs,
            gradeGroups: gradeGroups,
            gradeKeys: gradeKeys,
            searchQuery: widget.searchQuery,
            filterGrade: widget.filterGrade,
            filterSection: widget.filterSection,
            scrollController: widget.scrollController,
            isBulkMode: widget.isBulkMode,
            selectedStudents: widget.selectedStudents,
            currentlyEditingStudentId: _currentlyEditingStudentId,
            onStudentSelectionChanged: _handleStudentSelection,
            onStartEditing: _setEditingStudent,
            onStopEditing: _setEditingStudent,
            onMessage: widget.onMessage,
            findClassDocById: _findClassDocById,
            findClassDocByGradeAndSection: _findClassDocByGradeAndSection,
            sectionExistsInClass: _sectionExistsInClass,
            isDesktop: widget.isDesktop,
            studentsStream: _studentsStream, // Use the pre-initialized stream
          ),
        ),
      ],
    );
  }

  bool _shouldShowStudent(
    QueryDocumentSnapshot<Map<String, dynamic>> student,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> classDocs,
  ) {
    try {
      final data = student.data() ?? <String, dynamic>{};
      final username = (data['username'] ?? '').toString();
      final fullName = (data['full_name'] ?? '').toString();
      final studentSection = (data['section'] ?? '').toString();

      String? studentGradeKey;
      final classId = (data['class_id'] as String?)?.toString();
      if (classId != null && classId.isNotEmpty) {
        final found = _findClassDocById(classDocs, classId);
        if (found != null) {
          final cdata = found.data() ?? <String, dynamic>{};
          final g = (cdata['grade']?.toString() ?? '').trim();
          if (g.isNotEmpty) studentGradeKey = g;
        }
      }

      if (studentGradeKey == null && (data['class_name'] is String)) {
        final cn = (data['class_name'] as String);
        if (cn.startsWith('Grade ')) {
          studentGradeKey = cn.replaceFirst('Grade ', '').trim();
        }
      }

      if (widget.searchQuery.isNotEmpty) {
        final combined = (username + ' ' + fullName).toLowerCase();
        if (!combined.contains(widget.searchQuery.toLowerCase())) return false;
      }

      if (widget.filterGrade != null) {
        if (studentGradeKey == null) return false;
        if (studentGradeKey != widget.filterGrade) return false;
      }

      if (widget.filterSection != null) {
        if (studentSection.isEmpty) return false;
        if (studentSection != widget.filterSection) return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Widget _buildFilterBar(
    List<String> gradeKeys,
    List<String> allSections,
    Map<String, Map<String, dynamic>> gradeGroups,
  ) {
    if (widget.isDesktop) {
      return _buildDesktopFilterBar(gradeKeys, allSections, gradeGroups);
    } else {
      return _buildMobileFilterBar(gradeKeys, allSections, gradeGroups);
    }
  }

  Widget _buildDesktopFilterBar(
    List<String> gradeKeys,
    List<String> allSections,
    Map<String, Map<String, dynamic>> gradeGroups,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: widget.searchController,
                  focusNode: widget.searchFocusNode,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search students by name or username...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) {
                    widget.onSearchChanged(v.trim());
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: widget.filterGrade,
                  hint: const Text('All Classes'),
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Classes'),
                    ),
                    ...gradeKeys.map(
                      (g) => DropdownMenuItem<String?>(
                        value: g,
                        child: Text(
                          g == '(Unknown)' ? 'Grade (Unknown)' : 'Grade $g',
                        ),
                      ),
                    ),
                  ],
                  onChanged: widget.onFilterGradeChanged,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: widget.filterSection,
                  hint: const Text('All Sections'),
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Sections'),
                    ),
                    ...((widget.filterGrade == null)
                            ? allSections
                            : ((gradeGroups[widget.filterGrade]?['sections']
                                          as Set<String>?)
                                      ?.toList() ??
                                  <String>[]))
                        .map(
                          (s) => DropdownMenuItem<String?>(
                            value: s,
                            child: Text(s),
                          ),
                        ),
                  ],
                  onChanged: widget.onFilterSectionChanged,
                ),
              ),
              const SizedBox(width: 16),
              PopupMenuButton<void>(
                icon: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.filter_alt),
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(enabled: false, child: Text('Filters')),
                  PopupMenuItem(
                    child: ListTile(
                      leading: const Icon(Icons.clear),
                      title: const Text('Clear All Filters'),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onFilterGradeChanged(null);
                        widget.onFilterSectionChanged(null);
                        widget.searchController.clear();
                        widget.onSearchChanged('');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFilterBar(
    List<String> gradeKeys,
    List<String> allSections,
    Map<String, Map<String, dynamic>> gradeGroups,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.searchController,
                focusNode: widget.searchFocusNode,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search students by name or username',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) {
                  widget.onSearchChanged(v.trim());
                },
              ),
            ),
            const SizedBox(width: 12),
            PopupMenuButton<void>(
              icon: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.filter_alt),
              ),
              itemBuilder: (context) => [
                const PopupMenuItem(enabled: false, child: Text('Filters')),
                PopupMenuItem(
                  child: ListTile(
                    leading: const Icon(Icons.clear),
                    title: const Text('Clear All Filters'),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onFilterGradeChanged(null);
                      widget.onFilterSectionChanged(null);
                      widget.searchController.clear();
                      widget.onSearchChanged('');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: widget.filterGrade,
                hint: const Text('All Classes'),
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Classes'),
                  ),
                  ...gradeKeys.map(
                    (g) => DropdownMenuItem<String?>(
                      value: g,
                      child: Text(
                        g == '(Unknown)' ? 'Grade (Unknown)' : 'Grade $g',
                      ),
                    ),
                  ),
                ],
                onChanged: widget.onFilterGradeChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: widget.filterSection,
                hint: const Text('All Sections'),
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Sections'),
                  ),
                  ...((widget.filterGrade == null)
                          ? allSections
                          : ((gradeGroups[widget.filterGrade]?['sections']
                                        as Set<String>?)
                                    ?.toList() ??
                                <String>[]))
                      .map(
                        (s) =>
                            DropdownMenuItem<String?>(value: s, child: Text(s)),
                      ),
                ],
                onChanged: widget.onFilterSectionChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// NEW: Separate widget for bulk selection header to minimize rebuilds
class _BulkSelectionHeader extends StatelessWidget {
  final String schoolCode;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> classDocs;
  final Set<String> selectedStudents;
  final ValueChanged<List<String>> onSelectAllStudents;
  final bool isDesktop;
  final String searchQuery;
  final String? filterGrade;
  final String? filterSection;
  final QueryDocumentSnapshot<Map<String, dynamic>>? Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    String,
  )
  findClassDocById;
  final bool Function(
    QueryDocumentSnapshot<Map<String, dynamic>>,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
  )
  shouldShowStudent;

  const _BulkSelectionHeader({
    required this.schoolCode,
    required this.classDocs,
    required this.selectedStudents,
    required this.onSelectAllStudents,
    required this.isDesktop,
    required this.searchQuery,
    required this.filterGrade,
    required this.filterSection,
    required this.findClassDocById,
    required this.shouldShowStudent,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: schoolCode)
          .where('role', isEqualTo: 'student')
          .orderBy('full_name')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[100]!),
            ),
            child: Row(
              children: [
                Icon(Icons.error, color: Colors.red[400], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Error loading students: ${snapshot.error}',
                    style: TextStyle(color: Colors.red[700], fontSize: 14),
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) return const SizedBox();

        final students = snapshot.data!.docs;
        final filteredStudentIds = students
            .where((student) => shouldShowStudent(student, classDocs))
            .map((student) => student.id)
            .toList();

        final allSelected =
            filteredStudentIds.isNotEmpty &&
            selectedStudents.length == filteredStudentIds.length;

        return Container(
          padding: isDesktop
              ? const EdgeInsets.all(16)
              : const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Checkbox(
                value: allSelected,
                tristate: true,
                onChanged: (value) {
                  if (value == true) {
                    onSelectAllStudents(filteredStudentIds);
                  } else {
                    onSelectAllStudents([]);
                  }
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Select all filtered students',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: isDesktop ? 16 : 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Text(
                  '${selectedStudents.length} selected',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[700],
                    fontSize: isDesktop ? 14 : 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// NEW: Separate widget for students list to prevent unnecessary rebuilds
class _StudentsListView extends StatelessWidget {
  final String schoolCode;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> classDocs;
  final Map<String, Map<String, dynamic>> gradeGroups;
  final List<String> gradeKeys;
  final String searchQuery;
  final String? filterGrade;
  final String? filterSection;
  final ScrollController scrollController;
  final bool isBulkMode;
  final Set<String> selectedStudents;
  final String? currentlyEditingStudentId;
  final ValueChanged2<String, bool> onStudentSelectionChanged;
  final ValueChanged<String> onStartEditing;
  final ValueChanged<String?> onStopEditing;
  final ValueChanged2<String, bool> onMessage;
  final QueryDocumentSnapshot<Map<String, dynamic>>? Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    String,
  )
  findClassDocById;
  final QueryDocumentSnapshot<Map<String, dynamic>>? Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    String,
    String?,
  )
  findClassDocByGradeAndSection;
  final bool Function(List<String>, String) sectionExistsInClass;
  final bool isDesktop;
  final Stream<QuerySnapshot<Map<String, dynamic>>> studentsStream;

  const _StudentsListView({
    required this.schoolCode,
    required this.classDocs,
    required this.gradeGroups,
    required this.gradeKeys,
    required this.searchQuery,
    required this.filterGrade,
    required this.filterSection,
    required this.scrollController,
    required this.isBulkMode,
    required this.selectedStudents,
    required this.currentlyEditingStudentId,
    required this.onStudentSelectionChanged,
    required this.onStartEditing,
    required this.onStopEditing,
    required this.onMessage,
    required this.findClassDocById,
    required this.findClassDocByGradeAndSection,
    required this.sectionExistsInClass,
    required this.isDesktop,
    required this.studentsStream,
  });

  bool _shouldShowStudent(QueryDocumentSnapshot<Map<String, dynamic>> student) {
    try {
      final data = student.data() ?? <String, dynamic>{};
      final username = (data['username'] ?? '').toString();
      final fullName = (data['full_name'] ?? '').toString();
      final studentSection = (data['section'] ?? '').toString();

      String? studentGradeKey;
      final classId = (data['class_id'] as String?)?.toString();
      if (classId != null && classId.isNotEmpty) {
        final found = findClassDocById(classDocs, classId);
        if (found != null) {
          final cdata = found.data() ?? <String, dynamic>{};
          final g = (cdata['grade']?.toString() ?? '').trim();
          if (g.isNotEmpty) studentGradeKey = g;
        }
      }

      if (studentGradeKey == null && (data['class_name'] is String)) {
        final cn = (data['class_name'] as String);
        if (cn.startsWith('Grade ')) {
          studentGradeKey = cn.replaceFirst('Grade ', '').trim();
        }
      }

      if (searchQuery.isNotEmpty) {
        final combined = (username + ' ' + fullName).toLowerCase();
        if (!combined.contains(searchQuery.toLowerCase())) return false;
      }

      if (filterGrade != null) {
        if (studentGradeKey == null) return false;
        if (studentGradeKey != filterGrade) return false;
      }

      if (filterSection != null) {
        if (studentSection.isEmpty) return false;
        if (studentSection != filterSection) return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: studentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  'Error loading students: ${snapshot.error}',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final students =
            snapshot.data?.docs
                .cast<QueryDocumentSnapshot<Map<String, dynamic>>>() ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        if (students.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.school, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No students found in this school',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          );
        }

        final filteredStudents = students.where(_shouldShowStudent).toList();

        if (filteredStudents.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No students match the current filters',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          );
        }

        if (isDesktop) {
          return _buildDesktopStudentsList(filteredStudents);
        } else {
          return _buildMobileStudentsList(filteredStudents);
        }
      },
    );
  }

  Widget _buildDesktopStudentsList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredStudents,
  ) {
    return ListView.builder(
      key: const PageStorageKey('students-list'),
      controller: scrollController,
      itemCount: filteredStudents.length,
      itemBuilder: (context, index) {
        final studentDoc = filteredStudents[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: _StudentCard(
            key: ValueKey(studentDoc.id), // Use ValueKey for stability
            studentDoc: studentDoc,
            classDocs: classDocs,
            gradeGroups: gradeGroups,
            gradeKeys: gradeKeys,
            isEditing: currentlyEditingStudentId == studentDoc.id,
            isBulkMode: isBulkMode,
            isSelected: selectedStudents.contains(studentDoc.id),
            onStartEditing: () => onStartEditing(studentDoc.id),
            onStopEditing: () => onStopEditing(null),
            onMessage: onMessage,
            onSelectionChanged: onStudentSelectionChanged,
            findClassDocById: findClassDocById,
            findClassDocByGradeAndSection: findClassDocByGradeAndSection,
            sectionExistsInClass: sectionExistsInClass,
            isDesktop: true,
          ),
        );
      },
    );
  }

  Widget _buildMobileStudentsList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredStudents,
  ) {
    return ListView.builder(
      key: const PageStorageKey('students-list'),
      controller: scrollController,
      itemCount: filteredStudents.length,
      itemBuilder: (context, index) {
        final studentDoc = filteredStudents[index];
        return _StudentCard(
          key: ValueKey(studentDoc.id), // Use ValueKey for stability
          studentDoc: studentDoc,
          classDocs: classDocs,
          gradeGroups: gradeGroups,
          gradeKeys: gradeKeys,
          isEditing: currentlyEditingStudentId == studentDoc.id,
          isBulkMode: isBulkMode,
          isSelected: selectedStudents.contains(studentDoc.id),
          onStartEditing: () => onStartEditing(studentDoc.id),
          onStopEditing: () => onStopEditing(null),
          onMessage: onMessage,
          onSelectionChanged: onStudentSelectionChanged,
          findClassDocById: findClassDocById,
          findClassDocByGradeAndSection: findClassDocByGradeAndSection,
          sectionExistsInClass: sectionExistsInClass,
          isDesktop: false,
        );
      },
    );
  }
}

class _StudentCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> studentDoc;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> classDocs;
  final Map<String, Map<String, dynamic>> gradeGroups;
  final List<String> gradeKeys;
  final bool isEditing;
  final bool isBulkMode;
  final bool isSelected;
  final VoidCallback onStartEditing;
  final VoidCallback onStopEditing;
  final ValueChanged2<String, bool> onMessage;
  final ValueChanged2<String, bool>
  onSelectionChanged; // CHANGED: Now accepts both studentId and selected
  final QueryDocumentSnapshot<Map<String, dynamic>>? Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    String,
  )
  findClassDocById;
  final QueryDocumentSnapshot<Map<String, dynamic>>? Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    String,
    String?,
  )
  findClassDocByGradeAndSection;
  final bool Function(List<String>, String) sectionExistsInClass;
  final bool isDesktop;

  const _StudentCard({
    super.key,
    required this.studentDoc,
    required this.classDocs,
    required this.gradeGroups,
    required this.gradeKeys,
    required this.isEditing,
    required this.isBulkMode,
    required this.isSelected,
    required this.onStartEditing,
    required this.onStopEditing,
    required this.onMessage,
    required this.onSelectionChanged, // CHANGED: Now accepts both studentId and selected
    required this.findClassDocById,
    required this.findClassDocByGradeAndSection,
    required this.sectionExistsInClass,
    required this.isDesktop,
  });

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  late final String studentId;
  late final Map<String, dynamic> studentData;
  late final String username;
  late final String fullName;
  late final String? currentClassId;
  late final String currentClassName;
  late final String currentSection;

  String? _selectedGrade;
  String? _selectedSection;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    studentId = widget.studentDoc.id;
    studentData = widget.studentDoc.data() ?? <String, dynamic>{};
    username = studentData['username']?.toString() ?? 'No username';
    fullName = studentData['full_name']?.toString() ?? 'No name';
    currentClassId = studentData['class_id'] as String?;
    currentClassName = studentData['class_name']?.toString() ?? 'Not assigned';
    currentSection = studentData['section']?.toString() ?? '';

    _initializeSelections();
  }

  @override
  void didUpdateWidget(_StudentCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only update selections if the student data actually changed
    if (widget.studentDoc != oldWidget.studentDoc) {
      _initializeSelections();
    }
  }

  void _initializeSelections() {
    // Initialize grade selection
    _selectedGrade = _getCurrentGrade();

    // Initialize section selection
    _selectedSection = _getCurrentSection();
  }

  String? _getCurrentGrade() {
    if (currentClassId != null) {
      final matchDoc = widget.findClassDocById(
        widget.classDocs,
        currentClassId!,
      );
      if (matchDoc != null) {
        final mdata = matchDoc.data() ?? <String, dynamic>{};
        final mg = (mdata['grade']?.toString() ?? '').trim();
        if (mg.isNotEmpty) return mg;
      }
    }

    if (currentClassName.startsWith('Grade ')) {
      return currentClassName.replaceFirst('Grade ', '').trim();
    }

    return null;
  }

  String? _getCurrentSection() {
    if (currentSection.isNotEmpty) {
      if (currentClassId != null) {
        final currentClassDoc = widget.findClassDocById(
          widget.classDocs,
          currentClassId!,
        );
        if (currentClassDoc != null) {
          final classData = currentClassDoc.data() ?? <String, dynamic>{};
          final classSections = _parseSections(classData['sections']);
          final validSection = _getValidSectionForStudent(
            currentSection,
            classSections,
          );
          if (validSection != null) {
            return validSection;
          }
        }
      }
    }

    // If grade is selected, preselect first section from its aggregated list
    if (_selectedGrade != null &&
        widget.gradeGroups.containsKey(_selectedGrade)) {
      final secs =
          (widget.gradeGroups[_selectedGrade]!['sections'] as Set<String>)
              .toList();
      return secs.isNotEmpty ? secs.first : null;
    }

    return null;
  }

  List<String> _parseSections(dynamic raw) {
    if (raw == null) return [];
    if (raw is String) {
      return raw
          .split(',')
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      return [];
    }
  }

  String? _getValidSectionForStudent(
    String? currentSection,
    List<String> classSections,
  ) {
    if (currentSection == null || currentSection.isEmpty) return null;

    final validSection = classSections.firstWhere(
      (section) => section.toLowerCase() == currentSection.toLowerCase(),
      orElse: () => '',
    );

    return validSection.isNotEmpty ? validSection : null;
  }

  Future<void> _assignStudent() async {
    if (_selectedGrade == null) {
      widget.onMessage('Please select a class (grade) before assigning.', true);
      return;
    }

    final matchedClassDoc = widget.findClassDocByGradeAndSection(
      widget.classDocs,
      _selectedGrade!,
      _selectedSection,
    );

    if (matchedClassDoc == null) {
      widget.onMessage(
        'No class document found for selected grade/section.',
        true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final classData = matchedClassDoc.data() ?? <String, dynamic>{};
      final gradeVal = (classData['grade']?.toString() ?? '').trim();
      final sectionToSave = _selectedSection ?? '';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(studentId)
          .update({
            'class_id': matchedClassDoc.id,
            'class_name': gradeVal.isNotEmpty ? 'Grade $gradeVal' : null,
            'section': sectionToSave.isNotEmpty ? sectionToSave : null,
            'updated_at': FieldValue.serverTimestamp(),
          });

      widget.onMessage('Student assigned to class successfully', false);
      widget.onStopEditing();
    } catch (e) {
      widget.onMessage('Error assigning student: ${e.toString()}', true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _unassignStudent() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(studentId)
          .update({
            'class_id': null,
            'class_name': null,
            'section': null,
            'updated_at': FieldValue.serverTimestamp(),
          });

      widget.onMessage('Student unassigned successfully', false);
      widget.onStopEditing();
    } catch (e) {
      widget.onMessage('Error unassigning student: ${e.toString()}', true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDesktop) {
      return _buildDesktopCard();
    } else {
      return _buildMobileCard();
    }
  }

  Widget _buildDesktopCard() {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: widget.isSelected ? Colors.blue[50] : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Selection checkbox (only in bulk mode)
                if (widget.isBulkMode) ...[
                  Checkbox(
                    value: widget.isSelected,
                    onChanged: (value) {
                      // CHANGED: Pass both studentId and selected value
                      widget.onSelectionChanged(studentId, value ?? false);
                    },
                  ),
                  const SizedBox(width: 16),
                ],
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  radius: 24,
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Full Name - Username display with text wrapping
                      Wrap(
                        children: [
                          Text(
                            '$fullName - $username',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Class: $currentClassName${currentSection.isNotEmpty ? ' ($currentSection)' : ''}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      if (currentClassId != null && currentSection.isNotEmpty)
                        Builder(
                          builder: (context) {
                            final currentClassDoc = widget.findClassDocById(
                              widget.classDocs,
                              currentClassId!,
                            );
                            if (currentClassDoc != null) {
                              final classData =
                                  currentClassDoc.data() ?? <String, dynamic>{};
                              final classSections = _parseSections(
                                classData['sections'],
                              );
                              final isValidSection = widget
                                  .sectionExistsInClass(
                                    classSections,
                                    currentSection,
                                  );
                              if (!isValidSection) {
                                return const Text(
                                  '⚠️ Section no longer exists in this class',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                  ),
                                );
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                    ],
                  ),
                ),
                if (!widget.isEditing && !widget.isBulkMode)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Assignment'),
                    onPressed: widget.onStartEditing,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  )
                else if (!widget.isBulkMode)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                    onPressed: widget.onStopEditing,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.isEditing && !widget.isBulkMode) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Assign to Class:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedGrade,
                      hint: const Text('Select Class (Grade)'),
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: widget.gradeKeys.map((gradeKey) {
                        final display = gradeKey == '(Unknown)'
                            ? 'Grade (Unknown)'
                            : 'Grade $gradeKey';
                        return DropdownMenuItem<String?>(
                          value: gradeKey,
                          child: Text(display),
                        );
                      }).toList(),
                      onChanged: (selectedGrade) {
                        setState(() {
                          _selectedGrade = selectedGrade;
                          // Reset section when grade changes
                          if (selectedGrade != null &&
                              widget.gradeGroups.containsKey(selectedGrade)) {
                            final secs =
                                (widget.gradeGroups[selectedGrade]!['sections']
                                        as Set<String>)
                                    .toList();
                            _selectedSection = secs.isNotEmpty
                                ? secs.first
                                : null;
                          } else {
                            _selectedSection = null;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        if (_selectedGrade == null) {
                          return const Text('Select a class to choose section');
                        }

                        final sectionsSet =
                            widget.gradeGroups[_selectedGrade]!['sections']
                                as Set<String>;
                        final sections = sectionsSet.toList();

                        if (sections.isEmpty) {
                          return const Text(
                            'No sections defined for this class',
                          );
                        }

                        // Ensure current section value exists in available sections
                        String? currentSectionValue = _selectedSection;
                        if (currentSectionValue != null) {
                          final exists = sections.any(
                            (s) => s == currentSectionValue,
                          );
                          if (!exists) {
                            currentSectionValue = null;
                          }
                        }

                        return DropdownButtonFormField<String?>(
                          value: currentSectionValue,
                          hint: const Text('Select Section'),
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          items: sections.map((sec) {
                            return DropdownMenuItem<String?>(
                              value: sec,
                              child: Text(sec),
                            );
                          }).toList(),
                          onChanged: (sec) {
                            setState(() {
                              _selectedSection = sec;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _isLoading ? null : _assignStudent,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Assign to Class'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _isLoading ? null : _unassignStudent,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      side: BorderSide(color: Colors.red[400]!),
                      foregroundColor: Colors.red[600],
                    ),
                    child: const Text('Unassign'),
                  ),
                  const Spacer(),
                  if (_isLoading)
                    const Text(
                      'Updating...',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: widget.isSelected ? Colors.blue[50] : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Selection checkbox (only in bulk mode)
                if (widget.isBulkMode) ...[
                  Checkbox(
                    value: widget.isSelected,
                    onChanged: (value) {
                      // CHANGED: Pass both studentId and selected value
                      widget.onSelectionChanged(studentId, value ?? false);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Full Name - Username display with text wrapping
                      Wrap(
                        children: [
                          Text(
                            '$fullName - $username',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Class: $currentClassName${currentSection.isNotEmpty ? ' ($currentSection)' : ''}',
                      ),
                      if (currentClassId != null && currentSection.isNotEmpty)
                        Builder(
                          builder: (context) {
                            final currentClassDoc = widget.findClassDocById(
                              widget.classDocs,
                              currentClassId!,
                            );
                            if (currentClassDoc != null) {
                              final classData =
                                  currentClassDoc.data() ?? <String, dynamic>{};
                              final classSections = _parseSections(
                                classData['sections'],
                              );
                              final isValidSection = widget
                                  .sectionExistsInClass(
                                    classSections,
                                    currentSection,
                                  );
                              if (!isValidSection) {
                                return const Text(
                                  '⚠️ Section no longer exists',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                  ),
                                );
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                    ],
                  ),
                ),
                if (!widget.isEditing && !widget.isBulkMode)
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: widget.onStartEditing,
                    tooltip: 'Edit assignment',
                  )
                else if (!widget.isBulkMode)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onStopEditing,
                    tooltip: 'Close',
                  ),
              ],
            ),
            if (widget.isEditing && !widget.isBulkMode) ...[
              const SizedBox(height: 12),
              const Text(
                'Assign to Class:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: _selectedGrade,
                hint: const Text('Select Class (Grade)'),
                isExpanded: true,
                items: widget.gradeKeys.map((gradeKey) {
                  final display = gradeKey == '(Unknown)'
                      ? 'Grade (Unknown)'
                      : 'Grade $gradeKey';
                  return DropdownMenuItem<String?>(
                    value: gradeKey,
                    child: Text(display),
                  );
                }).toList(),
                onChanged: (selectedGrade) {
                  setState(() {
                    _selectedGrade = selectedGrade;
                    // Reset section when grade changes
                    if (selectedGrade != null &&
                        widget.gradeGroups.containsKey(selectedGrade)) {
                      final secs =
                          (widget.gradeGroups[selectedGrade]!['sections']
                                  as Set<String>)
                              .toList();
                      _selectedSection = secs.isNotEmpty ? secs.first : null;
                    } else {
                      _selectedSection = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  if (_selectedGrade == null) {
                    return const Text('Select a class to choose section');
                  }

                  final sectionsSet =
                      widget.gradeGroups[_selectedGrade]!['sections']
                          as Set<String>;
                  final sections = sectionsSet.toList();

                  if (sections.isEmpty) {
                    return const Text('No sections defined for this class');
                  }

                  // Ensure current section value exists in available sections
                  String? currentSectionValue = _selectedSection;
                  if (currentSectionValue != null) {
                    final exists = sections.any(
                      (s) => s == currentSectionValue,
                    );
                    if (!exists) {
                      currentSectionValue = null;
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Section:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        value: currentSectionValue,
                        isExpanded: true,
                        items: sections.map((sec) {
                          return DropdownMenuItem<String?>(
                            value: sec,
                            child: Text(sec),
                          );
                        }).toList(),
                        onChanged: (sec) {
                          setState(() {
                            _selectedSection = sec;
                          });
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _assignStudent,
                      child: _isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Assign'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _unassignStudent,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[600],
                        side: BorderSide(color: Colors.red[400]!),
                      ),
                      child: const Text('Unassign'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Helper typedef for callbacks
typedef ValueChanged2<T1, T2> = void Function(T1 value1, T2 value2);
