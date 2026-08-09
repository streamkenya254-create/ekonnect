import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

class PhoneAuthScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;

  const PhoneAuthScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focuses = List.generate(6, (_) => FocusNode());

  late String _verificationId;
  bool _verifying = false;
  bool _resending = false;
  String? _error;
  int _resendCountdown = 60;
  Timer? _timer;

  String get _otp => _controllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _startResendTimer();
    // Auto-focus first box
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focuses[0].requestFocus();
    });
  }

  void _startResendTimer() {
    _resendCountdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _verify() async {
    if (_otp.length < 6 || _verifying) return;
    setState(() { _verifying = true; _error = null; });

    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    try {
      await auth.verifyOTP(_verificationId, _otp);
      if (!mounted) return;
      nav.pop(true);
    } catch (e) {
      if (!mounted) return;
      // Clear the boxes so the user can try again
      for (final c in _controllers) { c.clear(); }
      _focuses[0].requestFocus();
      setState(() {
        _error = _friendlyOtpError(e.toString());
        _verifying = false;
      });
    }
  }

  Future<void> _resendOTP() async {
    if (_resendCountdown > 0 || _resending) return;
    setState(() { _resending = true; _error = null; });
    try {
      final vId = await context.read<AuthProvider>().startPhoneSignIn(widget.phoneNumber);
      if (!mounted) return;
      if (vId != '__auto__') {
        _verificationId = vId;
        _startResendTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New OTP sent'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        // Auto-verified on resend
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not resend OTP. Try again.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  String _friendlyOtpError(String raw) {
    if (raw.contains('invalid-verification-code') || raw.contains('INVALID_CODE')) {
      return 'Wrong code. Please check the SMS and try again.';
    }
    if (raw.contains('session-expired') || raw.contains('SESSION_EXPIRED')) {
      return 'This code has expired. Tap "Resend" to get a new one.';
    }
    if (raw.contains('too-many-requests')) {
      return 'Too many attempts. Please wait before trying again.';
    }
    return 'Invalid code. Please try again.';
  }

  void _onBoxChanged(int i, String val) {
    // Handle paste: if more than 1 char lands in box 0, distribute
    if (i == 0 && val.length == 6) {
      final digits = val.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 6) {
        for (int j = 0; j < 6; j++) { _controllers[j].text = digits[j]; }
        _focuses[5].requestFocus();
        setState(() {});
        if (_otp.length == 6) _verify();
        return;
      }
    }

    if (val.isNotEmpty) {
      if (i < 5) _focuses[i + 1].requestFocus();
    } else {
      if (i > 0) _focuses[i - 1].requestFocus();
    }

    setState(() {}); // refresh to enable/disable verify button
    if (_otp.length == 6) _verify();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focuses) { f.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textDark),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: AppColors.primary, size: 28),
              ),

              const SizedBox(height: 24),

              const Text('Verify your number',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),

              const SizedBox(height: 8),

              RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textMedium, height: 1.5),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to\n'),
                    TextSpan(
                      text: widget.phoneNumber,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: AppColors.textDark),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // OTP boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _OtpBox(
                  controller: _controllers[i],
                  focusNode: _focuses[i],
                  hasValue: _controllers[i].text.isNotEmpty,
                  hasError: _error != null,
                  onChanged: (val) => _onBoxChanged(i, val),
                  onBackspace: () {
                    if (_controllers[i].text.isEmpty && i > 0) {
                      _controllers[i - 1].clear();
                      _focuses[i - 1].requestFocus();
                      setState(() {});
                    }
                  },
                )),
              ),

              // Error message
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.emergency, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: AppColors.emergency,
                                      fontSize: 13)),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 32),

              // Verify button
              GestureDetector(
                onTap: (_otp.length == 6 && !_verifying) ? _verify : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: _otp.length == 6 && !_verifying
                        ? const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          )
                        : null,
                    color: _otp.length < 6 || _verifying ? AppColors.divider : null,
                    boxShadow: _otp.length == 6 && !_verifying
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Center(
                    child: _verifying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Text('Verify & Continue',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Resend
              Center(
                child: _resending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary))
                    : _resendCountdown > 0
                        ? Text(
                            'Resend code in ${_resendCountdown}s',
                            style: const TextStyle(
                                color: AppColors.textMedium, fontSize: 13),
                          )
                        : GestureDetector(
                            onTap: _resendOTP,
                            child: const Text(
                              'Resend code',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Single OTP box ────────────────────────────────────────────────────────────

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasValue;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.hasValue,
    required this.hasError,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? AppColors.emergency
        : hasValue
            ? AppColors.primary
            : AppColors.divider;

    return SizedBox(
      width: 46,
      height: 54,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6, // allow 6 for paste detection on box 0
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: hasValue
                ? AppColors.primary.withValues(alpha: 0.06)
                : AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: hasError ? AppColors.emergency : AppColors.primary,
                  width: 2),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
