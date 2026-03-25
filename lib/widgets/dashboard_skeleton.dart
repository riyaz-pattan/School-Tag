import 'package:flutter/material.dart';

class DashboardSkeleton extends StatefulWidget {
  const DashboardSkeleton({super.key});

  @override
  State<DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F4F6),
      child: SafeArea(
        child: FadeTransition(
          opacity: _animation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top header profile section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSkeletonBox(width: 150, height: 28, borderRadius: 8),
                        const SizedBox(height: 8),
                        _buildSkeletonBox(width: 200, height: 16, borderRadius: 4),
                      ],
                    ),
                    _buildSkeletonBox(width: 50, height: 50, borderRadius: 25),
                  ],
                ),
                const SizedBox(height: 32),
                
                // Welcome / Main Info card
                _buildSkeletonBox(
                  width: double.infinity,
                  height: 140,
                  borderRadius: 16,
                ),
                const SizedBox(height: 32),

                // Grid view items
                _buildSkeletonBox(width: 120, height: 24, borderRadius: 6),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: MediaQuery.of(context).size.width > 600 ? 1.4 : 1.1,
                  ),
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    return _buildSkeletonBox(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: 16,
                    );
                  },
                ),
                const SizedBox(height: 32),
                
                // Content lists section
                _buildSkeletonBox(width: 150, height: 24, borderRadius: 6),
                const SizedBox(height: 16),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 3,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSkeletonBox(
                        width: double.infinity,
                        height: 90,
                        borderRadius: 12,
                      ),
                    );
                  },
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonBox({
    required double width,
    required double height,
    required double borderRadius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
