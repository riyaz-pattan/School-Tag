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
  Map<String, String> _schools = {};
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
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: const Color(0xFFBA1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFF),
      appBar: AppBar(
        title: const Text('User Analytics', style: TextStyle(color: Color(0xFF001F2A), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00113A)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isDesktop ? 32 : 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF001F2A).withOpacity(0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F6FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.apartment_rounded, color: Color(0xFF00113A)),
                          ),
                          const SizedBox(width: 16),
                          const Text(
                            'Select Demographic',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF001F2A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedSchoolCode,
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF757682)),
                        decoration: InputDecoration(
                          labelText: 'School Location',
                          labelStyle: const TextStyle(color: Color(0xFF757682)),
                          prefixIcon: const Icon(Icons.account_balance_rounded, color: Color(0xFF757682)),
                          filled: true,
                          fillColor: const Color(0xFFF4FAFF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFE6F6FF), width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF006D36), width: 2),
                          ),
                        ),
                        items: _schools.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(
                              '${entry.value} (${entry.key})',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF001F2A)),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedSchoolCode = newValue;
                            _userCounts = {};
                          });
                          if (newValue != null) _fetchUserCounts(newValue);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                if (_selectedSchoolCode != null) ...[
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator(color: Color(0xFF00113A)))
                  else if (_userCounts.isNotEmpty)
                    _buildUserCountsCard()
                  else
                    _buildEmptyState(),
                ] else
                  _buildInitialState(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.analytics_rounded, size: 64, color: Color(0xFF00113A)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Select a school to view user demographics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF001F2A)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Total connected campuses: ${_schools.length}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF757682)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.no_accounts_rounded, size: 80, color: Color(0xFFC5C6D2)),
            const SizedBox(height: 24),
            const Text(
              'No demographic data available',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF001F2A)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Location: ${_schools[_selectedSchoolCode]}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF757682)),
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

    return Column(
      children: [
        _buildCountCard(
           'Total Enrolled Users',
           totalUsers.toString(),
           Icons.groups_rounded,
           const Color(0xFF00113A),
           'Combined network of all roles',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
             Expanded(child: _buildRoleCountCard('Administrators', adminCount.toString(), Icons.admin_panel_settings_rounded, const Color(0xFF863489))),
             const SizedBox(width: 16),
             Expanded(child: _buildRoleCountCard('Educators/Teachers', teacherCount.toString(), Icons.assured_workload_rounded, const Color(0xFFD6602F))),
          ],
        ),
        const SizedBox(height: 16),
        _buildRoleCountCard('Students', studentCount.toString(), Icons.face_retouching_natural_rounded, const Color(0xFF006D36)),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
             color: const Color(0xFFFFFFFF),
             borderRadius: BorderRadius.circular(24),
             boxShadow: [
                BoxShadow(
                  color: const Color(0xFF001F2A).withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
             ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               const Text(
                  'Distribution Ratios',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF001F2A)),
               ),
               const SizedBox(height: 24),
               _buildStatItem('Admins', adminCount, totalUsers, const Color(0xFF863489)),
               const SizedBox(height: 12),
               _buildStatItem('Teachers', teacherCount, totalUsers, const Color(0xFFD6602F)),
               const SizedBox(height: 12),
               _buildStatItem('Students', studentCount, totalUsers, const Color(0xFF006D36)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountCard(String title, String count, IconData icon, Color color, String subtitle) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
             color: const Color(0xFF001F2A).withOpacity(0.04),
             blurRadius: 16,
             offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
             padding: const EdgeInsets.all(16),
             decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
             ),
             child: Icon(icon, size: 36, color: color),
          ),
          const SizedBox(height: 16),
          Text(count, style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF001F2A))),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF757682))),
        ],
      ),
    );
  }

  Widget _buildRoleCountCard(String role, String count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
         color: const Color(0xFFFFFFFF),
         borderRadius: BorderRadius.circular(20),
         boxShadow: [
            BoxShadow(
               color: const Color(0xFF001F2A).withOpacity(0.04),
               blurRadius: 16,
               offset: const Offset(0, 4),
            )
         ],
      ),
      child: Row(
        children: [
           Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, size: 28, color: color),
           ),
           const SizedBox(width: 16),
           Expanded(
              child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Text(role, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF757682))),
                    const SizedBox(height: 4),
                    Text(count, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color)),
                 ],
              ),
           ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String role, int count, int total, Color color) {
    final percentage = total > 0 ? (count / total * 100) : 0;
    return Row(
       children: [
          SizedBox(
             width: 80,
             child: Text(role, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF001F2A))),
          ),
          const SizedBox(width: 16),
          Expanded(
             child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                   value: total > 0 ? count / total : 0,
                   backgroundColor: const Color(0xFFF4FAFF),
                   valueColor: AlwaysStoppedAnimation<Color>(color),
                   minHeight: 12,
                ),
             ),
          ),
          const SizedBox(width: 16),
          SizedBox(
             width: 60,
             child: Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(fontWeight: FontWeight.w900, color: color),
                textAlign: TextAlign.right,
             ),
          ),
       ],
    );
  }
}
