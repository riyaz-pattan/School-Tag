import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:student_app/models/fee_models.dart';

class PdfReceiptService {
  /// Generates a beautiful PDF receipt from a StudentDue and prompts the user to save or share it.
  static Future<void> generateAndDownloadReceipt(StudentDue due, String schoolName) async {
    return _generatePdf(
      schoolName: schoolName,
      studentName: due.studentName,
      className: due.className,
      installmentLabel: due.installmentLabel,
      amount: due.amount,
      paidAt: due.paidAt,
      razorpayPaymentId: due.razorpayPaymentId,
    );
  }

  /// Generates a PDF invoice from a FeeTransaction (for Admin use).
  static Future<void> generateInvoiceFromTransaction(FeeTransaction txn, String schoolName) async {
    return _generatePdf(
      schoolName: schoolName,
      studentName: txn.studentName,
      className: txn.className,
      installmentLabel: 'Fee Payment',
      amount: txn.amount,
      paidAt: txn.createdAt,
      razorpayPaymentId: txn.razorpayPaymentId,
    );
  }

  static Future<void> _generatePdf({
    required String schoolName,
    required String studentName,
    required String className,
    required String installmentLabel,
    required double amount,
    DateTime? paidAt,
    String? razorpayPaymentId,
  }) async {
    final pdf = pw.Document();

    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final fileDateFormat = DateFormat('yyyyMMdd');
    final formattedDate = paidAt != null ? dateFormat.format(paidAt) : 'N/A';
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                   pw.Expanded(
                     child: pw.Column(
                       crossAxisAlignment: pw.CrossAxisAlignment.start,
                       children: [
                         pw.Text(schoolName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                         pw.SizedBox(height: 4),
                         pw.Text('FEE PAYMENT RECEIPT', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700, letterSpacing: 1.2)),
                       ],
                     ),
                   ),
                   pw.Column(
                     crossAxisAlignment: pw.CrossAxisAlignment.end,
                     children: [
                       pw.Text('Receipt No.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                       pw.Text(razorpayPaymentId ?? 'N/A', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                       pw.SizedBox(height: 8),
                       pw.Text('Date Paid', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                       pw.Text(formattedDate, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                     ]
                   )
                ]
              ),
              pw.SizedBox(height: 30),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 20),

              // Student Info
              pw.Text('Billed To:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Student Name:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                        pw.Text(studentName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      ]
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Class/Grade:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                        pw.Text(className, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      ]
                    ),
                  ]
                )
              ),
              
              pw.SizedBox(height: 30),

              // Payment Details Table
              pw.Table.fromTextArray(
                border: null,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
                cellHeight: 40,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                },
                headers: ['Description', 'Status', 'Amount (INR)'],
                data: [
                  [installmentLabel, 'PAID', 'Rs. ${amount.toStringAsFixed(2)}'],
                ],
              ),
              pw.Divider(color: PdfColors.grey300),

              // Total
              pw.Container(
                alignment: pw.Alignment.centerRight,
                padding: const pw.EdgeInsets.only(top: 10),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text('Total Paid: ', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Rs. ${amount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                  ]
                )
              ),

              pw.Spacer(),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'This is a computer-generated receipt and requires no physical signature.', 
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  textAlign: pw.TextAlign.center
                )
              )
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final filename = 'Fee_Receipt_${studentName.replaceAll(' ', '_')}_${fileDateFormat.format(paidAt ?? DateTime.now())}.pdf';

    if (kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Fee Receipt',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
      }
    } else {
      // For iOS/Android, Printing can trigger native Share/Save menu
      await Printing.sharePdf(bytes: bytes, filename: filename);
    }
  }
}
