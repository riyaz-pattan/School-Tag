import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme/app_theme.dart';
import 'theme/glass_card.dart';
import 'dart:ui';

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
            const Icon(Icons.error_outline_rounded, color: AppTheme.onPrimary),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: AppTheme.error,
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
      backgroundColor: AppTheme.surface,
      body: Stack(
        children: [
          // Background Gradient
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.onTertiaryContainer.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                _buildModernHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isDesktop ? 32 : 16),
                    physics: const BouncingScrollPhysics(),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSelectorSection(),
                            const SizedBox(height: 32),
                            if (_selectedSchoolCode != null) ...[
                              if (_isLoading)
                                const Center(child: Padding(
                                  padding: EdgeInsets.all(40.0),
                                  child: CircularProgressIndicator(color: AppTheme.primary),
                                ))
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Text(
            'User Analytics',
            style: AppTheme.lightTheme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorSection() {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.apartment_rounded, color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Demographic',
                      style: AppTheme.lightTheme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Choose a school to view analytics',
                      style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: _selectedSchoolCode,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.onSurfaceVariant),
            dropdownColor: AppTheme.surfaceContainerLowest,
            decoration: InputDecoration(
              labelText: 'School Location',
              labelStyle: const TextStyle(color: AppTheme.onSurfaceVariant),
              prefixIcon: const Icon(Icons.location_on_rounded, color: AppTheme.onSurfaceVariant),
              filled: true,
              fillColor: AppTheme.surfaceContainerLowest.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.secondary, width: 2),
              ),
            ),
            items: _schools.entries.map((entry) {
              return DropdownMenuItem<String>(
                value: entry.key,
                child: Text(
                  '${entry.value} (${entry.key})',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.onSurface),
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
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainer.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.analytics_rounded, size: 80, color: AppTheme.primary),
            ),
            const SizedBox(height: 32),
            Text(
              'Select a school to view\nuser demographics',
              style: AppTheme.lightTheme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Total connected campuses: ${_schools.length}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            const Icon(Icons.no_accounts_rounded, size: 80, color: AppTheme.outlineVariant),
            const SizedBox(height: 24),
            Text(
              'No demographic data available',
              style: AppTheme.lightTheme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Location: ${_schools[_selectedSchoolCode]}',
              style: const TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant),
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
           AppTheme.primary,
           'Combined network of all roles',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
             Expanded(child: _buildRoleCountCard('Administrators', adminCount.toString(), Icons.admin_panel_settings_rounded, const Color(0xFF863489))),
             const SizedBox(width: 16),
             Expanded(child: _buildRoleCountCard('Educators/Teachers', teacherCount.toString(), Icons.school_rounded, const Color(0xFFD6602F))),
          ],
        ),
        const SizedBox(height: 16),
        _buildRoleCountCard('Students', studentCount.toString(), Icons.face_retouching_natural_rounded, AppTheme.secondary),
        const SizedBox(height: 32),
        GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Row(
                 children: [
                   Container(
                     padding: const EdgeInsets.all(8),
                     decoration: BoxDecoration(
                       color: AppTheme.onTertiaryContainer.withOpacity(0.1),
                       borderRadius: BorderRadius.circular(8),
                     ),
                     child: const Icon(Icons.pie_chart_rounded, color: AppTheme.onTertiaryContainer),
                   ),
                   const SizedBox(width: 12),
                   Text(
                      'Distribution Ratios',
                      style: AppTheme.lightTheme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                   ),
                 ],
               ),
               const SizedBox(height: 32),
               _buildStatItem('Admins', adminCount, totalUsers, const Color(0xFF863489)),
               const SizedBox(height: 20),
               _buildStatItem('Teachers', teacherCount, totalUsers, const Color(0xFFD6602F)),
               const SizedBox(height: 20),
               _buildStatItem('Students', studentCount, totalUsers, AppTheme.secondary),
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
        gradient: AppTheme.signatureGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.ambientShadow,
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                 padding: const EdgeInsets.all(16),
                 decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                 ),
                 child: Icon(icon, size: 36, color: AppTheme.onPrimary),
              ),
              const Icon(Icons.trending_up_rounded, color: Colors.white54, size: 32),
            ],
          ),
          const SizedBox(height: 24),
          Text(count, style: AppTheme.lightTheme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: AppTheme.onPrimary,
          )),
          const SizedBox(height: 4),
          Text(title, style: AppTheme.lightTheme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppTheme.onPrimary,
          )),
          const SizedBox(height: 8),
          Text(subtitle, style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
          )),
        ],
      ),
    );
  }

  Widget _buildRoleCountCard(String role, String count, IconData icon, Color color) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
           Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16)
              ),
              child: Icon(icon, size: 28, color: color),
           ),
           const SizedBox(width: 16),
           Expanded(
              child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Text(role, style: AppTheme.lightTheme.textTheme.labelMedium?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    )),
                    const SizedBox(height: 4),
                    Text(count, style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.onSurface,
                    )),
                 ],
              ),
           ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String role, int count, int total, Color color) {
    final percentage = total > 0 ? (count / total * 100) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(role, style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            )),
            Text(
               '${percentage.toStringAsFixed(1)}%',
               style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
                 fontWeight: FontWeight.w900,
                 color: color,
               ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
           borderRadius: BorderRadius.circular(8),
           child: LinearProgressIndicator(
              value: total > 0 ? count / total : 0,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 12,
           ),
        ),
      ],
    );
  }
}
