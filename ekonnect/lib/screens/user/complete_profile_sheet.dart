import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';

/// Collects the profile details that used to block sign-up.
///
/// Nothing here is mandatory to use the app — a user can raise an emergency
/// with an empty profile. This exists so the details a responder actually needs
/// (a name to call out, a number to ring back) get filled in soon after, rather
/// than standing between someone and the SOS button on day one.
class CompleteProfileSheet extends StatefulWidget {
  const CompleteProfileSheet({super.key});

  @override
  State<CompleteProfileSheet> createState() => _CompleteProfileSheetState();
}

class _CompleteProfileSheetState extends State<CompleteProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  String? _visibility;
  bool _saving = false;

  /// Where "register with a private provider" sends the user. Admin-editable in
  /// appConfig so the destination can change without shipping a new build.
  String? _privateUrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _name = TextEditingController(text: user?.name ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _visibility = user?.visibility;
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final cfg = await FirestoreService.getAppConfig();
      if (mounted) {
        setState(() => _privateUrl = cfg['privateProviderUrl'] as String?);
      }
    } catch (_) {
      // Falls back to the in-app Providers list below.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      await FirestoreService.updateUser(uid, {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'visibility': _visibility,
        // Only true once everything a responder needs is present.
        'profileComplete':
            _name.text.trim().isNotEmpty && _phone.text.trim().length >= 9,
      });
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPrivateRegistration() async {
    final url = _privateUrl;
    if (url == null || url.isEmpty) {
      // No external portal configured — use the in-app provider list instead.
      Navigator.pop(context);
      Navigator.pushNamed(context, AppRoutes.myProviders);
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
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
              const SizedBox(height: 18),
              const Text('Complete your profile',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                'Responders use these details to reach you. You can send an SOS '
                'without them, but help arrives faster when they are filled in.',
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: AppColors.textMedium),
              ),
              const SizedBox(height: 22),

              _label('Your name'),
              _field(_name, 'As you would like to be called',
                  TextInputType.name),
              const SizedBox(height: 16),

              _label('Phone number'),
              _field(_phone, '+254 7XX XXX XXX', TextInputType.phone),
              const SizedBox(height: 6),
              const Text(
                'A responder calls this number if they cannot find you.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMedium),
              ),
              const SizedBox(height: 22),

              _label('Who should respond to you?'),
              const SizedBox(height: 6),
              _responderOption(
                value: ResponderVisibility.public,
                title: 'Public emergency network',
                body: 'Any nearby verified responder can answer your SOS. '
                    'This is the default and always available.',
                icon: Icons.public_rounded,
              ),
              const SizedBox(height: 10),
              _responderOption(
                value: ResponderVisibility.private,
                title: 'My private provider',
                body: 'Your own hospital, insurer or employer answers directly. '
                    'Requires registration and verification.',
                icon: Icons.business_rounded,
              ),

              if (_visibility == ResponderVisibility.private) ...[
                const SizedBox(height: 12),
                _privateRegistrationCard(user),
              ],

              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.divider,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.textMedium),
                  child: const Text('Not now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark));

  Widget _field(TextEditingController c, String hint, TextInputType type) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TextField(
          controller: c,
          keyboardType: type,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.surfaceAlt,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  Widget _responderOption({
    required String value,
    required String title,
    required String body,
    required IconData icon,
  }) {
    final selected = _visibility == value;
    return InkWell(
      onTap: () => setState(() => _visibility = value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textMedium),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textDark)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: AppColors.textMedium)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.primary : AppColors.divider,
            ),
          ],
        ),
      ),
    );
  }

  /// Shown once "private" is chosen. Registration happens off-app so the
  /// provider can collect whatever they need (policy number, employee ID) and
  /// verify it before the account is linked.
  Widget _privateRegistrationCard(UserModel? user) {
    final verified = user?.verificationStatus == VerificationStatus.verified &&
        (user?.organisation ?? '').isNotEmpty;

    if (verified) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded,
                color: AppColors.success, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user!.organisation!,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  const Text('Verified — they respond to you first',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textMedium)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Register with your provider',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your provider verifies your cover before linking the account. '
            'Once approved, their crews and hospitals become your first '
            'suggestions automatically.',
            style: TextStyle(
                fontSize: 11.5, height: 1.35, color: AppColors.textMedium),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openPrivateRegistration,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(_privateUrl == null || _privateUrl!.isEmpty
                  ? 'Browse providers'
                  : 'Open registration'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
