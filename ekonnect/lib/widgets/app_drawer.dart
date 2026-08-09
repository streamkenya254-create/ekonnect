import 'package:flutter/material.dart';

import '../core/constants.dart';

/// Shared, spacious navigation drawer used by both the user and responder
/// homes. Header is deep purple; items use purple icon-chips, with coral
/// reserved for emergency/destructive actions. Compose the body with
/// [DrawerSection] and [DrawerTile].
class AppDrawer extends StatelessWidget {
  final String name;
  final String subtitle;
  final IconData subtitleIcon;
  final String? statusText;
  final bool statusActive;
  final List<Widget> children;

  const AppDrawer({
    super.key,
    required this.name,
    required this.subtitle,
    required this.subtitleIcon,
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
      width: MediaQuery.of(context).size.width * 0.72,
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
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
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
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(subtitleIcon,
                              size: 13, color: Colors.white.withValues(alpha: 0.7)),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12.5)),
                          ),
                        ],
                      ),
                      if (statusText != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusActive
                                ? AppColors.accent.withValues(alpha: 0.9)
                                : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusActive
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(statusText!,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
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
              padding: const EdgeInsets.symmetric(vertical: 10),
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
      padding: const EdgeInsets.fromLTRB(26, 16, 24, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.textLight,
          letterSpacing: 1,
        ),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: emergency ? AppColors.accent : AppColors.textDark,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(badge!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  )
                else
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.textLight.withValues(alpha: 0.7), size: 20),
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
