import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

/// Sign in and sign up, on one page, carrying only the forms.
class LoginScreen extends StatefulWidget {
  /// Which side of the toggle to land on. The welcome screen decides.
  final bool startOnSignUp;

  const LoginScreen({super.key, this.startOnSignUp = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  late bool _signUp = widget.startOnSignUp;
  bool _obscure = true;
  bool _acceptedTerms = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _afterAuth(NavigatorState nav, AuthProvider auth) {
    if (!auth.isAuthenticated) return;
    if (AppRoles.isResponder(auth.user?.effectiveRole ?? '')) {
      nav.pushNamedAndRemoveUntil(AppRoutes.responderHome, (_) => false);
    } else {
      nav.pushNamedAndRemoveUntil(AppRoutes.userHome, (_) => false);
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    if (_signUp && !_acceptedTerms) {
      setState(() => _error = 'Please accept the terms to create an account.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    if (_signUp) {
      await auth.signUpWithEmail(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      if (auth.error == null) await auth.acceptTerms();
    } else {
      await auth.signInWithEmail(
        email: _email.text.trim(),
        password: _password.text,
      );
    }
    if (!mounted) return;
    setState(() => _error = auth.error);
    if (auth.error == null) _afterAuth(nav, auth);
  }

  Future<void> _google() async {
    setState(() => _error = null);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    await auth.signInWithGoogle();
    if (!mounted) return;
    if (auth.error == null) await auth.acceptTerms();
    if (!mounted) return;
    setState(() => _error = auth.error);
    if (auth.error == null) _afterAuth(nav, auth);
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email first, then tap this again.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final sent = await context.read<AuthProvider>().sendPasswordReset(email);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      backgroundColor: Colors.white,
      content: Text(
        sent
            ? 'Password reset link sent to $email'
            : 'Could not send a reset link. Check the address.',
        style: const TextStyle(color: Colors.black87),
      ),
    ));
  }

  Future<void> _openTerms() async {
    final uri = Uri.parse('https://ekonnectapp.web.app/privacy');
    final messenger = ScaffoldMessenger.of(context);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Open ekonnectapp.web.app/privacy in your browser')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().isLoading;

    return Scaffold(
      // Matching the deep, modern background from the welcome screen
      backgroundColor: AppColors.primaryDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true, // Allows content to slide elegantly under the app bar
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Clean, bold typography
                Text(
                  _signUp ? 'Create account' : 'Welcome back',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _signUp
                      ? 'You only need this once. It takes a moment.'
                      : 'Sign in to send an SOS or go on duty.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 40),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (_signUp) ...[
                        _Field(
                          controller: _name,
                          label: 'Full name',
                          icon: Icons.person_outline,
                          validator: (v) => (v ?? '').trim().length < 3
                              ? 'Tell us your name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _Field(
                        controller: _email,
                        label: 'Email',
                        icon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'Enter your email';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                            return 'That email does not look right';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _Field(
                        controller: _password,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscure: _obscure,
                        trailing: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 22,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        validator: (v) => (v ?? '').length < 6
                            ? 'At least 6 characters'
                            : null,
                      ),
                    ],
                  ),
                ),

                if (!_signUp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : _forgotPassword,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.7),
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),

                if (_signUp) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _acceptedTerms,
                              onChanged: (v) =>
                                  setState(() => _acceptedTerms = v ?? false),
                              activeColor: Colors.white,
                              checkColor: AppColors.primaryDark,
                              side: WidgetStateBorderSide.resolveWith(
                                (states) => const BorderSide(color: Colors.white54, width: 1.5),
                              ),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'I agree to the ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _openTerms,
                                    child: const Text(
                                      'Terms & Privacy Policy',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 20, color: Colors.redAccent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                                fontSize: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Primary Action Button (Styled like "Create an account")
                ElevatedButton(
                  onPressed: busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primaryDark,
                    elevation: 0,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: AppColors.primaryDark),
                        )
                      : Text(
                          _signUp ? 'Create account' : 'Sign in',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),

                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: Divider(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                ]),
                const SizedBox(height: 24),

                // Secondary Action Button (Styled like "I already have an account")
                OutlinedButton.icon(
                  onPressed: busy ? null : _google,
                  icon: Image.asset(
                    'assets/images/google.png',
                    width: 20,
                    height: 20,
                    errorBuilder: (_, _, _) {
                      return const Icon(Icons.g_mobiledata_rounded,
                          size: 28, color: Colors.white);
                    },
                  ),
                  label: const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Toggler
                Center(
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              _signUp = !_signUp;
                              _error = null;
                            }),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        children: [
                          TextSpan(
                            text: _signUp
                                ? 'Already have an account?  '
                                : 'New to eKonnect?  ',
                          ),
                          TextSpan(
                            text: _signUp ? 'Sign in' : 'Create one',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A simplified, visually pleasing input field tuned for dark mode.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.trailing,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 16, color: Colors.white),
      cursorColor: Colors.white,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        prefixIcon: Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.6)),
        suffixIcon: trailing,
        filled: true,
        // Semi-transparent glassmorphism feel for the inputs
        fillColor: Colors.white.withValues(alpha: 0.08),
        contentPadding: const EdgeInsets.symmetric(vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
    );
  }
}