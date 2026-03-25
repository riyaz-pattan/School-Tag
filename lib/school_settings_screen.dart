import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_dashboard_screen.dart';

class SchoolSettingsScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;

  const SchoolSettingsScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<SchoolSettingsScreen> createState() => _SchoolSettingsScreenState();
}

class _SchoolSettingsScreenState extends State<SchoolSettingsScreen> {
  String _attendanceType = 'per_day';
  String? _errorMessage;
  String? _successMessage;
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
    _loadSettings();
  }

  @override
  void dispose() {
    _infoPageController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('settings')
          .doc('config')
          .get();

      if (settingsDoc.exists) {
        final data = settingsDoc.data()!;
        setState(() {
          _attendanceType = data['attendance_type'] ?? 'per_day';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading settings: $e';
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('settings')
          .doc('config')
          .set({
            'attendance_type': _attendanceType,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      setState(() {
        _successMessage = 'Settings saved successfully';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving settings: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
      title: Text('School Settings - ${widget.schoolName}'),
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
                  Icons.settings,
                  size: 40,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
                const SizedBox(height: 8),
                const Text(
                  'School Settings',
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
            'School Settings Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildSidebarInfoItem(
            Icons.attribution,
            'Attendance Settings',
            'Configure how attendance is tracked in your school',
          ),
          _buildSidebarInfoItem(
            Icons.calendar_today,
            'Per Day (One Period)',
            'Simple daily attendance marking for fixed schedules',
          ),
          _buildSidebarInfoItem(
            Icons.event_repeat,
            'Per Day - Twice',
            'Morning and afternoon sessions for distinct periods',
          ),
          _buildSidebarInfoItem(
            Icons.schedule,
            'Per Period',
            'Detailed period-wise tracking for flexible timetables',
          ),
          _buildSidebarInfoItem(
            Icons.save,
            'Save Settings',
            'Remember to save changes after updating preferences',
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
            'Attendance Settings Guide',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
          _buildTipItem(
            '📅',
            'Choose the method that fits your school schedule',
          ),
          _buildTipItem(
            '⏰',
            'Per Day: Best for schools with consistent daily routines',
          ),
          _buildTipItem(
            '🔄',
            'Per Day - Twice: Ideal for schools with morning/afternoon sessions',
          ),
          _buildTipItem(
            '📚',
            'Per Period: Perfect for schools with subject-wise timetables',
          ),
          _buildTipItem(
            '💾',
            'Settings are saved automatically and apply to all users',
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
              'Need help? Contact your system administrator for assistance with school settings.',
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
            'School Settings - ${widget.schoolName}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _loadSettings,
            tooltip: 'Refresh Settings',
          ),
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
            'School Settings',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // School Info Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.school, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.schoolName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text('School Code: ${widget.schoolCode}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Settings Card
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
                const Row(
                  children: [
                    Icon(
                      Icons.attribution,
                      color: Color.fromARGB(255, 21, 101, 192),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Attendance Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 21, 101, 192),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select how attendance should be marked for your school:',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 20),

                // Attendance Type Options
                _buildAttendanceOptionCard(
                  'Per Day (One Period Only)',
                  'Teachers mark attendance once daily',
                  'per_day',
                  Icons.calendar_today,
                  Colors.blue,
                ),
                const SizedBox(height: 12),
                _buildAttendanceOptionCard(
                  'Per Day - Twice',
                  'Teachers mark attendance twice daily',
                  'per_day_twice',
                  Icons.event_repeat,
                  Colors.green,
                ),
                const SizedBox(height: 12),
                _buildAttendanceOptionCard(
                  'Per Period',
                  'Teachers mark attendance for each period',
                  'per_period',
                  Icons.schedule,
                  Colors.orange,
                ),

                const SizedBox(height: 24),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SizedBox(
                        width: _isDesktop ? 200 : double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveSettings,
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
                            'Save Settings',
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
                if (_successMessage != null) ...[
                  const SizedBox(height: 16),
                  _buildSuccessMessage(_successMessage!),
                ],
              ],
            ),
          ),
        ),

        // Information Section
        const SizedBox(height: 24),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'About Attendance Types',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildMainContentInfoItem(
                  'Per Day (One Period)',
                  'Simple daily attendance marking. Suitable for schools with fixed schedules.',
                ),
                _buildMainContentInfoItem(
                  'Per Day - Twice',
                  'Morning and afternoon sessions. Ideal for schools with distinct sessions.',
                ),
                _buildMainContentInfoItem(
                  'Per Period',
                  'Detailed period-wise tracking. Best for schools with flexible timetables.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceOptionCard(
    String title,
    String description,
    String value,
    IconData icon,
    Color color,
  ) {
    final isSelected = _attendanceType == value;

    return Card(
      elevation: isSelected ? 8 : 2,
      color: isSelected ? Colors.white : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? color : Colors.grey[300]!,
          width: isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _attendanceType = value;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.1),
                      color.withOpacity(0.05),
                      Colors.white,
                    ],
                  )
                : null,
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon with clear border
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected ? color : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? color : Colors.grey[400]!,
                    width: 2,
                  ),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? color : Colors.black,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: isSelected ? Colors.black87 : Colors.grey[600],
                        fontWeight: isSelected
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),

              // Clear selection indicator
              const SizedBox(width: 8),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected ? color : Colors.grey[400],
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContentInfoItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
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

  Widget _buildSuccessMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[100]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.green, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
