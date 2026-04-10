// fee_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/fee_models.dart';

class FeeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ─── Fee Structure CRUD ──────────────────────────────────────────────────

  /// Create a new fee structure (admin only, saved as draft)
  static Future<String> createFeeStructure({
    required String schoolCode,
    required String title,
    required String academicYear,
    required List<String> applicableClasses,
    required double totalAmount,
    required List<Installment> installments,
    required String adminId,
  }) async {
    final docRef = _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('fee_structures')
        .doc();

    final structure = FeeStructure(
      id: docRef.id,
      title: title,
      schoolCode: schoolCode,
      applicableClasses: applicableClasses,
      totalAmount: totalAmount,
      academicYear: academicYear,
      installments: installments,
      createdBy: adminId,
      createdAt: DateTime.now(),
      status: 'draft',
    );

    await docRef.set(structure.toMap());
    return docRef.id;
  }

  /// Update an existing draft fee structure
  static Future<void> updateFeeStructure({
    required String schoolCode,
    required String structureId,
    required Map<String, dynamic> updates,
  }) async {
    await _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('fee_structures')
        .doc(structureId)
        .update(updates);
  }

  /// Check if a fee structure has any active payments (not pending or waived)
  static Future<bool> hasPayments({
    required String schoolCode,
    required String structureId,
  }) async {
    final dues = await _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('student_dues')
        .where('structureId', isEqualTo: structureId)
        .get();

    return dues.docs.any((doc) {
      final status = doc.data()['status'] as String? ?? 'pending';
      return status != 'pending' && status != 'waived';
    });
  }

  /// Delete a fee structure (checks for safety lock)
  static Future<void> deleteFeeStructure({
    required String schoolCode,
    required String structureId,
  }) async {
    final hasActivePayments = await hasPayments(
      schoolCode: schoolCode,
      structureId: structureId,
    );

    if (hasActivePayments) {
      throw Exception('Cannot delete a fee structure that has active payments.');
    }

    final batch = _firestore.batch();
    
    // Delete all student dues associated with it
    final dues = await _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('student_dues')
        .where('structureId', isEqualTo: structureId)
        .get();
        
    for (final doc in dues.docs) {
      batch.delete(doc.reference);
    }
    
    // Delete the structure itself
    batch.delete(_firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('fee_structures')
        .doc(structureId));

    await batch.commit();
  }

  /// Stream all fee structures for a school
  static Stream<List<FeeStructure>> streamFeeStructures(String schoolCode) {
    return _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('fee_structures')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FeeStructure.fromFirestore(doc))
            .toList());
  }

  /// Fetch a single fee structure
  static Future<FeeStructure?> getFeeStructure({
    required String schoolCode,
    required String structureId,
  }) async {
    final doc = await _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('fee_structures')
        .doc(structureId)
        .get();
    if (!doc.exists) return null;
    return FeeStructure.fromFirestore(doc);
  }

  // ─── Publishing (generates student dues) ─────────────────────────────────

  /// Publish a fee structure: generates student_due docs for all students
  /// in the applicable classes.
  static Future<void> publishFeeStructure({
    required String schoolCode,
    required String structureId,
  }) async {
    // Fetch the structure
    final structureDoc = await _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('fee_structures')
        .doc(structureId)
        .get();

    if (!structureDoc.exists) throw Exception('Fee structure not found');

    final structure = FeeStructure.fromFirestore(structureDoc);
    // Removed strict isPublished check to allow syncing missing students/dues via re-publish.
    // The duplicate check below handles idempotent generation.

    // Fetch all students in the applicable classes
    final usersSnapshot = await _firestore
        .collection('users')
        .where('school_code', isEqualTo: schoolCode)
        .where('role', isEqualTo: 'student')
        .get();

    final students = usersSnapshot.docs.where((doc) {
      final data = doc.data();
      final classId = data['class_id']?.toString() ?? '';
      final classGrade = data['class_grade']?.toString() ?? '';
      final className = data['class_name']?.toString() ?? '';
      final classShort = data['class']?.toString() ?? '';
      
      return structure.applicableClasses.contains(classId) ||
          structure.applicableClasses.contains(classGrade) ||
          structure.applicableClasses.contains(className) ||
          structure.applicableClasses.contains(classShort) ||
          structure.applicableClasses.contains('ALL');
    }).toList();

    // Batch create student_due docs
    final batch = _firestore.batch();
    int batchCount = 0;
    List<WriteBatch> batches = [batch];

    for (final studentDoc in students) {
      final studentData = studentDoc.data();
      final studentName =
          studentData['full_name'] ?? studentData['username'] ?? 'Unknown';
      final className = studentData['class_id'] ?? 'N/A';

      for (final installment in structure.installments) {
        // Check for existing due to avoid duplicates
        final existingDue = await _firestore
            .collection('schools')
            .doc(schoolCode)
            .collection('student_dues')
            .where('studentId', isEqualTo: studentDoc.id)
            .where('structureId', isEqualTo: structureId)
            .where('installmentId', isEqualTo: installment.id)
            .limit(1)
            .get();

        if (existingDue.docs.isNotEmpty) continue; // skip duplicates

        final dueRef = _firestore
            .collection('schools')
            .doc(schoolCode)
            .collection('student_dues')
            .doc();

        final currentBatch = batches.last;
        currentBatch.set(dueRef, {
          'studentId': studentDoc.id,
          'studentName': studentName,
          'className': className,
          'structureId': structureId,
          'installmentId': installment.id,
          'installmentLabel': installment.label,
          'amount': installment.amount,
          'dueDate': Timestamp.fromDate(installment.dueDate),
          'status': 'pending',
          'paidAt': null,
          'razorpayOrderId': null,
          'razorpayPaymentId': null,
          'receiptUrl': null,
          'note': null,
          'createdAt': FieldValue.serverTimestamp(),
          'schoolCode': schoolCode,
        });

        batchCount++;
        // Firestore batch limit is 500
        if (batchCount % 490 == 0) {
          batches.add(_firestore.batch());
        }
      }
    }

    // Mark structure as published
    batches.last.update(structureDoc.reference, {'status': 'published'});

    // Commit all batches
    for (final b in batches) {
      await b.commit();
    }
  }

  // ─── Student Dues ────────────────────────────────────────────────────────

  /// Stream dues for a specific student (real-time updates)
  static Stream<List<StudentDue>> streamStudentDues({
    required String schoolCode,
    required String studentId,
  }) {
    return _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('student_dues')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
      final list =
          snapshot.docs.map((doc) => StudentDue.fromFirestore(doc)).toList();
      list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
      return list;
    });
  }

  /// Stream a single due (used during payment verification)
  static Stream<StudentDue?> streamSingleDue({
    required String schoolCode,
    required String dueId,
  }) {
    return _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('student_dues')
        .doc(dueId)
        .snapshots()
        .map((doc) => doc.exists ? StudentDue.fromFirestore(doc) : null);
  }

  /// Stream all dues for admin view (with optional filters)
  static Stream<List<StudentDue>> streamAllDues({
    required String schoolCode,
    String? className,
    String? status,
  }) {
    Query query = _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('student_dues');

    if (className != null && className.isNotEmpty) {
      query = query.where('className', isEqualTo: className);
    }
    if (status != null && status.isNotEmpty) {
      query = query.where('status', isEqualTo: status);
    }

    return query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => StudentDue.fromFirestore(doc)).toList());
  }

  /// Admin: Update a student due (discount, waiver, note)
  static Future<void> updateStudentDue({
    required String schoolCode,
    required String dueId,
    required Map<String, dynamic> updates,
  }) async {
    await _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('student_dues')
        .doc(dueId)
        .update(updates);
  }

  /// Admin: Waive a student due
  static Future<void> waiveStudentDue({
    required String schoolCode,
    required String dueId,
    required String reason,
  }) async {
    final batch = _firestore.batch();

    final dueRef = _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('student_dues')
        .doc(dueId);

    batch.update(dueRef, {
      'status': 'waived',
      'note': reason,
    });

    // Also create a transaction record for audit
    final dueDoc = await dueRef.get();
    if (dueDoc.exists) {
      final dueData = dueDoc.data() as Map<String, dynamic>;
      final txnRef = _firestore
          .collection('schools')
          .doc(schoolCode)
          .collection('transactions')
          .doc();

      batch.set(txnRef, {
        'dueId': dueId,
        'studentId': dueData['studentId'],
        'studentName': dueData['studentName'],
        'className': dueData['className'],
        'razorpayOrderId': 'WAIVED',
        'razorpayPaymentId': null,
        'amount': dueData['amount'],
        'currency': 'INR',
        'status': 'waived',
        'failureReason': null,
        'refundId': null,
        'refundReason': reason,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'schoolCode': schoolCode,
      });
    }

    await batch.commit();
  }

  /// Admin: Mark a student due as paid manually (offline payment)
  static Future<void> markAsPaidManually({
    required String schoolCode,
    required String dueId,
    required String paymentMode,
    required String referenceNumber,
    required String adminId,
  }) async {
    final batch = _firestore.batch();
    final dueRef = _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('student_dues')
        .doc(dueId);

    batch.update(dueRef, {
      'status': 'paid',
      'paidAt': FieldValue.serverTimestamp(),
      'razorpayPaymentId': 'MANUAL_OFFLINE',
      'note': 'Paid via $paymentMode (Ref: $referenceNumber) by Admin: $adminId',
    });

    final dueDoc = await dueRef.get();
    if (dueDoc.exists) {
      final dueData = dueDoc.data() as Map<String, dynamic>;
      final txnRef = _firestore
          .collection('schools')
          .doc(schoolCode)
          .collection('transactions')
          .doc();

      batch.set(txnRef, {
        'dueId': dueId,
        'studentId': dueData['studentId'],
        'studentName': dueData['studentName'],
        'className': dueData['className'],
        'razorpayOrderId': 'MANUAL_OFFLINE',
        'razorpayPaymentId': 'MANUAL_OFFLINE',
        'amount': dueData['amount'],
        'currency': 'INR',
        'status': 'paid_offline',
        'failureReason': null,
        'refundId': null,
        'refundReason': 'Mode: $paymentMode, Ref: $referenceNumber',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'schoolCode': schoolCode,
      });
    }

    await batch.commit();
  }

  // ─── Razorpay Order (calls Cloud Function) ───────────────────────────────

  /// Create a Razorpay order for a specific due
  static Future<Map<String, dynamic>> createRazorpayOrder({
    required String schoolCode,
    required String dueId,
    required String studentId,
  }) async {
    try {
      print('🚀 [FeeService] Calling createRazorpayOrder Cloud Function...');
      print('   - schoolCode: $schoolCode');
      print('   - dueId: $dueId');
      print('   - studentId: $studentId');

      final callable = _functions.httpsCallable('createRazorpayOrder');
      final result = await callable.call({
        'schoolCode': schoolCode,
        'dueId': dueId,
        'studentId': studentId,
      });

      print('✅ [FeeService] Order created successfully!');
      print('   - Result: ${result.data}');

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      print('❌ [FeeService] FirebaseFunctionsException:');
      print('   - Code: ${e.code}');
      print('   - Message: ${e.message}');
      print('   - Details: ${e.details}');
      rethrow;
    } catch (e) {
      print('❌ [FeeService] Unexpected error: $e');
      rethrow;
    }
  }

  /// Verify payment after Razorpay checkout success (client-side verification)
  /// NOTE: The webhook is the source of truth. This is supplementary.
  static Future<void> verifyPaymentClientSide({
    required String schoolCode,
    required String dueId,
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
  }) async {
    final callable = _functions.httpsCallable('verifyRazorpayPayment');
    await callable.call({
      'schoolCode': schoolCode,
      'dueId': dueId,
      'razorpayPaymentId': razorpayPaymentId,
      'razorpayOrderId': razorpayOrderId,
      'razorpaySignature': razorpaySignature,
    });
  }

  // ─── Refunds (admin only) ────────────────────────────────────────────────

  /// Initiate a refund for a paid due (admin only)
  static Future<void> initiateRefund({
    required String schoolCode,
    required String dueId,
    required String reason,
  }) async {
    final callable = _functions.httpsCallable('initiateRefund');
    await callable.call({
      'schoolCode': schoolCode,
      'dueId': dueId,
      'reason': reason,
    });
  }

  // ─── Transactions ────────────────────────────────────────────────────────

  /// Stream all transactions for admin view
  static Stream<List<FeeTransaction>> streamTransactions({
    required String schoolCode,
  }) {
    return _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FeeTransaction.fromFirestore(doc))
            .toList());
  }

  /// Fetch transactions for a specific due
  static Future<List<FeeTransaction>> getTransactionsForDue({
    required String schoolCode,
    required String dueId,
  }) async {
    final snapshot = await _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('transactions')
        .where('dueId', isEqualTo: dueId)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => FeeTransaction.fromFirestore(doc))
        .toList();
  }

  // ─── Reports / Aggregation Helpers ────────────────────────────────────────

  /// Get fee summary stats for admin dashboard
  static Future<Map<String, dynamic>> getFeeSummary({
    required String schoolCode,
  }) async {
    final allDues = await _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('student_dues')
        .get();

    double totalExpected = 0;
    double totalCollected = 0;
    double totalOutstanding = 0;
    int totalPaid = 0;
    int totalPending = 0;
    int totalOverdue = 0;

    for (final doc in allDues.docs) {
      final due = StudentDue.fromFirestore(doc);
      if (due.isWaived) continue; // skip waived

      totalExpected += due.amount;

      if (due.isPaid) {
        totalCollected += due.amount;
        totalPaid++;
      } else if (due.isOverdue) {
        totalOutstanding += due.amount;
        totalOverdue++;
      } else if (due.isPending) {
        totalOutstanding += due.amount;
        totalPending++;
      }
    }

    final collectionRate =
        totalExpected > 0 ? (totalCollected / totalExpected) * 100 : 0.0;

    return {
      'totalExpected': totalExpected,
      'totalCollected': totalCollected,
      'totalOutstanding': totalOutstanding,
      'collectionRate': collectionRate,
      'totalPaid': totalPaid,
      'totalPending': totalPending,
      'totalOverdue': totalOverdue,
    };
  }

  /// Get list of classes for the school (used in dropdowns)
  static Future<List<String>> getClassList(String schoolCode) async {
    final snapshot = await _firestore
        .collection('schools')
        .doc(schoolCode)
        .collection('classes')
        .get();

    return snapshot.docs.map((doc) => doc.id).toList();
  }

  // ─── Send Reminders (calls Cloud Function) ───────────────────────────────

  /// Send a fee reminder notification to a student
  static Future<String> sendFeeReminder({
    required String schoolCode,
    required String dueId,
    required String studentId,
  }) async {
    try {
      final callable = _functions.httpsCallable('sendFeeReminder');
      final result = await callable.call({
        'schoolCode': schoolCode,
        'dueId': dueId,
        'studentId': studentId,
      });
      return result.data['message'] as String? ?? 'Reminder request sent';
    } catch (e) {
      print('Fee reminder not sent: $e');
      throw Exception('Failed to send reminder');
    }
  }
}
