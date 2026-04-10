// admin_payment_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class AdminPaymentSettingsScreen extends StatefulWidget {
  final String schoolCode;

  const AdminPaymentSettingsScreen({super.key, required this.schoolCode});

  @override
  State<AdminPaymentSettingsScreen> createState() =>
      _AdminPaymentSettingsScreenState();
}

class _AdminPaymentSettingsScreenState
    extends State<AdminPaymentSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _keyIdController = TextEditingController();
  final _keySecretController = TextEditingController();
  final _webhookSecretController = TextEditingController();

  bool _isPaymentEnabled = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _obscureSecret = true;
  bool _obscureWebhook = true;
  bool _isConfigured = false;

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  @override
  void dispose() {
    _keyIdController.dispose();
    _keySecretController.dispose();
    _webhookSecretController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingConfig() async {
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('settings')
          .doc('payment_config')
          .get();

      final secretsDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('settings')
          .doc('payment_secrets')
          .get();

      if (configDoc.exists) {
        final data = configDoc.data()!;
        _keyIdController.text = data['razorpayKeyId'] ?? '';
        _isPaymentEnabled = data['isPaymentEnabled'] ?? false;
      }

      if (secretsDoc.exists) {
        final data = secretsDoc.data()!;
        // For security, show masked version if secret exists
        if (data['razorpayKeySecret'] != null &&
            (data['razorpayKeySecret'] as String).isNotEmpty) {
          _keySecretController.text = data['razorpayKeySecret'];
          _isConfigured = true;
        }
        if (data['webhookSecret'] != null &&
            (data['webhookSecret'] as String).isNotEmpty) {
          _webhookSecretController.text = data['webhookSecret'];
        }
      }
    } catch (e) {
      // First time setup — no config yet
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Save public config (readable by students for checkout)
      final configRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('settings')
          .doc('payment_config');

      batch.set(configRef, {
        'razorpayKeyId': _keyIdController.text.trim(),
        'isPaymentEnabled': _isPaymentEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Save private secrets (only Cloud Functions should read this)
      final secretsRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('settings')
          .doc('payment_secrets');

      batch.set(secretsRef, {
        'razorpayKeySecret': _keySecretController.text.trim(),
        'webhookSecret': _webhookSecretController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isConfigured = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment settings saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'Payment Settings',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status card
                    _buildStatusCard(),
                    const SizedBox(height: 20),

                    // Setup guide
                    _buildSetupGuide(),
                    const SizedBox(height: 20),

                    // API Key ID
                    _buildSectionHeader(
                      'Razorpay Key ID',
                      Icons.key,
                      Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _keyIdController,
                      decoration: InputDecoration(
                        hintText: 'rzp_test_XXXXXXXXXXXX or rzp_live_XXXX',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Key ID is required';
                        }
                        if (!value.startsWith('rzp_test_') &&
                            !value.startsWith('rzp_live_')) {
                          return 'Key ID must start with rzp_test_ or rzp_live_';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // API Key Secret
                    _buildSectionHeader(
                      'Razorpay Key Secret',
                      Icons.lock,
                      Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _keySecretController,
                      obscureText: _obscureSecret,
                      decoration: InputDecoration(
                        hintText: 'Enter your Key Secret',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureSecret
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _obscureSecret = !_obscureSecret),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Key Secret is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Webhook URL
                    _buildSectionHeader(
                      'Webhook URL',
                      Icons.webhook,
                      Colors.purple,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Copy this URL and paste it in your Razorpay Dashboard → Webhooks',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'https://us-central1-student-app-c362d.cloudfunctions.net/razorpayWebhook',
                              style: TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            onPressed: () {
                              Clipboard.setData(
                                const ClipboardData(
                                  text:
                                      'https://us-central1-student-app-c362d.cloudfunctions.net/razorpayWebhook',
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Webhook URL copied to clipboard',
                                  ),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            tooltip: 'Copy URL',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Webhook Secret
                    _buildSectionHeader(
                      'Webhook Secret',
                      Icons.security,
                      Colors.purple,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create a secret string here and use the EXACT SAME value in your Razorpay Dashboard.',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _webhookSecretController,
                      obscureText: _obscureWebhook,
                      decoration: InputDecoration(
                        hintText: 'Enter your Webhook Secret',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        prefixIcon: const Icon(Icons.security),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureWebhook
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscureWebhook = !_obscureWebhook,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Webhook Secret is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Enable/Disable toggle
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isPaymentEnabled
                              ? Colors.green[300]!
                              : Colors.grey[200]!,
                        ),
                      ),
                      child: SwitchListTile(
                        title: const Text(
                          'Enable Fee Payments',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          _isPaymentEnabled
                              ? 'Students can pay fees via Razorpay'
                              : 'Fee payments are disabled',
                          style: TextStyle(
                            color: _isPaymentEnabled
                                ? Colors.green[600]
                                : Colors.grey[500],
                          ),
                        ),
                        value: _isPaymentEnabled,
                        activeColor: Colors.green,
                        onChanged: (value) =>
                            setState(() => _isPaymentEnabled = value),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Security warning
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amber[200]!),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.amber[800],
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Keep your Key Secret and Webhook Secret confidential. '
                              'Never share them publicly. These are securely stored and '
                              'only accessed by the payment processing backend.',
                              style: TextStyle(
                                color: Colors.amber[900],
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveConfig,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Save Payment Settings',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isConfigured
              ? [Colors.green[600]!, Colors.green[800]!]
              : [Colors.orange[600]!, Colors.orange[800]!],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _isConfigured ? Icons.check_circle : Icons.settings,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConfigured ? 'Razorpay Connected' : 'Setup Required',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isConfigured
                      ? _isPaymentEnabled
                            ? 'Payments are live and active'
                            : 'Configured but payments disabled'
                      : 'Enter your Razorpay credentials to get started',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'How to get your keys',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.blue[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildStep('1', 'Log in to dashboard.razorpay.com'),
          _buildStep('2', 'Go to Account & Settings → API Keys'),
          _buildStep(
            '3',
            'Click "Generate Key ID & Secret" (Keep the Secret safe!)',
          ),
          _buildStep(
            '4',
            'Copy the Key ID and Key Secret into the fields below',
          ),
          _buildStep('5', 'Go to Settings → Webhooks → Add New'),
          _buildStep('6', 'Paste the Webhook URL (from below) and your Secret'),
          _buildStep('7', 'Select "order.paid" in Active Events and save'),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.blue[100],
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.blue[800],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.blue[800],
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    );
  }
}
