// users_count_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UsersCountScreen extends StatefulWidget {
  final String userId;

  const UsersCountScreen({super.key, required this.userId});

  @override
  State<UsersCountScreen> createState() => _UsersCountScreenState();
}

class _UsersCountScreenState extends State<UsersCountScreen> {
  String? _selectedSchoolCode;
  Map<String, String> _schools = {}; // schoolCode: schoolName
  Map<String, dynamic> _userCounts = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchSchools();
  }

  Future<void> _fetchSchools() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .where('status', isEqualTo: 'active')
          .get();

      setState(() {
        _schools = {
          for (var doc in snapshot.docs) doc.id: doc['name'] as String,
        };
      });
    } catch (e) {
      print('Error fetching schools: $e');
      _showError('Error loading schools: $e');
    }
  }

  Future<void> _fetchUserCounts(String schoolCode) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final schoolDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolCode)
          .get();

      if (schoolDoc.exists) {
        final data = schoolDoc.data()!;
        setState(() {
          _userCounts = {
            'admin_count': data['admin_count'] ?? 0,
            'teacher_count': data['teacher_count'] ?? 0,
            'student_count': data['student_count'] ?? 0,
          };
        });
      } else {
        _showError('School not found');
      }
    } catch (e) {
      print('Error fetching user counts: $e');
      _showError('Error loading user counts: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users Count by School'),
        backgroundColor: Colors.blue[700],
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // School Selection
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select School',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedSchoolCode,
                      decoration: const InputDecoration(
                        labelText: 'School',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.school),
                      ),
                      hint: const Text('Select a school'),
                      items: _schools.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(
                            '${entry.value} (${entry.key})',
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedSchoolCode = newValue;
                          _userCounts = {}; // Clear previous counts
                        });
                        if (newValue != null) {
                          _fetchUserCounts(newValue);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // User Counts Display
            if (_selectedSchoolCode != null) ...[
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_userCounts.isNotEmpty)
                _buildUserCountsCard()
              else
                _buildEmptyState(),
            ] else
              _buildInitialState(),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Select a school to view user counts',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Total schools available: ${_schools.length}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No user data found for this school',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'School: ${_schools[_selectedSchoolCode]}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCountsCard() {
    final schoolName = _schools[_selectedSchoolCode];
    final adminCount = _userCounts['admin_count'] ?? 0;
    final teacherCount = _userCounts['teacher_count'] ?? 0;
    final studentCount = _userCounts['student_count'] ?? 0;
    final totalUsers = adminCount + teacherCount + studentCount;

    return Expanded(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // School Info Card
            Card(
              elevation: 3,
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.school, size: 40, color: Colors.blue[700]),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            schoolName ?? 'Unknown School',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          Text(
                            'School Code: $_selectedSchoolCode',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Total Users Card
            _buildCountCard(
              'Total Users',
              totalUsers.toString(),
              Icons.people,
              Colors.purple,
              'All users in the school',
            ),
            const SizedBox(height: 16),

            // Role-based Count Cards
            Row(
              children: [
                Expanded(
                  child: _buildRoleCountCard(
                    'Admins',
                    adminCount.toString(),
                    Icons.admin_panel_settings,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildRoleCountCard(
                    'Teachers',
                    teacherCount.toString(),
                    Icons.school,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildRoleCountCard(
              'Students',
              studentCount.toString(),
              Icons.person,
              Colors.green,
            ),
            const SizedBox(height: 20),

            // Statistics Section
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Statistics',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatItem(
                      'Admins',
                      adminCount,
                      totalUsers,
                      Colors.red,
                    ),
                    _buildStatItem(
                      'Teachers',
                      teacherCount,
                      totalUsers,
                      Colors.orange,
                    ),
                    _buildStatItem(
                      'Students',
                      studentCount,
                      totalUsers,
                      Colors.green,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountCard(
    String title,
    String count,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              count,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCountCard(
    String role,
    String count,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
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

  Widget _buildStatItem(String role, int count, int total, Color color) {
    final percentage = total > 0 ? (count / total * 100) : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(role, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            flex: 3,
            child: LinearProgressIndicator(
              value: total > 0 ? count / total : 0,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              '${percentage.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
