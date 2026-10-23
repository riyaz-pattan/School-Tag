import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'theme/app_theme.dart';
import 'theme/glass_card.dart';

class SchoolDetailsScreen extends StatelessWidget {
  final String schoolId;

  const SchoolDetailsScreen({super.key, required this.schoolId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Campus Profile', style: AppTheme.lightTheme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.onSurface),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -150,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppTheme.primary.withOpacity(0.08), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppTheme.secondary.withOpacity(0.08), Colors.transparent],
                ),
              ),
            ),
          ),
          
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              }

              if (!snapshot.hasData || !snapshot.data!.exists) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: AppTheme.surfaceContainerHighest, shape: BoxShape.circle),
                        child: const Icon(Icons.domain_disabled_rounded, size: 64, color: AppTheme.outline),
                      ),
                      const SizedBox(height: 24),
                      Text('Campus Not Found', style: AppTheme.lightTheme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('The campus record may have been deleted.', style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(color: AppTheme.onSurfaceVariant)),
                    ],
                  ),
                );
              }

              final school = snapshot.data!.data() as Map<String, dynamic>;
              
              String formattedDate = 'N/A';
              if (school['last_updated'] != null) {
                formattedDate = DateFormat('MMM d, yyyy • h:mm a').format((school['last_updated'] as Timestamp).toDate());
              }

              final isActive = school['status'] == 'active';

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hero Header
                        GlassCard(
                          padding: const EdgeInsets.all(32),
                          child: Row(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.signatureGradient,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: AppTheme.ambientShadow,
                                ),
                                child: const Icon(Icons.school_rounded, color: AppTheme.onPrimary, size: 40),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      school['name'] ?? 'Unknown Campus',
                                      style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isActive ? AppTheme.secondary.withOpacity(0.1) : AppTheme.error.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: isActive ? AppTheme.secondary : AppTheme.error,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            (school['status'] ?? 'Unknown').toString().toUpperCase(),
                                            style: AppTheme.lightTheme.textTheme.labelMedium?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: isActive ? AppTheme.secondary : AppTheme.error,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Details Grid
                        Text(
                          'Campus Information',
                          style: AppTheme.lightTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 16),
                        
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isDesktop = constraints.maxWidth > 600;
                            return Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                SizedBox(
                                  width: isDesktop ? (constraints.maxWidth - 16) / 2 : double.infinity,
                                  child: _buildInfoCard('Campus ID', schoolId, Icons.badge_rounded, AppTheme.primary),
                                ),
                                SizedBox(
                                  width: isDesktop ? (constraints.maxWidth - 16) / 2 : double.infinity,
                                  child: _buildInfoCard('Admin Username', school['admin_username'] ?? 'N/A', Icons.admin_panel_settings_rounded, AppTheme.onTertiaryContainer),
                                ),
                                SizedBox(
                                  width: double.infinity,
                                  child: _buildInfoCard('Last Sync', formattedDate, Icons.update_rounded, AppTheme.outline),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon, Color iconColor) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.lightTheme.textTheme.labelMedium?.copyWith(color: AppTheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
