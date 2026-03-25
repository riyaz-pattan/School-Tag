import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'quiz_models.dart';
import 'student_assignments_screen.dart';

class StudentQuizScreen extends StatefulWidget {
  final String userId;
  final String schoolName;
  final String assignmentId;
  final String schoolCode;
  final String studentId;
  final String studentName;

  const StudentQuizScreen({
    super.key,
    required this.userId,
    required this.schoolName,
    required this.assignmentId,
    required this.schoolCode,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentQuizScreen> createState() => _StudentQuizScreenState();
}

class _StudentQuizScreenState extends State<StudentQuizScreen> {
  QuizAssignment? _assignment;
  StudentQuizSubmission? _existingSubmission;
  Map<String, dynamic> _answers = {};
  int _currentQuestionIndex = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  // controllers for fill-blank
  final Map<String, TextEditingController> _textControllers = {};

  // shuffled right-side options per match question
  final Map<String, List<String>> _shuffledRightOptions = {};

  final Random _random = Random();

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
    _loadAssignmentAndSubmission();
  }

  @override
  void dispose() {
    _textControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }

  Future<void> _loadAssignmentAndSubmission() async {
    try {
      final assignmentDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .get();

      if (!assignmentDoc.exists) {
        setState(() {
          _errorMessage = 'Assignment not found';
          _isLoading = false;
        });
        return;
      }

      final assignmentData = assignmentDoc.data();
      if (assignmentData == null || assignmentData['deleted'] == true) {
        setState(() {
          _errorMessage = 'Assignment not found or deleted';
          _isLoading = false;
        });
        return;
      }

      _assignment = QuizAssignment.fromMap({
        'id': assignmentDoc.id,
        ...assignmentData,
      });

      // Prepare shuffled options for match questions
      for (var q in _assignment!.questions) {
        if (q is MatchFollowingQuestion) {
          final rightOptions = q.pairs.map((p) => p.right).toList();
          final shuffled = List<String>.from(rightOptions);
          shuffled.shuffle(_random);
          _shuffledRightOptions[q.id] = shuffled;
          _shuffledRightOptions[q.id] = shuffled;
        } else if (q is OrderingQuestion && _answers[q.id] == null) {
          // Initialize ordering questions with shuffled order if not already set
          // (Only if we don't have an existing submission, but here we are just loading assignment first)
           final shuffled = List<String>.from(q.correctOrder)..shuffle(_random);
           _answers[q.id] = shuffled;
        }
      }

      // Load existing submission (if any)
      final submissionDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('submissions')
          .doc(widget.studentId)
          .get();

      if (submissionDoc.exists && submissionDoc.data() != null) {
        _existingSubmission = StudentQuizSubmission.fromMap({
          'id': submissionDoc.id,
          ...submissionDoc.data()!,
        });

        // Normalize existing answers
        final rawAnswers = _existingSubmission!.answers ?? {};

        for (var q in _assignment!.questions) {
          final raw = rawAnswers[q.id];
          if (q is MultipleChoiceQuestion) {
            int? val;
            if (raw is int) val = raw;
            if (raw is String) val = int.tryParse(raw);
            _answers[q.id] = val;
          } else if (q is FillBlankQuestion) {
            final txt = raw?.toString() ?? '';
            _answers[q.id] = txt;
            _textControllers[q.id] = TextEditingController(text: txt);
          } else if (q is MatchFollowingQuestion) {
            final canonical = List<int?>.filled(q.pairs.length, null);

            if (raw is List) {
              for (int i = 0; i < q.pairs.length; i++) {
                final r = i < raw.length ? raw[i] : null;
                final resolved = _resolveRawMatchToCanonicalIndex(q, r);
                canonical[i] = resolved;
              }
            } else if (raw is Map) {
              raw.forEach((k, v) {
                int? leftIndex;
                if (k is int) leftIndex = k;
                if (k is String) {
                  final pk = int.tryParse(k);
                  if (pk != null)
                    leftIndex = pk;
                  else {
                    for (int i = 0; i < q.pairs.length; i++) {
                      if (q.pairs[i].left == k) {
                        leftIndex = i;
                        break;
                      }
                    }
                  }
                }
                if (leftIndex != null &&
                    leftIndex >= 0 &&
                    leftIndex < q.pairs.length) {
                  canonical[leftIndex] = _resolveRawMatchToCanonicalIndex(q, v);
                }
              });
            } else if (raw is String) {
              final split = raw
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (split.length == q.pairs.length) {
                for (int i = 0; i < split.length; i++) {
                  canonical[i] = _resolveRawMatchToCanonicalIndex(q, split[i]);
                }
              } else {
                final resolvedSingle = _resolveRawMatchToCanonicalIndex(q, raw);
                if (resolvedSingle != null) {
                  for (int i = 0; i < q.pairs.length; i++) {
                    if (canonical[i] == null) {
                      canonical[i] = resolvedSingle;
                      break;
                    }
                  }
                }
              }
            }

            _answers[q.id] = canonical;
          }
        }
      } else {
        // No existing submission: initialize controllers
        for (var q in _assignment!.questions) {
          if (q is FillBlankQuestion) {
            _textControllers[q.id] = TextEditingController();
            _answers[q.id] = '';
          } else if (q is MatchFollowingQuestion) {
            _answers[q.id] = List<int?>.filled(q.pairs.length, null);
          } else if (q is MultipleChoiceQuestion) {
            _answers[q.id] = null;
          }
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading quiz: $e';
        _isLoading = false;
      });
    }
  }

  int? _resolveRawMatchToCanonicalIndex(MatchFollowingQuestion q, dynamic raw) {
    if (raw == null) return null;
    if (raw is int) {
      if (raw >= 0 && raw < q.pairs.length) return raw;
      return null;
    }
    if (raw is String) {
      final p = int.tryParse(raw);
      if (p != null && p >= 0 && p < q.pairs.length) return p;
      for (int i = 0; i < q.pairs.length; i++) {
        if (q.pairs[i].right == raw) return i;
      }
    }
    return null;
  }

  Widget _buildMultipleChoiceQuestion(MultipleChoiceQuestion question) {
    final currentAnswer = _answers[question.id] as int?;
    final isSubmitted = _existingSubmission != null;
    final isCorrect =
        isSubmitted && currentAnswer == question.correctAnswerIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _questionHeader(question.questionText, question.marks),
        const SizedBox(height: 12),
        ...question.options.asMap().entries.map((entry) {
          final idx = entry.key;
          final option = entry.value;
          final isSelected = currentAnswer == idx;
          final isRight = idx == question.correctAnswerIndex;

          Color bg = Colors.white;
          if (isSubmitted) {
            if (isSelected && isRight)
              bg = Colors.green.shade50;
            else if (isSelected && !isRight)
              bg = Colors.red.shade50;
            else if (isRight)
              bg = Colors.green.shade50;
          }

          return Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.only(bottom: 8),
            color: bg,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: isSubmitted
                  ? null
                  : () {
                      setState(() {
                        _answers[question.id] = idx;
                      });
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(option, style: const TextStyle(fontSize: 16)),
                    ),
                    if (isSubmitted && isRight)
                      const Icon(Icons.check, color: Colors.green),
                    if (isSubmitted && isSelected && !isRight)
                      const Icon(Icons.close, color: Colors.red),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
        const SizedBox(height: 8),
        Text(
          'Marks: ${isSubmitted ? (isCorrect ? question.marks : 0) : question.marks}',
          style: TextStyle(color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildFillBlankQuestion(FillBlankQuestion question) {
    final controller = _textControllers[question.id]!;
    final isSubmitted = _existingSubmission != null;
    final currentAnswer = _answers[question.id]?.toString() ?? '';
    final isCorrect =
        isSubmitted &&
        currentAnswer.toString().toLowerCase().trim() ==
            question.correctAnswer.toLowerCase().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _questionHeader(question.questionText, question.marks),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          readOnly: isSubmitted,
          onChanged: isSubmitted
              ? null
              : (v) {
                  setState(() {
                    _answers[question.id] = v;
                  });
                },
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: isSubmitted,
            fillColor: isSubmitted
                ? (isCorrect ? Colors.green.shade50 : Colors.red.shade50)
                : null,
            hintText: 'Type your answer...',
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        if (isSubmitted) ...[
          Text(
            'Correct Answer: ${question.correctAnswer}',
            style: const TextStyle(color: Colors.green),
          ),
          const SizedBox(height: 6),
          Text(
            'Marks: ${isCorrect ? question.marks : 0}/${question.marks}',
            style: TextStyle(
              color: isCorrect ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ] else
          Text(
            'Marks: ${question.marks}',
            style: TextStyle(color: Colors.grey[700]),
          ),
      ],
    );
  }

  Widget _buildMatchFollowingQuestion(MatchFollowingQuestion question) {
    _answers.putIfAbsent(
      question.id,
      () => List<int?>.filled(question.pairs.length, null),
    );
    final List<int?> canonicalAnswers = List<int?>.from(
      _answers[question.id] as List<dynamic>,
    );
    final isSubmitted = _existingSubmission != null;

    final shuffled =
        _shuffledRightOptions[question.id] ??
        question.pairs.map((p) => p.right).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _questionHeader(question.questionText, question.marks),
        const SizedBox(height: 12),
        const Text(
          'Match the left item to the correct right item:',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        ...question.pairs.asMap().entries.map((entry) {
          final leftIndex = entry.key;
          final left = entry.value.left;

          final selectedCanonical = canonicalAnswers[leftIndex];
          final displayedSelected =
              (selectedCanonical != null &&
                  selectedCanonical >= 0 &&
                  selectedCanonical < question.pairs.length)
              ? question.pairs[selectedCanonical].right
              : null;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
              color: isSubmitted
                  ? (selectedCanonical != null && selectedCanonical == leftIndex
                        ? Colors.green.shade50
                        : Colors.red.shade50)
                  : Colors.white,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    left,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('→'),
                const SizedBox(width: 12),
                Expanded(
                  child: isSubmitted
                      ? Text(
                          displayedSelected ?? 'Not matched',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color:
                                (selectedCanonical != null &&
                                    selectedCanonical == leftIndex)
                                ? Colors.green
                                : Colors.red,
                          ),
                        )
                      : DropdownButtonFormField<String>(
                          value: displayedSelected,
                          isExpanded: true,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Select'),
                            ),
                            ...shuffled
                                .map(
                                  (s) => DropdownMenuItem<String>(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                          ],
                          onChanged: (sel) {
                            final canonicalIndex = question.pairs.indexWhere(
                              (p) => p.right == sel,
                            );
                            setState(() {
                              (_answers[question.id] as List<int?>)[leftIndex] =
                                  canonicalIndex >= 0 ? canonicalIndex : null;
                            });
                          },
                        ),
                ),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 8),
        Text(
          'Marks: ${isSubmitted ? (_calculateMatchScoreAllOrNothing(question, canonicalAnswers) == question.marks ? question.marks : 0) : question.marks}',
          style: TextStyle(color: Colors.grey[700]),
        ),
      ],
    );
  }

  int _calculateMatchScoreAllOrNothing(
    MatchFollowingQuestion question,
    List<int?> canonicalAnswers,
  ) {
    if (canonicalAnswers.length < question.pairs.length) return 0;
    for (int i = 0; i < question.pairs.length; i++) {
      if (canonicalAnswers[i] == null) return 0;
      if (canonicalAnswers[i] != i) return 0;
    }
    return question.marks;
  }

  Widget _buildTrueFalseQuestion(TrueFalseQuestion question) {
    final currentAnswer = _answers[question.id] as bool?;
    final isSubmitted = _existingSubmission != null;
    final isCorrect = isSubmitted && currentAnswer == question.correctAnswer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _questionHeader(question.questionText, question.marks),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTFButton(
                question,
                true,
                currentAnswer,
                isSubmitted,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTFButton(
                question,
                false,
                currentAnswer,
                isSubmitted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Marks: ${isSubmitted ? (isCorrect ? question.marks : 0) : question.marks}',
          style: TextStyle(color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildTFButton(
    TrueFalseQuestion question,
    bool value,
    bool? currentAnswer,
    bool isSubmitted,
  ) {
    final isSelected = currentAnswer == value;
    final isRight = isSubmitted && question.correctAnswer == value;
    
    Color color = Colors.grey[200]!;
    Color textColor = Colors.black;
    if (isSubmitted) {
        if (isRight) {
            color = Colors.green.shade100;
            textColor = Colors.green.shade900;
        } else if (isSelected && !isRight) {
             color = Colors.red.shade100;
             textColor = Colors.red.shade900;
        }
    } else if (isSelected) {
        color = Colors.deepPurple.shade100;
        textColor = Colors.deepPurple.shade900;
    }

    return InkWell(
      onTap: isSubmitted ? null : () => setState(() => _answers[question.id] = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: isSelected || (isSubmitted && isRight) ? Border.all(color: textColor, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          value ? 'True' : 'False',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderingQuestion(OrderingQuestion question) {
    // If answer not set yet, init with SHUFFLED order (or simply correct order shuffled)
    // IMPORTANT: For a real app, we should store the initial shuffled state so it doesn't reshuffle on every rebuild.
    // For now we will rely on _answers containing the current user order.
    // If _answers is empty, we set it to a shuffled version of correctOrder.
    // Answer is initialized in _loadAssignmentAndSubmission
    
    final currentOrder = List<String>.from(_answers[question.id] ?? question.correctOrder);
    final isSubmitted = _existingSubmission != null;
    
    // Check correctness
    bool isCorrect = false;
    if (isSubmitted) {
         isCorrect = true;
         for(int i=0; i<question.correctOrder.length; i++) {
             if (i >= currentOrder.length || currentOrder[i] != question.correctOrder[i]) {
                 isCorrect = false;
                 break;
             }
         }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _questionHeader(question.questionText, question.marks),
        const SizedBox(height: 8),
        const Text('Drag and drop to arrange in correct order:', style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 12),
        isSubmitted 
          ? Column(
              children: currentOrder.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final correctItem = question.correctOrder[index];
                  final isItemCorrect = item == correctItem;
                  
                  return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: isItemCorrect ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isItemCorrect ? Colors.green : Colors.red),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${index+1}.', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, height: 1.5)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item, 
                                  style: const TextStyle(fontSize: 16, height: 1.5),
                                ),
                              ),
                            ],
                          ),
                          if (!isItemCorrect) ...[
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: Text(
                                  '(Correct: $correctItem)', 
                                  style: const TextStyle(fontSize: 14, color: Colors.green, fontStyle: FontStyle.italic),
                                ),
                              ),
                          ]
                        ],
                      ),
                  );
              }).toList(),
          )
          : ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (int i = 0; i < currentOrder.length; i++)
                  Card(
                    key: ValueKey(currentOrder[i]),
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple[100],
                          child: Text('${i+1}', style: const TextStyle(color: Colors.deepPurple)),
                      ),
                      title: Text(currentOrder[i]),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
              ],
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final String item = currentOrder.removeAt(oldIndex);
                  currentOrder.insert(newIndex, item);
                  _answers[question.id] = currentOrder;
                });
              },
            ),
         const SizedBox(height: 8),
         Text(
          'Marks: ${isSubmitted ? (isCorrect ? question.marks : 0) : question.marks}',
          style: TextStyle(color: Colors.grey[700]),
        ),
      ],
    );
  }

  int _calculateAnsweredCount() {
    if (_assignment == null) return 0;
    int count = 0;
    for (var q in _assignment!.questions) {
        final a = _answers[q.id];
        if (a != null) {
            if (q is FillBlankQuestion && (a as String).trim().isEmpty) continue;
            if (q is MatchFollowingQuestion) {
                 final list = a as List<dynamic>;
                 if (list.every((e) => e == null)) continue;
            }
            count++;
        }
    }
    return count;
  }

  Widget _questionHeader(String text, int marks) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$marks pts',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestion() {
    if (_assignment == null || _assignment!.questions.isEmpty) {
      return const Center(child: Text('No questions available'));
    }

    final question = _assignment!.questions[_currentQuestionIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: (() {
                switch (question.type) {
                  case 'multiple_choice':
                    return _buildMultipleChoiceQuestion(
                      question as MultipleChoiceQuestion,
                    );
                  case 'fill_blank':
                    return _buildFillBlankQuestion(
                      question as FillBlankQuestion,
                    );
                  case 'match_following':
                    return _buildMatchFollowingQuestion(
                      question as MatchFollowingQuestion,
                    );
                  case 'true_false':
                    return _buildTrueFalseQuestion(
                      question as TrueFalseQuestion,
                    );
                  case 'ordering':
                    return _buildOrderingQuestion(
                      question as OrderingQuestion,
                    );
                  default:
                    return const Text('Unknown question type');
                }
              })(),
            ),
          ),
        ),
      ],
    );
  }

  int _calculateAutoGrade() {
    if (_assignment == null) return 0;
    int total = 0;
    for (var q in _assignment!.questions) {
      final answer = _answers[q.id];
      if (q is MultipleChoiceQuestion) {
        if (answer != null && answer == q.correctAnswerIndex) total += q.marks;
      } else if (q is FillBlankQuestion) {
        final ansText = (answer ?? '').toString().toLowerCase().trim();
        if (ansText.isNotEmpty &&
            ansText == q.correctAnswer.toLowerCase().trim())
          total += q.marks;
      } else if (q is MatchFollowingQuestion) {
        final List<dynamic>? raw = answer as List<dynamic>?;
        if (raw != null) {
          bool allCorrect = true;
          if (raw.length < q.pairs.length) allCorrect = false;
          for (int i = 0; i < q.pairs.length; i++) {
            final v = raw[i];
            if (v == null || v is! int || v != i) {
              allCorrect = false;
              break;
            }
          }
          if (allCorrect) total += q.marks;
        }
      } else if (q is TrueFalseQuestion) {
        if (answer == q.correctAnswer) total += q.marks;
      } else if (q is OrderingQuestion) {
        final userOrder = answer as List<String>?;
        if (userOrder != null && userOrder.length == q.correctOrder.length) {
          bool exact = true;
          for (int i = 0; i < q.correctOrder.length; i++) {
            if (userOrder[i] != q.correctOrder[i]) {
              exact = false;
              break;
            }
          }
          if (exact) total += q.marks;
        }
      }
    }
    return total;
  }

  Future<void> _submitQuiz() async {
    if (_existingSubmission != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Quiz already submitted')));
      return;
    }

    // Confirmation Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Quiz?'),
        content: Text(
            'You have answered ${_calculateAnsweredCount()} out of ${_assignment?.questions.length ?? 0} questions.\n\nAre you sure you want to finish?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final submissionAnswers = <String, dynamic>{};

      for (var q in _assignment!.questions) {
        final a = _answers[q.id];
        if (q is MultipleChoiceQuestion) {
          submissionAnswers[q.id] = a;
        } else if (q is FillBlankQuestion) {
          submissionAnswers[q.id] = (a ?? '').toString();
        } else if (q is MatchFollowingQuestion) {
          final List<int?> list = List<int?>.from(
            a as List<dynamic>? ?? List<int?>.filled(q.pairs.length, null),
          );
          submissionAnswers[q.id] = list.map((e) => e).toList();
        } else if (q is TrueFalseQuestion) {
          submissionAnswers[q.id] = a;
        } else if (q is OrderingQuestion) {
          submissionAnswers[q.id] = a; // List<String>
        }
      }

      final autoGrade = _calculateAutoGrade();

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('assignments')
          .doc(widget.assignmentId)
          .collection('submissions')
          .doc(widget.studentId)
          .set({
            'student_id': widget.studentId,
            'student_name': widget.studentName,
            'answers': submissionAnswers,
            'auto_grade': autoGrade,
            'teacher_grade': null,
            'teacher_comments': null,
            'submitted_at': Timestamp.now(),
          });

      await _loadAssignmentAndSubmission();

      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quiz submitted! Auto-grade: $autoGrade/${_assignment!.totalMarks}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Submission failed: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _nextQuestion() {
    if (_assignment == null) return;
    if (_currentQuestionIndex < _assignment!.questions.length - 1) {
      setState(() => _currentQuestionIndex++);
    }
  }

  void _prevQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() => _currentQuestionIndex--);
    }
  }

  // ==================== NEW UI COMPONENTS ====================

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
                      widget.studentName.isNotEmpty
                          ? widget.studentName[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 106, 27, 154),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.studentName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color.fromARGB(255, 106, 27, 154),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Student',
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
    final totalQuestions = _assignment?.questions.length ?? 0;
    final currentGrade =
        _existingSubmission?.finalGrade ?? _calculateAutoGrade();
    final maxGrade = _assignment?.totalMarks ?? 0;
    final submissionStatus = _existingSubmission != null
        ? 'Submitted'
        : 'Not Submitted';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quiz Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 106, 27, 154),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoItem(Icons.quiz, 'Quiz Status', submissionStatus),
          _buildInfoItem(
            Icons.question_answer,
            'Total Questions',
            '$totalQuestions questions',
          ),
          _buildInfoItem(
            Icons.grade,
            'Current Score',
            '$currentGrade/$maxGrade points',
          ),
          _buildInfoItem(
            Icons.timer,
            'Progress',
            'Question ${_currentQuestionIndex + 1}/$totalQuestions',
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
              'Answer all questions carefully. You can navigate between questions using the Previous and Next buttons. Your quiz will be auto-graded upon submission.',
              style: TextStyle(fontSize: 12, color: Colors.purple),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Question Types:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _buildQuizTypeItem(
            '📝',
            'Multiple Choice',
            'Select one correct answer from options',
          ),
          _buildQuizTypeItem(
            '✏️',
            'Fill in Blank',
            'Type your answer in text field',
          ),
          _buildQuizTypeItem(
            '🔗',
            'Match Following',
            'Match items from left to right columns',
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

  Widget _buildQuizTypeItem(String emoji, String title, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
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
                  builder: (context) => StudentAssignmentsScreen(
                    userId: widget.userId,
                    schoolCode: widget.schoolCode,
                    schoolName: widget
                        .schoolName, // You need to pass schoolName if available
                    studentId: widget.studentId,
                    studentName: widget.studentName,
                  ),
                ),
                (route) => false,
              );
            },
            tooltip: 'Back to My Assignments',
          ),
          const SizedBox(width: 16),
          Text(
            _assignment?.title ?? 'Quiz',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 106, 27, 154),
            ),
          ),
          const Spacer(),
          if (_assignment != null)
            Text(
              '${_assignment!.questions.length} questions',
              style: const TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_assignment == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Quiz not found',
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAssignmentAndSubmission,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 24 : 16,
        vertical: _isDesktop ? 20 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quiz Header Card
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
                  Text(
                    _assignment!.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _buildDetailItem(Icons.quiz, 'Quiz Assignment'),
                      _buildDetailItem(
                        Icons.question_answer,
                        '${_assignment!.questions.length} Questions',
                      ),
                      _buildDetailItem(
                        Icons.grade,
                        '${_assignment!.totalMarks} Total Points',
                      ),
                      if (_existingSubmission != null)
                        _buildDetailItem(
                          Icons.assignment_turned_in,
                          'Submitted',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Progress Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  'Q ${_currentQuestionIndex + 1}/${_assignment!.questions.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value:
                        (_currentQuestionIndex + 1) /
                        _assignment!.questions.length,
                    backgroundColor: Colors.grey[300],
                    color: Colors.purple,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                if (_existingSubmission != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Submitted - Grade: ${_existingSubmission!.finalGrade}/${_assignment!.totalMarks}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Answered: ${_calculateAnsweredCount()}/${_assignment!.questions.length}',
                      style: TextStyle(color: Colors.purple[700], fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Question Area
          _buildQuestion(),

          const SizedBox(height: 24),

          // Navigation Buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
              color: Colors.white,
            ),
            child: Row(
              children: [
                if (_currentQuestionIndex > 0)
                  ElevatedButton(
                    onPressed: _prevQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Previous'),
                  ),
                const Spacer(),
                if (_currentQuestionIndex < _assignment!.questions.length - 1)
                  ElevatedButton(
                    onPressed: _nextQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Next'),
                  )
                else if (_existingSubmission == null)
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitQuiz,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Submit Quiz'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple[100]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.purple[700]),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.purple[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTabletLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_assignment?.title ?? 'Quiz'),
        backgroundColor: Colors.purple[700],
        foregroundColor: Colors.white,
      ),
      body: _buildMainContent(),
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
