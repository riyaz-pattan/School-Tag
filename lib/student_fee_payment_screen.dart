// student_fee_payment_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'models/fee_models.dart';
import 'services/fee_service.dart';

class StudentFeePaymentScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String studentName;
  final StudentDue due;

  const StudentFeePaymentScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.studentName,
    required this.due,
  });

  @override
  State<StudentFeePaymentScreen> createState() =>
      _StudentFeePaymentScreenState();
}

enum PaymentState { summary, loading, verifying, success, failure }

class _StudentFeePaymentScreenState extends State<StudentFeePaymentScreen> {
  late Razorpay _razorpay;
  PaymentState _paymentState = PaymentState.summary;
  String? _errorMessage;
  String? _transactionId;
  String? _razorpayOrderId;

  final NumberFormat _formatter =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  // ─── Razorpay Callbacks ──────────────────────────────────────────────────

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    setState(() {
      _paymentState = PaymentState.verifying;
      _transactionId = response.paymentId;
    });

    // Client-side verification (the webhook is the source of truth)
    FeeService.verifyPaymentClientSide(
      schoolCode: widget.schoolCode,
      dueId: widget.due.id,
      razorpayPaymentId: response.paymentId ?? '',
      razorpayOrderId: response.orderId ?? _razorpayOrderId ?? '',
      razorpaySignature: response.signature ?? '',
    ).then((_) {
      // Listen to due status changes via real-time stream
      _waitForPaymentConfirmation();
    }).catchError((e) {
      // Even if client verification fails, webhook will handle it
      _waitForPaymentConfirmation();
    });
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    setState(() {
      _paymentState = PaymentState.failure;
      _errorMessage = _getHumanReadableError(response.code, response.message);
    });
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    // External wallet selected — Razorpay will handle it
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Processing with ${response.walletName ?? "wallet"}...')),
    );
  }

  String _getHumanReadableError(int? code, String? message) {
    switch (code) {
      case Razorpay.NETWORK_ERROR:
        return 'Network connection failed. Please check your internet and try again.';
      case Razorpay.INVALID_OPTIONS:
        return 'Payment configuration error. Please contact the school.';
      case Razorpay.PAYMENT_CANCELLED:
        return 'Payment was cancelled. You can try again when ready.';
      case Razorpay.TLS_ERROR:
        return 'Secure connection failed. Please update your device and try again.';
      default:
        return message ?? 'Payment failed. Please try again.';
    }
  }

  void _waitForPaymentConfirmation() {
    // Listen to the due document for up to 3 minutes
    final stream = FeeService.streamSingleDue(
      schoolCode: widget.schoolCode,
      dueId: widget.due.id,
    );

    bool settled = false;
    final subscription = stream.listen((due) {
      if (due != null && due.isPaid && !settled) {
        settled = true;
        if (mounted) {
          setState(() {
            _paymentState = PaymentState.success;
          });
        }
      }
    });

    // Timeout after 3 minutes
    Future.delayed(const Duration(minutes: 3), () {
      if (!settled && mounted) {
        subscription.cancel();
        setState(() {
          _paymentState = PaymentState.success;
          _transactionId ??= 'Processing...';
        });
      }
    });
  }

  // ─── Initiate Payment ────────────────────────────────────────────────────

  Future<void> _initiatePayment() async {
    setState(() {
      _paymentState = PaymentState.loading;
      _errorMessage = null;
    });

    try {
      final orderData = await FeeService.createRazorpayOrder(
        schoolCode: widget.schoolCode,
        dueId: widget.due.id,
        studentId: widget.userId,
      );

      _razorpayOrderId = orderData['orderId'];

      final options = {
        'key': orderData['keyId'],
        'amount': orderData['amount'], // in paise
        'currency': orderData['currency'] ?? 'INR',
        'order_id': orderData['orderId'],
        'name': widget.schoolName,
        'description':
            '${widget.due.installmentLabel} — ${widget.due.className}',
        'prefill': {
          'contact': '',
          'email': '',
        },
        'theme': {
          'color': '#1565C0',
        },
        'retry': {
          'enabled': true,
          'max_count': 3,
        },
      };

      _razorpay.open(options);

      // Reset to summary so user sees the Razorpay UI
      // (Razorpay handles its own overlay)
      if (mounted) setState(() => _paymentState = PaymentState.summary);
    } catch (e) {
      setState(() {
        _paymentState = PaymentState.failure;
        _errorMessage =
            'Could not connect to payment service. Please try again later.';
      });
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: _paymentState == PaymentState.success ||
              _paymentState == PaymentState.verifying
          ? null
          : AppBar(
              title: const Text(
                'Fee Payment',
                style:
                    TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_paymentState) {
      case PaymentState.summary:
        return _buildPaymentSummary();
      case PaymentState.loading:
        return _buildLoadingState();
      case PaymentState.verifying:
        return _buildVerifyingState();
      case PaymentState.success:
        return _buildSuccessState();
      case PaymentState.failure:
        return _buildFailureState();
    }
  }

  // ─── Summary Screen ──────────────────────────────────────────────────────

  Widget _buildPaymentSummary() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Payment Details Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // School icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.school, size: 40, color: Colors.blue[700]),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.schoolName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                _buildPaymentDetailRow('Student', widget.studentName),
                _buildPaymentDetailRow('Class', widget.due.className),
                _buildPaymentDetailRow('Fee', widget.due.installmentLabel),
                _buildPaymentDetailRow(
                    'Due Date',
                    DateFormat('dd MMMM yyyy')
                        .format(widget.due.dueDate)),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                // Amount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Amount to Pay',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _formatter.format(widget.due.amount),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Security note
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.lock, size: 20, color: Colors.green[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Secured by Razorpay. Your payment details are encrypted.',
                    style: TextStyle(
                      color: Colors.green[800],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Proceed to Pay button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _initiatePayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payment, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Proceed to Pay',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Payment methods
          Text(
            'UPI • Credit/Debit Card • Net Banking • Wallets',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Loading State ───────────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(
            'Preparing payment...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we connect to Razorpay',
            style: TextStyle(color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  // ─── Verifying State ─────────────────────────────────────────────────────

  Widget _buildVerifyingState() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.blue[50]!, Colors.white],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(
              'Verifying Payment...',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please wait. Do not close this screen.',
              style: TextStyle(color: Colors.grey[500]),
            ),
            if (_transactionId != null) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Transaction ID: $_transactionId',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Success State ───────────────────────────────────────────────────────

  Widget _buildSuccessState() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.green[50]!, Colors.white],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle,
                    size: 64, color: Colors.green[700]),
              ),
              const SizedBox(height: 24),
              Text(
                'Payment Successful!',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.green[800],
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatter.format(widget.due.amount),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.due.installmentLabel,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              if (_transactionId != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildPaymentDetailRow(
                          'Transaction ID', _transactionId!),
                      _buildPaymentDetailRow('Student', widget.studentName),
                      _buildPaymentDetailRow('Class', widget.due.className),
                      _buildPaymentDetailRow(
                          'Date',
                          DateFormat('dd MMM yyyy, hh:mm a')
                              .format(DateTime.now())),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Failure State ───────────────────────────────────────────────────────

  Widget _buildFailureState() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.red[50]!, Colors.white],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(Icons.cancel, size: 64, color: Colors.red[700]),
              ),
              const SizedBox(height: 24),
              Text(
                'Payment Failed',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.red[800],
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ??
                    'Something went wrong. Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _initiatePayment,
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
