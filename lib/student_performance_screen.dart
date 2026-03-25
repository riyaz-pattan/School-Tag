import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'student_dashboard_screen.dart';

class StudentPerformanceScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String studentId;
  final String studentName;
  final int currentLevel;

  const StudentPerformanceScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.studentId,
    required this.studentName,
    required this.currentLevel,
  });

  @override
  State<StudentPerformanceScreen> createState() =>
      _StudentPerformanceScreenState();
}

class _StudentPerformanceScreenState extends State<StudentPerformanceScreen> {
  List<Map<String, dynamic>> _allGrades = [];
  List<Map<String, dynamic>> _exams = [];
  Map<String, List<Map<String, dynamic>>> _subjectPerformance = {};
  List<Map<String, dynamic>> _examPerformance = [];
  bool _isLoading = true;
  String? _selectedExamId;
  int _selectedTabIndex = 0;
  String? _errorMessage;
  bool _isRefreshing = false;

  // Cache management
  final Map<String, dynamic> _cache = {};
  late SharedPreferences _prefs;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadPerformanceData();
  }

  Future<void> _loadPerformanceData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load all grades
      final gradesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('grades')
          .where('student_id', isEqualTo: widget.studentId)
          .get();

      _allGrades = gradesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {...data, 'id': doc.id};
      }).toList();

      // Get unique exam IDs
      final examIds = _allGrades.map((g) => g['exam_id']).toSet().toList();

      // Load exam details for these exams
      _exams.clear();
      for (var examId in examIds) {
        try {
          final examDoc = await FirebaseFirestore.instance
              .collection('schools')
              .doc(widget.schoolCode)
              .collection('exams')
              .doc(examId)
              .get();

          if (examDoc.exists) {
            // Check for duplicates before adding
            if (!_exams.any((exam) => exam['id'] == examId)) {
              _exams.add({...examDoc.data()!, 'id': examId});
            }
          }
        } catch (e) {
          print('Error loading exam $examId: $e');
        }
      }

      // Sort exams by name for consistency
      _exams.sort(
        (a, b) => (a['exam_name'] ?? '').compareTo(b['exam_name'] ?? ''),
      );

      // Calculate performance data
      _calculatePerformanceData();

      // Set selected exam - fix for dropdown issue
      if (_exams.isNotEmpty) {
        // Check if current selected exam exists in the list
        if (_selectedExamId == null ||
            !_exams.any((exam) => exam['id'] == _selectedExamId)) {
          _selectedExamId = _exams.first['id'];
        }
      } else {
        _selectedExamId = null;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading performance data: $e');
      setState(() {
        _errorMessage = 'Failed to load performance data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _calculatePerformanceData() {
    // Reset data
    _subjectPerformance.clear();
    _examPerformance.clear();

    // Group grades by subject
    final Map<String, List<Map<String, dynamic>>> subjectData = {};

    for (var grade in _allGrades) {
      final subjectId = grade['subject_id'];
      final subjectName = grade['subject_name'];
      final examId = grade['exam_id'];

      // Find exam details
      final exam = _exams.firstWhere(
        (e) => e['id'] == examId,
        orElse: () => {},
      );

      final examName = exam['exam_name'] ?? 'Unknown Exam';

      if (!subjectData.containsKey(subjectId)) {
        subjectData[subjectId] = [];
      }

      final marksObtained = grade['marks_obtained'] as int? ?? 0;
      final maxMarks = grade['max_marks'] as int? ?? 100;
      final isAbsent = grade['is_absent'] == true;

      // For performance calculation, include all graded subjects
      if (maxMarks > 0) {
        final percentage = (marksObtained / maxMarks) * 100;
        final level = _calculateLevelFromPercentage(percentage);

        subjectData[subjectId]!.add({
          'subject_id': subjectId,
          'subject_name': subjectName,
          'exam_id': examId,
          'exam_name': examName,
          'marks_obtained': marksObtained,
          'max_marks': maxMarks,
          'percentage': percentage,
          'level': level,
          'is_absent': isAbsent,
          'date': grade['created_at'] ?? DateTime.now(),
        });
      }
    }

    _subjectPerformance = subjectData;

    // Calculate exam-wise performance
    final Map<String, Map<String, dynamic>> examData = {};

    for (var grade in _allGrades) {
      final examId = grade['exam_id'];
      final marksObtained = grade['marks_obtained'] as int? ?? 0;
      final maxMarks = grade['max_marks'] as int? ?? 100;
      final isAbsent = grade['is_absent'] == true;

      if (!examData.containsKey(examId)) {
        // Find exam details
        final exam = _exams.firstWhere(
          (e) => e['id'] == examId,
          orElse: () => {'exam_name': 'Unknown Exam'},
        );

        examData[examId] = {
          'exam_id': examId,
          'exam_name': exam['exam_name'] ?? 'Unknown Exam',
          'total_marks': 0,
          'max_total_marks': 0,
          'subject_count': 0,
          'graded_subject_count': 0,
        };
      }

      final exam = examData[examId]!;
      exam['subject_count'] = (exam['subject_count'] as int) + 1;

      if (maxMarks > 0) {
        exam['max_total_marks'] = (exam['max_total_marks'] as int) + maxMarks;
        exam['total_marks'] = (exam['total_marks'] as int) + marksObtained;
        exam['graded_subject_count'] =
            (exam['graded_subject_count'] as int) + 1;
      }
    }

    // Calculate average percentage and level for each exam
    _examPerformance = examData.values.map((exam) {
      final totalMarks = exam['total_marks'] as int;
      final maxTotalMarks = exam['max_total_marks'] as int;
      final gradedSubjectCount = exam['graded_subject_count'] as int;

      double averagePercentage = 0;
      if (maxTotalMarks > 0 && gradedSubjectCount > 0) {
        averagePercentage = (totalMarks / maxTotalMarks) * 100;
      }

      final level = _calculateLevelFromPercentage(averagePercentage);

      return {
        ...exam,
        'average_percentage': averagePercentage,
        'level': level,
        'is_complete': gradedSubjectCount == exam['subject_count'],
      };
    }).toList();

    // Sort exams by name
    _examPerformance.sort((a, b) => a['exam_name'].compareTo(b['exam_name']));
  }

  int _calculateLevelFromPercentage(double percentage) {
    if (percentage <= 20) return 1;
    if (percentage <= 30) return 2;
    if (percentage <= 40) return 3;
    if (percentage <= 50) return 4;
    if (percentage <= 60) return 5;
    if (percentage <= 70) return 6;
    if (percentage <= 75) return 7;
    if (percentage <= 80) return 8;
    if (percentage <= 90) return 9;
    return 10;
  }

  Color _getLevelColor(int level) {
    if (level <= 3) return Colors.red[400]!;
    if (level <= 5) return Colors.orange[400]!;
    if (level <= 7) return Colors.yellow[700]!;
    return Colors.green[500]!;
  }

  String _getLevelDescription(int level) {
    switch (level) {
      case 1:
        return 'Beginner - Needs significant improvement';
      case 2:
        return 'Basic - Below average performance';
      case 3:
        return 'Developing - Below expected level';
      case 4:
        return 'Approaching - Slightly below average';
      case 5:
        return 'Average - Meeting minimum expectations';
      case 6:
        return 'Proficient - Meeting expectations';
      case 7:
        return 'Accomplished - Above average performance';
      case 8:
        return 'Advanced - Consistently high performance';
      case 9:
        return 'Excellent - Outstanding performance';
      case 10:
        return 'Master - Exceptional performance';
      default:
        return 'Unknown level';
    }
  }

  // In the _calculateOverallLevel() method, add a fallback:

  int _calculateOverallLevel() {
    if (_allGrades.isEmpty) {
      // Use widget.currentLevel if provided, otherwise calculate from exam performance
      return widget.currentLevel ?? 5;
    }

    // Calculate weighted average from all exams
    double totalWeightedPercentage = 0;
    int totalWeight = 0;

    for (var exam in _examPerformance) {
      final percentage = exam['average_percentage'] as double;
      final subjectCount = exam['graded_subject_count'] as int;

      if (subjectCount > 0) {
        totalWeightedPercentage += percentage * subjectCount;
        totalWeight += subjectCount;
      }
    }

    if (totalWeight == 0) {
      return widget.currentLevel ?? 5;
    }

    final overallPercentage = totalWeightedPercentage / totalWeight;
    return _calculateLevelFromPercentage(overallPercentage);
  }

  Widget _buildLevelCard() {
    final overallLevel = _calculateOverallLevel();
    final distinctExamCount = _exams.length;
    final totalSubjectsGraded = _allGrades.length;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _getLevelColor(overallLevel),
              _getLevelColor(overallLevel).withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.auto_graph, size: 32, color: Colors.white),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Current Level',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                      Text(
                        'LEVEL $overallLevel',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$distinctExamCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Text(
                        'Exams',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: overallLevel / 10,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 12),
            Text(
              _getLevelDescription(overallLevel),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      '$totalSubjectsGraded',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const Text(
                      'Subjects Graded',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '${_subjectPerformance.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const Text(
                      'Unique Subjects',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
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

  Widget _buildExamLevelChart() {
    if (_examPerformance.isEmpty) {
      return _buildEmptyState('No exam data available');
    }

    // Filter only complete exams (all subjects graded)
    final completeExams = _examPerformance
        .where((exam) => exam['is_complete'] == true)
        .toList();

    if (completeExams.isEmpty) {
      return _buildEmptyState('No complete exam data available');
    }

    final spots = completeExams.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value['level'].toDouble());
    }).toList();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.timeline, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Exam-wise Performance',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Your level across different exams (only complete exams shown)',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < completeExams.length) {
                            final exam = completeExams[index];
                            final name = exam['exam_name'];
                            final shortName = name.length > 8
                                ? '${name.substring(0, 8)}...'
                                : name;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                shortName,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                        interval: 1,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              'L${value.toInt()}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                        interval: 1,
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      belowBarData: BarAreaData(show: false),
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.blue,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                    ),
                  ],
                  minY: 1,
                  maxY: 10,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((touchedSpot) {
                          final index = touchedSpot.spotIndex;
                          final exam = completeExams[index];
                          final percentage =
                              exam['average_percentage'] as double;
                          return LineTooltipItem(
                            '${exam['exam_name']}\nLevel: ${exam['level']}\nScore: ${percentage.toStringAsFixed(1)}%',
                            const TextStyle(color: Colors.white),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: completeExams.map((exam) {
                return Chip(
                  label: Text('${exam['exam_name']}: L${exam['level']}'),
                  backgroundColor: _getLevelColor(
                    exam['level'],
                  ).withOpacity(0.1),
                  labelStyle: TextStyle(
                    color: _getLevelColor(exam['level']),
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectPerformance() {
    if (_subjectPerformance.isEmpty) {
      return _buildEmptyState('No subject data available');
    }

    // Get available exams for the dropdown
    final availableExams = _exams.where((exam) {
      return _subjectPerformance.values.any(
        (subjectList) =>
            subjectList.any((grade) => grade['exam_id'] == exam['id']),
      );
    }).toList();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.subject, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Subject-wise Performance',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Your level in different subjects',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 20),

            // Exam selector
            if (availableExams.length > 1)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Exam:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedExamId,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: availableExams.map((exam) {
                        return DropdownMenuItem<String>(
                          value: exam['id'],
                          child: Text(exam['exam_name'] ?? 'Unknown Exam'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedExamId = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),

            // Subject list
            Column(
              children: _subjectPerformance.entries.map((entry) {
                final subjectId = entry.key;
                final subjectData = entry.value;
                final subjectName = subjectData.isNotEmpty
                    ? subjectData.first['subject_name']
                    : 'Unknown';

                // Filter data for selected exam if applicable
                List<Map<String, dynamic>> filteredData;
                if (_selectedExamId != null) {
                  filteredData = subjectData
                      .where((d) => d['exam_id'] == _selectedExamId)
                      .toList();
                } else {
                  filteredData = subjectData;
                }

                if (filteredData.isEmpty) return const SizedBox();

                // Calculate average level for this subject across all exams
                final allSubjectData = subjectData;
                final averageLevel = allSubjectData.isNotEmpty
                    ? (allSubjectData
                                  .map((d) => d['level'] as int)
                                  .reduce((a, b) => a + b) /
                              allSubjectData.length)
                          .round()
                    : 0;

                // Get current exam level if applicable
                final currentExamLevel = filteredData.isNotEmpty
                    ? filteredData.first['level']
                    : averageLevel;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _getLevelColor(
                                currentExamLevel,
                              ).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Center(
                              child: Text(
                                subjectName[0],
                                style: TextStyle(
                                  color: _getLevelColor(currentExamLevel),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subjectName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Level $currentExamLevel',
                                  style: TextStyle(
                                    color: _getLevelColor(currentExamLevel),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _getLevelColor(currentExamLevel),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${filteredData.length} exam${filteredData.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: currentExamLevel / 10,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getLevelColor(currentExamLevel),
                        ),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      if (subjectData.length > 1)
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: subjectData.map((data) {
                            final isSelected =
                                _selectedExamId != null &&
                                data['exam_id'] == _selectedExamId;
                            return Chip(
                              label: Text(
                                '${data['exam_name']}: L${data['level']}',
                              ),
                              backgroundColor: isSelected
                                  ? _getLevelColor(
                                      data['level'],
                                    ).withOpacity(0.2)
                                  : Colors.grey[100],
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? _getLevelColor(data['level'])
                                    : Colors.grey[700],
                                fontSize: 11,
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImprovementSuggestions() {
    // Calculate weak subjects (level <= 5)
    final weakSubjects = _subjectPerformance.entries.where((entry) {
      final subjectData = entry.value;
      if (subjectData.isEmpty) return false;

      // Calculate average level across all exams for this subject
      final averageLevel = subjectData.isNotEmpty
          ? (subjectData.map((d) => d['level'] as int).reduce((a, b) => a + b) /
                    subjectData.length)
                .round()
          : 0;

      return averageLevel <= 5;
    }).toList();

    // Calculate strong subjects (level >= 8)
    final strongSubjects = _subjectPerformance.entries.where((entry) {
      final subjectData = entry.value;
      if (subjectData.isEmpty) return false;

      final averageLevel = subjectData.isNotEmpty
          ? (subjectData.map((d) => d['level'] as int).reduce((a, b) => a + b) /
                    subjectData.length)
                .round()
          : 0;

      return averageLevel >= 8;
    }).toList();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Performance Analysis',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Insights and recommendations for improvement',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 20),

            // Weak Subjects
            if (weakSubjects.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Areas for Improvement:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...weakSubjects.map((entry) {
                    final subjectData = entry.value;
                    final subjectName = subjectData.isNotEmpty
                        ? subjectData.first['subject_name']
                        : 'Unknown';
                    final averageLevel = subjectData.isNotEmpty
                        ? (subjectData
                                      .map((d) => d['level'] as int)
                                      .reduce((a, b) => a + b) /
                                  subjectData.length)
                              .round()
                        : 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.warning,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subjectName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Current Level: $averageLevel',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: Text('Need +${6 - averageLevel} levels'),
                            backgroundColor: Colors.orange[100],
                            labelStyle: const TextStyle(
                              color: Colors.orange,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 16),
                ],
              ),

            // Strong Subjects
            if (strongSubjects.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Strengths:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...strongSubjects.map((entry) {
                    final subjectData = entry.value;
                    final subjectName = subjectData.isNotEmpty
                        ? subjectData.first['subject_name']
                        : 'Unknown';
                    final averageLevel = subjectData.isNotEmpty
                        ? (subjectData
                                      .map((d) => d['level'] as int)
                                      .reduce((a, b) => a + b) /
                                  subjectData.length)
                              .round()
                        : 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.star,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subjectName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Current Level: $averageLevel',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: const Text('Excellent'),
                            backgroundColor: Colors.green[100],
                            labelStyle: const TextStyle(
                              color: Colors.green,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 16),
                ],
              ),

            if (weakSubjects.isEmpty && strongSubjects.isEmpty)
              _buildEmptyState(
                'Complete more exams to get personalized recommendations',
              ),

            // General Tips
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'General Tips:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('• Spend 30 minutes daily on weak subjects'),
                  Text('• Review class notes regularly'),
                  Text('• Practice previous exam papers'),
                  Text('• Ask teachers for clarification'),
                  Text('• Form study groups with classmates'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.auto_graph_outlined, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
    });

    try {
      await _loadPerformanceData();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error refreshing data: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 280,
            color: Colors.white,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.deepOrange[100],
                      child: Icon(
                        Icons.auto_graph,
                        size: 40,
                        color: Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.studentName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.schoolName,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 24),

                    // Navigation tabs
                    Column(
                      children: [
                        _buildSidebarTab('Overall Level', 0),
                        _buildSidebarTab('Exam Progress', 1),
                        _buildSidebarTab('Subjects', 2),
                        _buildSidebarTab('Improvement', 3),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar
                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  color: Colors.white,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.deepOrange,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Performance Analytics',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const Spacer(),
                      if (_isRefreshing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.deepOrange,
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(
                            Icons.refresh,
                            color: Colors.deepOrange,
                          ),
                          onPressed: _refreshData,
                        ),
                    ],
                  ),
                ),

                // Error message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.red[50],
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            setState(() {
                              _errorMessage = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _getCurrentTabContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTab(String title, int index) {
    final isSelected = _selectedTabIndex == index;
    return ListTile(
      leading: Icon(
        _getTabIcon(index),
        color: isSelected ? Colors.deepOrange : Colors.grey,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.deepOrange : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      selected: isSelected,
      onTap: () => setState(() => _selectedTabIndex = index),
    );
  }

  IconData _getTabIcon(int index) {
    switch (index) {
      case 0:
        return Icons.assessment;
      case 1:
        return Icons.timeline;
      case 2:
        return Icons.subject;
      case 3:
        return Icons.lightbulb;
      default:
        return Icons.assessment;
    }
  }

  Widget _getCurrentTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildLevelCard(),
              if (_errorMessage != null) _buildErrorMessage(_errorMessage!),
            ],
          ),
        );
      case 1:
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildExamLevelChart(),
              if (_errorMessage != null) _buildErrorMessage(_errorMessage!),
            ],
          ),
        );
      case 2:
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildSubjectPerformance(),
              if (_errorMessage != null) _buildErrorMessage(_errorMessage!),
            ],
          ),
        );
      case 3:
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildImprovementSuggestions(),
              if (_errorMessage != null) _buildErrorMessage(_errorMessage!),
            ],
          ),
        );
      default:
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildLevelCard(),
              if (_errorMessage != null) _buildErrorMessage(_errorMessage!),
            ],
          ),
        );
    }
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Performance'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          if (_isRefreshing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshData,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Error message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.red[50],
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            setState(() {
                              _errorMessage = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: DefaultTabController(
                    length: 4,
                    child: Column(
                      children: [
                        Container(
                          color: Colors.white,
                          child: TabBar(
                            labelColor: Colors.deepOrange,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: Colors.deepOrange,
                            tabs: const [
                              Tab(text: 'Level', icon: Icon(Icons.assessment)),
                              Tab(text: 'Exams', icon: Icon(Icons.timeline)),
                              Tab(text: 'Subjects', icon: Icon(Icons.subject)),
                              Tab(text: 'Tips', icon: Icon(Icons.lightbulb)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: Column(children: [_buildLevelCard()]),
                              ),
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: _buildExamLevelChart(),
                              ),
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: _buildSubjectPerformance(),
                              ),
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: _buildImprovementSuggestions(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.deepOrange),
              const SizedBox(height: 16),
              const Text('Analyzing your performance...'),
            ],
          ),
        ),
      );
    }

    if (_isDesktop) {
      return _buildDesktopLayout();
    } else {
      return _buildMobileTabletLayout();
    }
  }
}
