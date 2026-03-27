// fee_models.dart
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Installment (sub-object inside FeeStructure) ───────────────────────────

class Installment {
  final String id;
  final String label;
  final double amount;
  final DateTime dueDate;

  Installment({
    required this.id,
    required this.label,
    required this.amount,
    required this.dueDate,
  });

  factory Installment.fromMap(Map<String, dynamic> map) {
    return Installment(
      id: map['id'] ?? '',
      label: map['label'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      dueDate: map['dueDate'] is Timestamp
          ? (map['dueDate'] as Timestamp).toDate()
          : DateTime.tryParse(map['dueDate']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'amount': amount,
      'dueDate': Timestamp.fromDate(dueDate),
    };
  }

  Installment copyWith({
    String? id,
    String? label,
    double? amount,
    DateTime? dueDate,
  }) {
    return Installment(
      id: id ?? this.id,
      label: label ?? this.label,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
    );
  }
}

// ─── Fee Structure (Admin-created template) ─────────────────────────────────

class FeeStructure {
  final String id;
  final String title;
  final String schoolCode;
  final List<String> applicableClasses;
  final double totalAmount;
  final String academicYear;
  final List<Installment> installments;
  final String createdBy;
  final DateTime createdAt;
  final String status; // "draft" | "published"

  FeeStructure({
    required this.id,
    required this.title,
    required this.schoolCode,
    required this.applicableClasses,
    required this.totalAmount,
    required this.academicYear,
    required this.installments,
    required this.createdBy,
    required this.createdAt,
    required this.status,
  });

  factory FeeStructure.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FeeStructure(
      id: doc.id,
      title: data['title'] ?? '',
      schoolCode: data['schoolCode'] ?? '',
      applicableClasses: List<String>.from(data['applicableClasses'] ?? []),
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      academicYear: data['academicYear'] ?? '',
      installments: (data['installments'] as List<dynamic>?)
              ?.map((e) => Installment.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      createdBy: data['createdBy'] ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      status: data['status'] ?? 'draft',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'schoolCode': schoolCode,
      'applicableClasses': applicableClasses,
      'totalAmount': totalAmount,
      'academicYear': academicYear,
      'installments': installments.map((e) => e.toMap()).toList(),
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status,
    };
  }

  bool get isDraft => status == 'draft';
  bool get isPublished => status == 'published';
}

// ─── Student Due (one per student per installment) ──────────────────────────

class StudentDue {
  final String id;
  final String studentId;
  final String studentName;
  final String className;
  final String structureId;
  final String installmentId;
  final String installmentLabel;
  final double amount;
  final DateTime dueDate;
  final String status; // "pending" | "paid" | "overdue" | "refund_initiated" | "refunded" | "waived"
  final DateTime? paidAt;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String? receiptUrl;
  final String? note;
  final DateTime createdAt;
  final String schoolCode;

  StudentDue({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.structureId,
    required this.installmentId,
    required this.installmentLabel,
    required this.amount,
    required this.dueDate,
    required this.status,
    this.paidAt,
    this.razorpayOrderId,
    this.razorpayPaymentId,
    this.receiptUrl,
    this.note,
    required this.createdAt,
    required this.schoolCode,
  });

  factory StudentDue.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return StudentDue(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      className: data['className'] ?? '',
      structureId: data['structureId'] ?? '',
      installmentId: data['installmentId'] ?? '',
      installmentLabel: data['installmentLabel'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      dueDate: data['dueDate'] is Timestamp
          ? (data['dueDate'] as Timestamp).toDate()
          : DateTime.now(),
      status: data['status'] ?? 'pending',
      paidAt: data['paidAt'] is Timestamp
          ? (data['paidAt'] as Timestamp).toDate()
          : null,
      razorpayOrderId: data['razorpayOrderId'],
      razorpayPaymentId: data['razorpayPaymentId'],
      receiptUrl: data['receiptUrl'],
      note: data['note'],
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      schoolCode: data['schoolCode'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'studentName': studentName,
      'className': className,
      'structureId': structureId,
      'installmentId': installmentId,
      'installmentLabel': installmentLabel,
      'amount': amount,
      'dueDate': Timestamp.fromDate(dueDate),
      'status': status,
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      'razorpayOrderId': razorpayOrderId,
      'razorpayPaymentId': razorpayPaymentId,
      'receiptUrl': receiptUrl,
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
      'schoolCode': schoolCode,
    };
  }

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isOverdue => status == 'overdue' || (status == 'pending' && dueDate.isBefore(DateTime.now()));
  bool get isRefundInitiated => status == 'refund_initiated';
  bool get isRefunded => status == 'refunded';
  bool get isWaived => status == 'waived';
}

// ─── Fee Transaction (immutable audit log) ──────────────────────────────────

class FeeTransaction {
  final String id;
  final String dueId;
  final String studentId;
  final String studentName;
  final String className;
  final String razorpayOrderId;
  final String? razorpayPaymentId;
  final double amount;
  final String currency;
  final String status; // "created" | "captured" | "failed" | "refund_initiated" | "refunded" | "waived"
  final String? failureReason;
  final String? refundId;
  final String? refundReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String schoolCode;

  FeeTransaction({
    required this.id,
    required this.dueId,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.razorpayOrderId,
    this.razorpayPaymentId,
    required this.amount,
    required this.currency,
    required this.status,
    this.failureReason,
    this.refundId,
    this.refundReason,
    required this.createdAt,
    required this.updatedAt,
    required this.schoolCode,
  });

  factory FeeTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return FeeTransaction(
      id: doc.id,
      dueId: data['dueId'] ?? '',
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      className: data['className'] ?? '',
      razorpayOrderId: data['razorpayOrderId'] ?? '',
      razorpayPaymentId: data['razorpayPaymentId'],
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'INR',
      status: data['status'] ?? 'created',
      failureReason: data['failureReason'],
      refundId: data['refundId'],
      refundReason: data['refundReason'],
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
      schoolCode: data['schoolCode'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dueId': dueId,
      'studentId': studentId,
      'studentName': studentName,
      'className': className,
      'razorpayOrderId': razorpayOrderId,
      'razorpayPaymentId': razorpayPaymentId,
      'amount': amount,
      'currency': currency,
      'status': status,
      'failureReason': failureReason,
      'refundId': refundId,
      'refundReason': refundReason,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'schoolCode': schoolCode,
    };
  }

  bool get isCaptured => status == 'captured';
  bool get isFailed => status == 'failed';
  bool get isRefunded => status == 'refunded';
}
