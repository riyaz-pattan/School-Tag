import 'package:cloud_firestore/cloud_firestore.dart';

class QuizAssignment {
  final String id;
  final String title;
  final String description;
  final String assignmentType; // 'file', 'text', 'quiz'
  final String
  questionType; // 'multiple_choice', 'fill_blank', 'match_following', 'mixed'
  final List<Question> questions;
  final int totalMarks;
  final DateTime dueDate;
  final String teacherId;
  final String teacherName;
  final String classId;
  final String grade;
  final String? section;
  final DateTime createdAt;

  QuizAssignment({
    required this.id,
    required this.title,
    required this.description,
    required this.assignmentType,
    required this.questionType,
    required this.questions,
    required this.totalMarks,
    required this.dueDate,
    required this.teacherId,
    required this.teacherName,
    required this.classId,
    required this.grade,
    this.section,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'assignment_type': assignmentType,
      'question_type': questionType,
      'questions': questions.map((q) => q.toMap()).toList(),
      'total_marks': totalMarks,
      'due_date': Timestamp.fromDate(dueDate),
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'class_id': classId,
      'grade': grade,
      'section': section,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }

  static QuizAssignment fromMap(Map<String, dynamic> map) {
    return QuizAssignment(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      assignmentType: map['assignment_type'] ?? 'quiz',
      questionType: map['question_type'] ?? 'multiple_choice',
      questions:
          (map['questions'] as List<dynamic>?)
              ?.map((q) => Question.fromMap(q))
              .toList() ??
          [],
      totalMarks: map['total_marks'] ?? 0,
      dueDate: (map['due_date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      teacherId: map['teacher_id'] ?? '',
      teacherName: map['teacher_name'] ?? '',
      classId: map['class_id'] ?? '',
      grade: map['grade'] ?? '',
      section: map['section'],
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

abstract class Question {
  final String id;
  final String type;
  final String questionText;
  final int marks;

  Question({
    required this.id,
    required this.type,
    required this.questionText,
    required this.marks,
  });

  Map<String, dynamic> toMap();

  static Question fromMap(Map<String, dynamic> map) {
    final type = map['type'] ?? 'multiple_choice';

    switch (type) {
      case 'multiple_choice':
        return MultipleChoiceQuestion.fromMap(map);
      case 'fill_blank':
        return FillBlankQuestion.fromMap(map);
      case 'match_following':
        return MatchFollowingQuestion.fromMap(map);
      case 'true_false':
        return TrueFalseQuestion.fromMap(map);
      case 'ordering':
        return OrderingQuestion.fromMap(map);
      default:
        return MultipleChoiceQuestion.fromMap(map);
    }
  }
}

class MultipleChoiceQuestion extends Question {
  final List<String> options;
  final int correctAnswerIndex;

  MultipleChoiceQuestion({
    required String id,
    required String questionText,
    required int marks,
    required this.options,
    required this.correctAnswerIndex,
  }) : super(
         id: id,
         type: 'multiple_choice',
         questionText: questionText,
         marks: marks,
       );

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'question_text': questionText,
      'marks': marks,
      'options': options,
      'correct_answer_index': correctAnswerIndex,
    };
  }

  static MultipleChoiceQuestion fromMap(Map<String, dynamic> map) {
    return MultipleChoiceQuestion(
      id: map['id'] ?? '',
      questionText: map['question_text'] ?? '',
      marks: map['marks'] ?? 1,
      options: List<String>.from(map['options'] ?? []),
      correctAnswerIndex: map['correct_answer_index'] ?? 0,
    );
  }
}

class FillBlankQuestion extends Question {
  final String correctAnswer;

  FillBlankQuestion({
    required String id,
    required String questionText,
    required int marks,
    required this.correctAnswer,
  }) : super(
         id: id,
         type: 'fill_blank',
         questionText: questionText,
         marks: marks,
       );

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'question_text': questionText,
      'marks': marks,
      'correct_answer': correctAnswer,
    };
  }

  static FillBlankQuestion fromMap(Map<String, dynamic> map) {
    return FillBlankQuestion(
      id: map['id'] ?? '',
      questionText: map['question_text'] ?? '',
      marks: map['marks'] ?? 1,
      correctAnswer: map['correct_answer'] ?? '',
    );
  }
}

class MatchFollowingQuestion extends Question {
  final List<MatchPair> pairs;

  MatchFollowingQuestion({
    required String id,
    required String questionText,
    required int marks,
    required this.pairs,
  }) : super(
         id: id,
         type: 'match_following',
         questionText: questionText,
         marks: marks,
       );

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'question_text': questionText,
      'marks': marks,
      'pairs': pairs.map((p) => p.toMap()).toList(),
    };
  }

  static MatchFollowingQuestion fromMap(Map<String, dynamic> map) {
    return MatchFollowingQuestion(
      id: map['id'] ?? '',
      questionText: map['question_text'] ?? '',
      marks: map['marks'] ?? 1,
      pairs:
          (map['pairs'] as List<dynamic>?)
              ?.map((p) => MatchPair.fromMap(p))
              .toList() ??
          [],
    );
  }
}

class TrueFalseQuestion extends Question {
  final bool correctAnswer;

  TrueFalseQuestion({
    required String id,
    required String questionText,
    required int marks,
    required this.correctAnswer,
  }) : super(
         id: id,
         type: 'true_false',
         questionText: questionText,
         marks: marks,
       );

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'question_text': questionText,
      'marks': marks,
      'correct_answer': correctAnswer,
    };
  }

  static TrueFalseQuestion fromMap(Map<String, dynamic> map) {
    return TrueFalseQuestion(
      id: map['id'] ?? '',
      questionText: map['question_text'] ?? '',
      marks: map['marks'] ?? 1,
      correctAnswer: map['correct_answer'] ?? true,
    );
  }
}

class OrderingQuestion extends Question {
  final List<String> correctOrder;

  OrderingQuestion({
    required String id,
    required String questionText,
    required int marks,
    required this.correctOrder,
  }) : super(
         id: id,
         type: 'ordering',
         questionText: questionText,
         marks: marks, // Usually marks = number of items to order or just 1 big point
       );

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'question_text': questionText,
      'marks': marks,
      'correct_order': correctOrder,
    };
  }

  static OrderingQuestion fromMap(Map<String, dynamic> map) {
    return OrderingQuestion(
      id: map['id'] ?? '',
      questionText: map['question_text'] ?? '',
      marks: map['marks'] ?? 1,
      correctOrder: List<String>.from(map['correct_order'] ?? []),
    );
  }
}

class MatchPair {
  final String left;
  final String right;

  MatchPair({required this.left, required this.right});

  Map<String, dynamic> toMap() {
    return {'left': left, 'right': right};
  }

  static MatchPair fromMap(Map<String, dynamic> map) {
    return MatchPair(left: map['left'] ?? '', right: map['right'] ?? '');
  }
}

class StudentQuizSubmission {
  final String studentId;
  final String studentName;
  final Map<String, dynamic> answers;
  final int autoGrade;
  final int? teacherGrade;
  final String? teacherComments;
  final DateTime submittedAt;

  StudentQuizSubmission({
    required this.studentId,
    required this.studentName,
    required this.answers,
    required this.autoGrade,
    this.teacherGrade,
    this.teacherComments,
    required this.submittedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'student_id': studentId,
      'student_name': studentName,
      'answers': answers,
      'auto_grade': autoGrade,
      'teacher_grade': teacherGrade,
      'teacher_comments': teacherComments,
      'submitted_at': Timestamp.fromDate(submittedAt),
    };
  }

  static StudentQuizSubmission fromMap(Map<String, dynamic> map) {
    return StudentQuizSubmission(
      studentId: map['student_id'] ?? '',
      studentName: map['student_name'] ?? '',
      answers: Map<String, dynamic>.from(map['answers'] ?? {}),
      autoGrade: map['auto_grade'] ?? 0,
      teacherGrade: map['teacher_grade'],
      teacherComments: map['teacher_comments'],
      submittedAt:
          (map['submitted_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  int get finalGrade => teacherGrade ?? autoGrade;
}
