import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('Account'),
          _Tile(
            icon: Icons.person_outline,
            color: AppColors.primary,
            title: auth.user?.name ?? 'User',
            subtitle: auth.user?.email ?? auth.user?.phone ?? '',
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => Navigator.pushNamed(context, AppRoutes.profile),
            ),
          ),

          const SizedBox(height: 16),
          _SectionHeader('About'),
          _Tile(
            icon: Icons.smart_toy_outlined,
            color: AppColors.primary,
            title: 'AI Emergency Assistant',
            subtitle: 'Powered by Groq — no setup needed',
          ),
          _Tile(
            icon: Icons.info_outline,
            color: AppColors.info,
            title: 'App Version',
            subtitle: 'eKonnect v1.0.0',
          ),
          _Tile(
            icon: Icons.shield_outlined,
            color: AppColors.success,
            title: 'Privacy Policy',
            subtitle: 'How we use your data',
            onTap: () {},
          ),
          _Tile(
            icon: Icons.description_outlined,
            color: AppColors.textMedium,
            title: 'Terms of Service',
            subtitle: 'Usage agreement',
            onTap: () {},
          ),

          const SizedBox(height: 16),
          _SectionHeader('Session'),
          _Tile(
            icon: Icons.logout,
            color: AppColors.emergency,
            title: 'Sign Out',
            subtitle: 'Log out of your account',
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign Out',
                            style: TextStyle(color: AppColors.emergency))),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await context.read<AuthProvider>().signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                      context, AppRoutes.login, (_) => false);
                }
              }
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.textLight,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle = '',
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: subtitle.isNotEmpty
            ? Text(subtitle,
                style: const TextStyle(
                    color: AppColors.textLight, fontSize: 12))
            : null,
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right, color: AppColors.textLight)
                : null),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
