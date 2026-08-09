import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _loading = false;

  Future<void> _accept() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    await auth.acceptTerms();
    if (!mounted) return;
    // Straight to the app. Profile details are collected later, from a prompt
    // on the home screen, so a new user can raise an emergency immediately.
    nav.pushReplacementNamed(AppRoutes.userHome);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms and Conditions')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Terms and Conditions',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  _para(
                    'These Terms and Conditions govern your use of the eKonnect Application. '
                    'By accessing and using the Application you are deemed to have understood and agreed to the terms.',
                  ),
                  _para(
                    'The Application is owned and operated by eKonnect.',
                  ),
                  _para(
                    'eKonnect reserves the right to vary, amend or modify or impose new conditions '
                    'in these Terms and Conditions at any time without any notification to you. '
                    'Any such variations, amendments or modifications will be reflected by an update '
                    'on the Application. You are therefore responsible for checking these Terms and '
                    'Conditions periodically to be aware of any such changes. Your continued access '
                    'of this service following the posting of any changes to these Terms and Conditions '
                    'shall constitute your acceptance and agreement of the same.',
                  ),
                  _para(
                    'eKonnect is an emergency coordination platform. Response times, availability '
                    'of responders, and service quality may vary based on your location and network '
                    'conditions. eKonnect does not guarantee a specific response time.',
                  ),
                  _para(
                    'By using this application, you consent to sharing your GPS location with '
                    'assigned responders and with the eKonnect administrative team for the purpose '
                    'of emergency response coordination.',
                  ),
                  _para(
                    'Misuse of the SOS feature (false alarms) may result in your account being '
                    'suspended and may be subject to legal action.',
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, AppRoutes.login),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.emergency,
                        side: const BorderSide(color: AppColors.emergency),
                      ),
                      child: const Text('CANCEL'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _accept,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('ACCEPT'),
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

  Widget _para(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(height: 1.6)),
      );
}
