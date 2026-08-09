import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../core/app_assets.dart';
import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  // Only one role is self-selectable, so pre-select it rather than making the
  // user tap a list of one before Continue enables.
  String? _selectedRole = AppRoles.user;
  bool _loading = false;

  // Responder roles are deliberately NOT offered here.
  //
  // Anyone could previously tick "Ambulance Driver" and start receiving real
  // medical emergencies with no vetting whatsoever. Responder status is now
  // granted by an administrator in the eKonnect admin console, against a
  // verified organisation. Everyone signs up here as an emergency user; the
  // system recognises responders automatically on their next launch.
  static const _roles = [
    {
      'role': AppRoles.user,
      'label': 'Regular User',
      'sub': 'Send an SOS and get help fast',
      'asset': AppAssets.user,
    },
  ];

  Future<void> _proceed() async {
    if (_selectedRole == null) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    await auth.setRole(_selectedRole!);
    if (!mounted) return;
    nav.pushReplacementNamed(AppRoutes.profileSetup, arguments: _selectedRole);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Who are you?',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick your role — it shapes what you see\nand do inside eKonnect.',
                style: TextStyle(
                    color: AppColors.textMedium, fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 24),

              // Role cards — same visual language as the home page tiles.
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _roles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final r = _roles[i];
                    return _RoleCard(
                      label: r['label'] as String,
                      sub: r['sub'] as String,
                      asset: r['asset'] as String,
                      selected: _selectedRole == r['role'],
                      onTap: () => setState(
                          () => _selectedRole = r['role'] as String),
                    );
                  },
                ),
              ),

              // Tells would-be responders where to go, instead of leaving them
              // hunting for an option that no longer exists.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user_outlined,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.textMedium),
                          children: [
                            TextSpan(
                              text: 'Are you a responder?\n',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark),
                            ),
                            TextSpan(
                              text: 'Ambulance crews and practitioners are '
                                  'registered by their organisation and verified '
                                  'by eKonnect. Sign up here as normal — your '
                                  'responder access appears automatically once '
                                  'approved.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: (_selectedRole == null || _loading) ? null : _proceed,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.accent.withValues(alpha: 0.35),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Continue',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String label;
  final String sub;
  final String asset;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.label,
    required this.sub,
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? Colors.white : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8))
                ]
              : null,
        ),
        child: Row(
          children: [
            // Big illustrated SVG in a white tile.
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.all(12),
              child: SvgPicture.asset(asset, fit: BoxFit.contain),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: AppColors.textDark),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.textMedium),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.accent : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.textLight,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
