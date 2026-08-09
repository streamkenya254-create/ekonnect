import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../core/app_assets.dart';
import '../../core/constants.dart';
import '../../core/validators.dart';
import '../../providers/auth_provider.dart';
import 'phone_auth_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSignUp = false;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _formError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _routeAfterLogin(AuthProvider auth, NavigatorState nav) {
    if (!auth.hasAcceptedTerms) {
      nav.pushReplacementNamed(AppRoutes.terms);
    } else if (!auth.hasCompletedProfile) {
      nav.pushReplacementNamed(AppRoutes.roleSelect);
    } else if (AppRoles.isResponder(auth.user?.effectiveRole ?? '')) {
      nav.pushReplacementNamed(AppRoutes.responderHome);
    } else {
      nav.pushReplacementNamed(AppRoutes.userHome);
    }
  }

  Future<void> _emailAction() async {
    setState(() => _formError = null);
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (_isSignUp) {
      final nameError = Validators.name(_nameCtrl.text);
      if (nameError != null) {
        setState(() => _formError = nameError);
        return;
      }
    }

    final emailError = Validators.email(email);
    if (emailError != null) {
      setState(() => _formError = emailError);
      return;
    }

    final passwordError =
        Validators.password(password, requireStrong: _isSignUp);
    if (passwordError != null) {
      setState(() => _formError = passwordError);
      return;
    }

    if (_isSignUp && password != _confirmCtrl.text) {
      setState(() => _formError = 'Passwords do not match.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    auth.clearError();

    if (_isSignUp) {
      await auth.signUpWithEmail(
          name: _nameCtrl.text.trim(), email: email, password: password);
    } else {
      await auth.signInWithEmail(email: email, password: password);
    }

    if (!mounted) return;
    if (auth.error == null) {
      _routeAfterLogin(auth, nav);
    } else {
      setState(() => _formError = auth.error);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _formError = null);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    await auth.signInWithGoogle();
    if (!mounted) return;
    if (auth.error == null) {
      _routeAfterLogin(auth, nav);
    } else {
      setState(() => _formError = auth.error);
    }
  }

  Future<void> _phoneSignIn() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _formError = 'Please enter your phone number.');
      return;
    }
    if (!phone.startsWith('+')) {
      setState(() => _formError = 'Use international format, e.g. +254 700 000 000');
      return;
    }
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    try {
      final vId = await auth.startPhoneSignIn(phone);
      if (!mounted) return;

      if (vId == '__auto__') {
        _routeAfterLogin(auth, nav);
        return;
      }

      final result = await nav.push<bool>(
        MaterialPageRoute(
          builder: (_) => PhoneAuthScreen(phoneNumber: phone, verificationId: vId),
        ),
      );
      if (result == true && mounted) _routeAfterLogin(auth, nav);
    } catch (e) {
      if (mounted) setState(() => _formError = _friendlyPhoneError(e.toString()));
    }
  }

  String _friendlyPhoneError(String raw) {
    if (raw.contains('invalid-phone-number') || raw.contains('INVALID_PHONE_NUMBER')) {
      return 'Invalid phone number. Use international format: +254 7XX XXX XXX';
    }
    if (raw.contains('too-many-requests') || raw.contains('TOO_MANY_REQUESTS')) {
      return 'Too many attempts. Please wait a few minutes and try again.';
    }
    if (raw.contains('quota-exceeded') || raw.contains('QUOTA_EXCEEDED')) {
      return 'SMS quota exceeded. Please try another sign-in method.';
    }
    if (raw.contains('network') || raw.contains('NETWORK')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (raw.contains('blocked') || raw.contains('BLOCKED')) {
      return 'This device has been temporarily blocked. Try again later.';
    }
    return 'Could not send OTP. Check your number and try again.';
  }

  void _forgotPassword() {
    showDialog(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initialEmail: _emailCtrl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── Full-page brand gradient ───────────────────────────────
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // ── Single-page content ────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero — big ambulance illustration, no frame.
                  SvgPicture.asset(
                    AppAssets.ambulanceHome,
                    height: size.height * 0.24,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: Text(
                      'eKonnect',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Emergency Response, Anytime',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Tab toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _TabBtn(
                          label: 'Sign In',
                          selected: !_isSignUp,
                          onTap: () => setState(() {
                            _isSignUp = false;
                            _formError = null;
                          }),
                        ),
                        _TabBtn(
                          label: 'Create Account',
                          selected: _isSignUp,
                          onTap: () => setState(() {
                            _isSignUp = true;
                            _formError = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Name (sign-up only)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _isSignUp
                        ? Column(
                            children: [
                              _Field(
                                controller: _nameCtrl,
                                hint: 'Full name',
                                icon: Icons.person_outline,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                              ),
                              const SizedBox(height: 12),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),

                  // Email
                  _Field(
                    controller: _emailCtrl,
                    hint: 'Email address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 12),

                  // Password
                  _Field(
                    controller: _passwordCtrl,
                    hint: 'Password',
                    icon: Icons.lock_outline,
                    obscure: _obscurePass,
                    textInputAction: _isSignUp
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_isSignUp && !auth.isLoading) _emailAction();
                    },
                    autofillHints: _isSignUp
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),

                  // Confirm (sign-up only)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _isSignUp
                        ? Column(
                            children: [
                              const SizedBox(height: 12),
                              _Field(
                                controller: _confirmCtrl,
                                hint: 'Confirm password',
                                icon: Icons.lock_outline,
                                obscure: _obscureConfirm,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!auth.isLoading) _emailAction();
                                },
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscureConfirm = !_obscureConfirm),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),

                  // Forgot password (sign-in only)
                  if (!_isSignUp) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('Forgot password?',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.85))),
                      ),
                    ),
                  ] else
                    const SizedBox(height: 12),

                  // Error banner
                  if (_formError != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _formError!,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ] else
                    const SizedBox(height: 6),

                  // Primary action — coral to pop on purple.
                  _PrimaryButton(
                    label: _isSignUp ? 'Create Account' : 'Sign In',
                    isLoading: auth.isLoading,
                    onTap: auth.isLoading ? null : _emailAction,
                  ),

                  const SizedBox(height: 22),

                  // Divider
                  Row(children: [
                    Expanded(
                        child: Divider(
                            color: Colors.white.withValues(alpha: 0.2))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'or continue with',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12),
                      ),
                    ),
                    Expanded(
                        child: Divider(
                            color: Colors.white.withValues(alpha: 0.2))),
                  ]),

                  const SizedBox(height: 16),

                  // Social buttons
                  Row(
                    children: [
                      Expanded(
                        child: _SocialBtn(
                          asset: AppAssets.google,
                          label: 'Google',
                          iconSize: 22,
                          onTap: auth.isLoading ? null : _googleSignIn,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SocialBtn(
                          icon: Icons.phone,
                          label: 'Phone OTP',
                          iconSize: 20,
                          onTap: auth.isLoading
                              ? null
                              : () => _showPhoneSheet(context),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  Center(
                    child: Text(
                      'By continuing you agree to our Terms & Privacy Policy',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11),
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

  void _showPhoneSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Phone Sign In',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('We\'ll send a one-time OTP to your number',
                  style: TextStyle(color: AppColors.textMedium, fontSize: 13)),
              const SizedBox(height: 20),
              _Field(
                controller: _phoneCtrl,
                hint: '+254 700 000 000',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                light: true,
              ),
              const SizedBox(height: 16),
              _GradientButton(
                label: 'Send OTP',
                isLoading: context.read<AuthProvider>().isLoading,
                onTap: () {
                  final phone = _phoneCtrl.text.trim();
                  if (phone.isEmpty) return;
                  Navigator.pop(context);
                  _phoneSignIn();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tab toggle button (dark page) ───────────────────────────────────────────

class _TabBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Input field (dark by default, light for white sheets/dialogs) ────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final bool light;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final fill = light
        ? AppColors.background
        : Colors.white.withValues(alpha: 0.10);
    final borderColor =
        light ? AppColors.divider : Colors.white.withValues(alpha: 0.22);
    final textColor = light ? AppColors.textDark : Colors.white;
    final hintColor =
        light ? AppColors.textLight : Colors.white.withValues(alpha: 0.55);
    final iconColor =
        light ? AppColors.textLight : Colors.white.withValues(alpha: 0.7);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscure,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        autofillHints: autofillHints,
        cursorColor: light ? AppColors.primary : Colors.white,
        style: TextStyle(fontSize: 14, color: textColor),
        decoration: InputDecoration(
          // Override the global white fill so our container colour shows.
          filled: false,
          prefixIcon: Icon(icon, size: 20, color: iconColor),
          hintText: hint,
          hintStyle: TextStyle(color: hintColor, fontSize: 14),
          suffixIcon: suffix,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        ),
      ),
    );
  }
}

// ── Primary (coral) action button ───────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onTap;

  const _PrimaryButton(
      {required this.label, required this.isLoading, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.35),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: AppColors.textDark, strokeWidth: 2.5),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Gradient action button (white sheets/dialogs) ───────────────────────────

class _GradientButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onTap;

  const _GradientButton(
      {required this.label, required this.isLoading, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: onTap == null
              ? null
              : const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          color: onTap == null ? AppColors.divider : null,
          boxShadow: onTap != null
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
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Social button (dark page) ────────────────────────────────────────────────

class _SocialBtn extends StatelessWidget {
  final IconData? icon;
  final String? asset;
  final String label;
  final double iconSize;
  final VoidCallback? onTap;

  const _SocialBtn({
    this.icon,
    this.asset,
    required this.label,
    required this.iconSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            asset != null
                ? SvgPicture.asset(asset!, width: iconSize, height: iconSize)
                : Icon(icon, size: iconSize, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Forgot-password dialog ──────────────────────────────────────────────────

class _ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;
  const _ForgotPasswordDialog({required this.initialEmail});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _emailCtrl;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    final emailError = Validators.email(email);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final ok = await auth.sendPasswordReset(email);
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (ok) {
        _sent = true;
      } else {
        _error = auth.error ?? 'Could not send reset email. Try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: _sent ? _buildSuccess() : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock_reset_rounded,
              color: AppColors.primary, size: 28),
        ),
        const SizedBox(height: 16),
        const Text(
          'Reset your password',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark),
        ),
        const SizedBox(height: 8),
        const Text(
          "Enter your account email and we'll send you a link to reset your password.",
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: AppColors.textMedium, height: 1.4),
        ),
        const SizedBox(height: 20),
        _Field(
          controller: _emailCtrl,
          hint: 'Email address',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          enabled: !_sending,
          light: true,
          onSubmitted: (_) {
            if (!_sending) _send();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.emergency, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: const TextStyle(
                        color: AppColors.emergency, fontSize: 13)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _sending ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMedium,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GradientButton(
                label: 'Send link',
                isLoading: _sending,
                onTap: _sending ? null : _send,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mark_email_read_rounded,
              color: AppColors.success, size: 28),
        ),
        const SizedBox(height: 16),
        const Text(
          'Check your inbox',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(
                fontSize: 13, color: AppColors.textMedium, height: 1.4),
            children: [
              const TextSpan(
                  text:
                      'If an account exists for that email, a reset link is on its way to '),
              TextSpan(
                text: _emailCtrl.text.trim(),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.textDark),
              ),
              const TextSpan(
                  text: '. Check your spam folder if you don\'t see it.'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _GradientButton(
          label: 'Done',
          isLoading: false,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
