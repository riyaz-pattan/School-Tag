import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'services/gemini_service.dart';
import 'quiz_models.dart';
import 'teacher_assignments_screen.dart';

class TeacherCreateQuizScreen extends StatefulWidget {
  final String schoolCode;
  final String userId;
  final String schoolName;
  final String teacherId;
  final String teacherName;
  final Map<String, dynamic> selectedClass;

  const TeacherCreateQuizScreen({
    super.key,
    required this.userId,
    required this.schoolName,
    required this.schoolCode,
    required this.teacherId,
    required this.teacherName,
    required this.selectedClass,
  });

  @override
  State<TeacherCreateQuizScreen> createState() =>
      _TeacherCreateQuizScreenState();
}

class _TeacherCreateQuizScreenState extends State<TeacherCreateQuizScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _dueDate;
  String _selectedQuestionType = 'multiple_choice';
  List<Question> _questions = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: _isDesktop ? 300 : 20,
          right: 20,
        ),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: _isDesktop ? 300 : 20,
          right: 20,
        ),
      ),
    );
  }

  void _addQuestion() {
    showDialog(
      context: context,
      builder: (context) => AddQuestionDialog(
        questionType: _selectedQuestionType,
        onQuestionAdded: (question) {
          setState(() {
            _questions.add(question);
          });
        },
      ),
    );
  }

  void _editQuestion(int index) {
    showDialog(
      context: context,
      builder: (context) => AddQuestionDialog(
        questionType: _questions[index].type,
        question: _questions[index],
        onQuestionAdded: (updatedQuestion) {
          setState(() {
            _questions[index] = updatedQuestion;
          });
        },
      ),
    );
  }

  void _deleteQuestion(int index) {
    setState(() {
      _questions.removeAt(index);
    });
  }

  int _calculateTotalMarks() {
    return _questions.fold(0, (sum, question) => sum + question.marks);
  }

  Future<void> _createQuizAssignment() async {
    if (_titleController.text.isEmpty) {
      _showErrorSnackbar('Please enter assignment title');
      return;
    }

    if (_dueDate == null) {
      _showErrorSnackbar('Please select due date');
      return;
    }

    if (_questions.isEmpty) {
      _showErrorSnackbar('Please add at least one question');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get the count of students in this class-section
      Query studentsQuery = FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: 'student')
          .where('class_id', isEqualTo: widget.selectedClass['id']);

      if (widget.selectedClass['section'] != null) {
        studentsQuery = studentsQuery.where(
          'section',
          isEqualTo: widget.selectedClass['section'],
        );
      }

      final studentsSnapshot = await studentsQuery.get();
      final totalStudents = studentsSnapshot.docs.length;

      final assignmentRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc();

      final quiz = QuizAssignment(
        id: assignmentRef.id,
        title: _titleController.text,
        description: _descriptionController.text,
        assignmentType: 'quiz',
        questionType: _selectedQuestionType,
        questions: _questions,
        totalMarks: _calculateTotalMarks(),
        dueDate: _dueDate!,
        teacherId: widget.teacherId,
        teacherName: widget.teacherName,
        classId: widget.selectedClass['id'],
        grade: widget.selectedClass['grade'],
        section: widget.selectedClass['section'],
        createdAt: DateTime.now(),
      );

      await assignmentRef.set({
        ...quiz.toMap(),
        'total_students': totalStudents,
        'submitted_count': 0,
        'deleted': false,
      });

      setState(() {
        _isLoading = false;
      });

      _showSuccessSnackbar('Quiz assignment created successfully!');

      // Clear form
      _titleController.clear();
      _descriptionController.clear();
      _dueDate = null;
      _questions.clear();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Error creating quiz: ${e.toString()}');
    }
  }

  void _showAiGenerationDialog() {
    final topicController = TextEditingController();
    int questionCount = 5;
    String difficulty = 'Medium';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('Generate Quiz with AI'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: topicController,
                    decoration: const InputDecoration(
                      labelText: 'Topic (e.g., Photosynthesis)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Questions: '),
                      Expanded(
                        child: Slider(
                          value: questionCount.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: questionCount.toString(),
                          activeColor: Colors.deepPurple,
                          onChanged: (value) {
                            setState(() {
                              questionCount = value.toInt();
                            });
                          },
                        ),
                      ),
                      Text(questionCount.toString()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: difficulty,
                    decoration: const InputDecoration(
                      labelText: 'Difficulty',
                      border: OutlineInputBorder(),
                    ),
                    items: ['Easy', 'Medium', 'Hard']
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (val) => difficulty = val!,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _generateAiQuestions(
                    topicController.text,
                    questionCount,
                    difficulty,
                  );
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate'),
                style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _generateAiQuestions(
      String topic, int count, String difficulty) async {
    if (topic.isEmpty) {
      _showErrorSnackbar('Please enter a topic');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final generatedData = await GeminiService.generateQuizQuestions(
        topic: topic,
        gradeLevel: widget.selectedClass['grade'] ?? '8',
        difficulty: difficulty,
        count: count,
        type: _selectedQuestionType,
      );

      final List<Question> newQuestions = [];
      
      for (var data in generatedData) {
        final id = DateTime.now().millisecondsSinceEpoch.toString() +
            newQuestions.length.toString();
            
        if (_selectedQuestionType == 'multiple_choice') {
          newQuestions.add(MultipleChoiceQuestion(
            id: id,
            questionText: data['questionText'] ?? 'Question',
            marks: 1,
            options: List<String>.from(data['options'] ?? []),
            correctAnswerIndex: data['correctAnswerIndex'] ?? 0,
          ));
        } else if (_selectedQuestionType == 'fill_blank') {
           newQuestions.add(FillBlankQuestion(
            id: id,
            questionText: data['questionText'] ?? 'Question',
            marks: 1,
            correctAnswer: data['correctAnswer'] ?? '',
          ));
        } else if (_selectedQuestionType == 'match_following') {
          final pairs = (data['pairs'] as List<dynamic>?)
              ?.map((p) => MatchPair(
                    left: p['left'] ?? '',
                    right: p['right'] ?? '',
                  ))
              .toList() ?? [];
              
          newQuestions.add(MatchFollowingQuestion(
            id: id,
            questionText: data['questionText'] ?? 'Match the following',
            marks: pairs.length, // Autoset marks to number of pairs
            pairs: pairs,
          ));
        } else if (_selectedQuestionType == 'true_false') {
          newQuestions.add(TrueFalseQuestion(
            id: id,
            questionText: data['questionText'] ?? 'Question',
            marks: 1,
            correctAnswer: data['correctAnswer'] ?? true,
          ));
        } else if (_selectedQuestionType == 'ordering') {
          newQuestions.add(OrderingQuestion(
            id: id,
            questionText: data['questionText'] ?? 'Arrange safely',
            marks: 1,
            correctOrder: List<String>.from(data['correctOrder'] ?? []),
          ));
        }
      }

      setState(() {
        _questions.addAll(newQuestions);
        _isLoading = false;
      });
      
      _showSuccessSnackbar('Generated ${newQuestions.length} questions successfully!');
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('AI Generation Failed: $e');
    }
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
              Expanded(child: _buildMainContent()),
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
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.purple[100],
                    child: Text(
                      widget.teacherName.isNotEmpty
                          ? widget.teacherName[0].toUpperCase()
                          : 'T',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 106, 27, 154),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.teacherName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromARGB(255, 106, 27, 154),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    widget.schoolCode,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildSidebarInfo()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quiz Creation Guide',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 106, 27, 154),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            Icons.help_outline,
            'Multiple Choice',
            'Create questions with multiple options and one correct answer',
          ),
          _buildInfoItem(
            Icons.short_text,
            'Fill in the Blanks',
            'Students type the correct answer for auto-grading',
          ),
          _buildInfoItem(
            Icons.link,
            'Match Following',
            'Create matching pairs for students to connect',
          ),
          _buildInfoItem(
            Icons.check_circle_outline,
            'True / False',
            'Simple binary choice questions',
          ),
          _buildInfoItem(
            Icons.format_list_numbered,
            'Ordering',
            'Students arrange items in correct sequence',
          ),
          _buildInfoItem(
            Icons.grade,
            'Auto-Grading',
            'Quiz assignments are automatically graded upon submission',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple[100]!),
            ),
            child: const Text(
              'Create engaging quizzes to assess student understanding. All quiz types support auto-grading for efficient evaluation.',
              style: TextStyle(fontSize: 12, color: Colors.purple),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Best Practices:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _buildTipItem('🎯', 'Keep questions clear and concise'),
          _buildTipItem('⏱️', 'Set realistic time limits'),
          _buildTipItem('📊', 'Use a mix of question types'),
          _buildTipItem('🔍', 'Review questions before publishing'),
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
          Icon(icon, size: 20, color: Colors.purple[700]),
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
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
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
              color: Color.fromARGB(255, 106, 27, 154),
            ),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => TeacherAssignmentsScreen(
                    userId: widget.userId,
                    schoolCode: widget.schoolCode,
                    schoolName: widget.schoolName,
                    teacherId: widget.userId,
                    teacherName: widget.userId,
                  ),
                ),
                (route) => false,
              );
            },
            tooltip: 'Back to Dashboard',
          ),
          const Text(
            'Create Quiz Assignment',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 106, 27, 154),
            ),
          ),
          const Spacer(),
          if (widget.selectedClass.isNotEmpty)
            Text(
              'Class: ${widget.selectedClass['displayName'] ?? 'Unknown'}',
              style: const TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 24 : 16,
        vertical: _isDesktop ? 20 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Basic Information
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Basic Information',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Quiz Title *',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Due Date: ', style: TextStyle(fontSize: 16)),
                      Text(
                        _dueDate != null
                            ? DateFormat('MMM dd, yyyy').format(_dueDate!)
                            : 'Not selected',
                        style: TextStyle(
                          fontSize: 16,
                          color: _dueDate != null ? Colors.black : Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (date != null) {
                            setState(() {
                              _dueDate = date;
                            });
                          }
                        },
                        child: const Text('Select Date'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Class: ${widget.selectedClass['displayName'] ?? 'Unknown Class'}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Question Type Selection
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Question Type',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedQuestionType,
                    decoration: const InputDecoration(
                      labelText: 'Select Question Type',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'multiple_choice',
                        child: Text('Multiple Choice Questions'),
                      ),
                      DropdownMenuItem(
                        value: 'fill_blank',
                        child: Text('Fill in the Blanks'),
                      ),
                      DropdownMenuItem(
                        value: 'match_following',
                        child: Text('Match the Following'),
                      ),
                      DropdownMenuItem(
                        value: 'true_false',
                        child: Text('True / False'),
                      ),
                      DropdownMenuItem(
                        value: 'ordering',
                        child: Text('Ordering / Sequencing'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedQuestionType = value!;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Questions List
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Questions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Total Marks: ${_calculateTotalMarks()}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),


                  if (_questions.isEmpty)
                    const Center(
                      child: Column(
                        children: [
                          Icon(Icons.quiz, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No questions added yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._questions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final question = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: Colors.grey[50],
                        child: ListTile(
                          title: Text(
                            'Q${index + 1}: ${question.questionText}',
                          ),
                          subtitle: Text(
                            '${question.type} - ${question.marks} marks',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _editQuestion(index),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _deleteQuestion(index),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 16),
                  
                  // AI Generation Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showAiGenerationDialog,
                      icon: const Icon(Icons.auto_awesome, color: Colors.deepPurple),
                      label: const Text('Generate with AI', style: TextStyle(color: Colors.deepPurple)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.deepPurple),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addQuestion,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Question'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Create Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _createQuizAssignment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Creating Quiz...'),
                      ],
                    )
                  : const Text(
                      'Create Quiz Assignment',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Quiz'),
        backgroundColor: Colors.purple[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildMainContent(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(body: _buildDesktopLayout());
    } else {
      return _buildMobileTabletLayout();
    }
  }
}

/// Add / Edit question dialog
class AddQuestionDialog extends StatefulWidget {
  final String questionType;
  final Question? question;
  final Function(Question) onQuestionAdded;

  const AddQuestionDialog({
    super.key,
    required this.questionType,
    this.question,
    required this.onQuestionAdded,
  });

  @override
  State<AddQuestionDialog> createState() => _AddQuestionDialogState();
}

class _AddQuestionDialogState extends State<AddQuestionDialog> {
  late TextEditingController _questionController;
  late TextEditingController _marksController;
  late List<TextEditingController> _optionControllers =
      <TextEditingController>[];
  late TextEditingController _correctAnswerController;
  late List<TextEditingController> _leftControllers = <TextEditingController>[];
  late List<TextEditingController> _rightControllers =
      <TextEditingController>[];
  int? _correctOptionIndex;
  bool _trueFalseAnswer = true;

  @override
  void initState() {
    super.initState();

    _questionController = TextEditingController(
      text: widget.question?.questionText ?? '',
    );
    _marksController = TextEditingController(
      text: (widget.question?.marks ?? 1).toString(),
    );
    _correctAnswerController = TextEditingController();

    if (widget.questionType == 'multiple_choice') {
      _optionControllers = [];
      if (widget.question is MultipleChoiceQuestion) {
        final mcq = widget.question as MultipleChoiceQuestion;
        for (var option in mcq.options) {
          _optionControllers.add(TextEditingController(text: option));
        }
        _correctOptionIndex = mcq.correctAnswerIndex;
      } else {
        // Add 4 empty options for new question
        for (int i = 0; i < 4; i++) {
          _optionControllers.add(TextEditingController());
        }
      }
    } else {
      // ensure list exists (already done by initialization)
      _optionControllers = _optionControllers;
    }

    if (widget.questionType == 'fill_blank') {
      if (widget.question is FillBlankQuestion) {
        final fbq = widget.question as FillBlankQuestion;
        _correctAnswerController.text = fbq.correctAnswer;
      }
    }

    if (widget.questionType == 'match_following') {
      _leftControllers = [];
      _rightControllers = [];
      if (widget.question is MatchFollowingQuestion) {
        final mfq = widget.question as MatchFollowingQuestion;
        for (var pair in mfq.pairs) {
          _leftControllers.add(TextEditingController(text: pair.left));
          _rightControllers.add(TextEditingController(text: pair.right));
        }
      } else {
        // Add 3 empty pairs for new question
        for (int i = 0; i < 3; i++) {
          _leftControllers.add(TextEditingController());
          _rightControllers.add(TextEditingController());
        }
      }
    } else {
      _leftControllers = _leftControllers;
      _rightControllers = _rightControllers;
    }
    
    if (widget.questionType == 'true_false') {
      if (widget.question is TrueFalseQuestion) {
        _trueFalseAnswer = (widget.question as TrueFalseQuestion).correctAnswer;
      }
    }

    if (widget.questionType == 'ordering') {
       _optionControllers = [];
       if (widget.question is OrderingQuestion) {
         final oq = widget.question as OrderingQuestion;
         for (var item in oq.correctOrder) {
           _optionControllers.add(TextEditingController(text: item));
         }
       } else {
         // Add 4 empty items for new question
         for (int i=0; i<4; i++) {
           _optionControllers.add(TextEditingController());
         }
       }
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    _marksController.dispose();
    _correctAnswerController.dispose();

    // dispose option controllers safely
    for (var controller in _optionControllers) {
      controller.dispose();
    }

    for (var controller in _leftControllers) {
      controller.dispose();
    }
    for (var controller in _rightControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    setState(() {
      _optionControllers.removeAt(index);
      if (_correctOptionIndex == index) {
        _correctOptionIndex = null;
      } else if (_correctOptionIndex != null && _correctOptionIndex! > index) {
        _correctOptionIndex = _correctOptionIndex! - 1;
      }
    });
  }

  void _addMatchPair() {
    setState(() {
      _leftControllers.add(TextEditingController());
      _rightControllers.add(TextEditingController());
    });
  }

  void _removeMatchPair(int index) {
    setState(() {
      _leftControllers.removeAt(index);
      _rightControllers.removeAt(index);
    });
  }

  void _saveQuestion() {
    if (_questionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter question text')),
      );
      return;
    }

    final marks = int.tryParse(_marksController.text) ?? 1;
    if (marks <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter valid marks')));
      return;
    }

    final id =
        widget.question?.id ?? DateTime.now().millisecondsSinceEpoch.toString();

    Question question;

    switch (widget.questionType) {
      case 'multiple_choice':
        final options = _optionControllers
            .map((c) => c.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
        if (options.length < 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please add at least 2 options')),
          );
          return;
        }
        if (_correctOptionIndex == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select correct answer')),
          );
          return;
        }
        question = MultipleChoiceQuestion(
          id: id,
          questionText: _questionController.text.trim(),
          marks: marks,
          options: options,
          correctAnswerIndex: _correctOptionIndex!,
        );
        break;

      case 'fill_blank':
        if (_correctAnswerController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter correct answer')),
          );
          return;
        }
        question = FillBlankQuestion(
          id: id,
          questionText: _questionController.text.trim(),
          marks: marks,
          correctAnswer: _correctAnswerController.text.trim(),
        );
        break;

      case 'match_following':
        final pairs = <MatchPair>[];
        for (int i = 0; i < _leftControllers.length; i++) {
          final leftText = _leftControllers[i].text.trim();
          final rightText = _rightControllers[i].text.trim();
          if (leftText.isNotEmpty && rightText.isNotEmpty) {
            pairs.add(MatchPair(left: leftText, right: rightText));
          }
        }
        if (pairs.length < 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please add at least 2 matching pairs'),
            ),
          );
          return;
        }

        // Check for duplicate left items
        final leftItems = pairs.map((p) => p.left).toList();
        if (leftItems.toSet().length != leftItems.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Left items must be unique')),
          );
          return;
        }

        // Check for duplicate right items
        final rightItems = pairs.map((p) => p.right).toList();
        if (rightItems.toSet().length != rightItems.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Right items must be unique')),
          );
          return;
        }

        question = MatchFollowingQuestion(
          id: id,
          questionText: _questionController.text.trim(),
          marks: marks,
          pairs: pairs,
        );
        break;

      case 'true_false':
        question = TrueFalseQuestion(
          id: id,
          questionText: _questionController.text.trim(),
          marks: marks,
          correctAnswer: _trueFalseAnswer,
        );
        break;

      case 'ordering':
        final items = _optionControllers
            .map((c) => c.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
        if (items.length < 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please add at least 2 items to order')),
          );
          return;
        }
        question = OrderingQuestion(
          id: id,
          questionText: _questionController.text.trim(),
          marks: marks,
          correctOrder: items,
        );
        break;

      default:
        return;
    }

    widget.onQuestionAdded(question);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Add ${widget.questionType.replaceAll('_', ' ').toTitleCase()} Question',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _questionController,
              decoration: const InputDecoration(
                labelText: 'Question Text *',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _marksController,
              decoration: const InputDecoration(
                labelText: 'Marks *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            if (widget.questionType == 'multiple_choice') ...[
              const Text(
                'Options (Select the correct one):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._optionControllers.asMap().entries.map((entry) {
                final index = entry.key;
                final controller = entry.value;
                return Row(
                  children: [
                    Radio<int>(
                      value: index,
                      groupValue: _correctOptionIndex,
                      onChanged: (value) {
                        setState(() {
                          _correctOptionIndex = value;
                        });
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: 'Option ${index + 1}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(
                        icon: const Icon(Icons.remove, color: Colors.red),
                        onPressed: () => _removeOption(index),
                      ),
                  ],
                );
              }).toList(),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: const Text('Add Option'),
              ),
            ],

            if (widget.questionType == 'fill_blank') ...[
              TextField(
                controller: _correctAnswerController,
                decoration: const InputDecoration(
                  labelText: 'Correct Answer *',
                  border: OutlineInputBorder(),
                  helperText: 'This will be used for auto-grading',
                ),
              ),
            ],

            if (widget.questionType == 'match_following') ...[
              const Text(
                'Matching Pairs:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Note: Correct matches are determined by the order of pairs (left→right)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ..._leftControllers.asMap().entries.map((entry) {
                final index = entry.key;
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _leftControllers[index],
                            decoration: InputDecoration(
                              labelText: 'Left ${index + 1}',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _rightControllers[index],
                            decoration: InputDecoration(
                              labelText: 'Right ${index + 1}',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle,
                            color: Colors.red,
                          ),
                          onPressed: _leftControllers.length > 2
                              ? () => _removeMatchPair(index)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              }).toList(),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _addMatchPair,
                icon: const Icon(Icons.add),
                label: const Text('Add Pair'),
              ),
            ],

            if (widget.questionType == 'true_false') ...[
              const Text(
                'Correct Answer:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                   Expanded(
                     child: RadioListTile<bool>(
                       title: const Text('True'),
                       value: true,
                       groupValue: _trueFalseAnswer,
                       onChanged: (val) => setState(() => _trueFalseAnswer = val!),
                     ),
                   ),
                   Expanded(
                     child: RadioListTile<bool>(
                       title: const Text('False'),
                       value: false,
                       groupValue: _trueFalseAnswer,
                       onChanged: (val) => setState(() => _trueFalseAnswer = val!),
                     ),
                   ),
                ],
              ),
            ],

            if (widget.questionType == 'ordering') ...[
              const Text(
                'Correct Order (Top to Bottom):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add items in the correct sequence. Students will have to arrange them.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
               const SizedBox(height: 8),
              ..._optionControllers.asMap().entries.map((entry) {
                final index = entry.key;
                final controller = entry.value;
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.purple[100],
                      child: Text('${index + 1}', style: const TextStyle(fontSize: 12, color: Colors.purple)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: 'Item ${index + 1}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () => _removeOption(index),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveQuestion,
          child: const Text('Save Question'),
        ),
      ],
    );
  }
}

extension StringExtension on String {
  String toTitleCase() {
    return split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }
}
