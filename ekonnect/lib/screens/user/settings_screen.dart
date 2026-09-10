import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

/// Account settings.
///
/// Deliberately short. Everything that was here to fill the page — the AI
/// blurb, a version row, a subtitle under each item restating its own label —
/// told the user nothing they had asked for. What is left is the two things
/// they may need to change, the two documents they may need to read, and the
/// way out.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static final _privacy = Uri.parse('https://ekonnectapp.web.app/privacy');

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 20, color: AppColors.textDark),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Settings', style: AppText.appBarTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // One card, because these are one thing: how we reach you.
          _Group(children: [
            _Value(
              label: 'Email & sign in',
              value: user?.email ?? '',
              onEdit: () => Navigator.pushNamed(context, AppRoutes.profile,
                  arguments: {'edit': true}),
            ),
            _Value(
              label: 'Phone',
              value: user?.phone ?? '',
              placeholder: 'Not set',
              onEdit: () => Navigator.pushNamed(context, AppRoutes.profile,
                  arguments: {'edit': true}),
            ),
          ]),

          const SizedBox(height: AppSpacing.xl),

          _Row(
            icon: Icons.shield_outlined,
            label: 'Privacy Policy',
            // Was an empty onTap that looked tappable and did nothing.
            onTap: () => launchUrl(_privacy,
                mode: LaunchMode.externalApplication),
          ),
          _Row(
            icon: Icons.description_outlined,
            label: 'Terms of Service',
            onTap: () => launchUrl(_privacy,
                mode: LaunchMode.externalApplication),
          ),

          const SizedBox(height: AppSpacing.xl),

          OutlinedButton(
            onPressed: () => _signOut(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.emergency,
              side: const BorderSide(color: AppColors.divider, width: 1.5),
            ),
            child: const Text('Sign out'),
          ),

          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text('eKonnect v1.0.0',
                style: AppText.meta.copyWith(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to use the app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.emergency),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    await auth.signOut();
    nav.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }
}

/// Related values in one bordered card, divided rather than separated.
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in children) ...[
            c,
            if (c != children.last)
              const Divider(height: 1, color: AppColors.divider),
          ],
        ],
      ),
    );
  }
}

/// A label, what it is currently set to, and a way to change it.
class _Value extends StatelessWidget {
  final String label;
  final String value;
  final String placeholder;
  final VoidCallback onEdit;

  const _Value({
    required this.label,
    required this.value,
    required this.onEdit,
    this.placeholder = '—',
  });

  @override
  Widget build(BuildContext context) {
    final shown = value.trim().isEmpty ? placeholder : value.trim();
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.cardTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Text(shown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(
                          color: value.trim().isEmpty
                              ? AppColors.textLight
                              : AppColors.textMedium)),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined,
                size: 20, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }
}

/// A plain destination. No card, no subtitle — the label is the whole message.
class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Row({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textDark),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: AppText.cardTitle)),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textLight, size: 22),
          ],
        ),
      ),
    );
  }
}
