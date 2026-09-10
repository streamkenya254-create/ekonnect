import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/user_model.dart';
import 'user_avatar.dart';

/// Shared, spacious navigation drawer used by both the user and responder
/// homes. Header is deep purple; items use purple icon-chips, with coral
/// reserved for emergency/destructive actions. Compose the body with
/// [DrawerSection] and [DrawerTile].
class AppDrawer extends StatelessWidget {
  final String name;

  /// The signed-in user, when the caller has one.
  ///
  /// The drawer used to take only a name and derive initials from it, so a
  /// profile photo could never appear here however many times it was set.
  final UserModel? user;
  final String subtitle;
  final String? statusText;
  final bool statusActive;
  final List<Widget> children;

  const AppDrawer({
    super.key,
    required this.name,
    this.user,
    required this.subtitle,
    required this.children,
    this.statusText,
    this.statusActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return Drawer(
      backgroundColor: AppColors.surface,
      width: MediaQuery.of(context).size.width * 0.80,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 26,
              left: 24,
              right: 24,
              bottom: 28,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                user != null
                    ? GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, AppRoutes.profile);
                        },
                        child: UserAvatar(
                          user: user,
                          size: 56,
                          background: Colors.white.withValues(alpha: 0.16),
                          foreground: Colors.white,
                          ring: Colors.white.withValues(alpha: 0.35),
                        ),
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.16),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        child: Center(
                          child: Text(initials.isEmpty ? '?' : initials,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20)),
                        ),
                      ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      if (statusText != null) ...[
                        const SizedBox(height: 4),
                        Text(statusText!,
                            style: TextStyle(
                                color: statusActive
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase section label between groups of drawer items.
class DrawerSection extends StatelessWidget {
  final String label;
  const DrawerSection(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, AppSpacing.lg, 24, AppSpacing.sm),
      child: Text(label, style: AppText.sectionTitle),
    );
  }
}

/// A single, spacious drawer row with a colored icon-chip.
class DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emergency; // renders in coral for destructive/emergency actions
  final String? badge;

  const DrawerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emergency = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final color = emergency ? AppColors.accent : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong.copyWith(
                          color: emergency
                              ? AppColors.accent
                              : AppColors.textDark)),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(badge!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
                  )
                else
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.textLight.withValues(alpha: 0.7), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin inset divider for grouping drawer sections.
class DrawerDivider extends StatelessWidget {
  const DrawerDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Divider(height: 1, color: AppColors.divider),
    );
  }
}
