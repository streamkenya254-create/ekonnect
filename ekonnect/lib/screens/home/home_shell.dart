import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import '../responder/responder_home_screen.dart';
import '../user/user_home_screen.dart';

/// Single entry point for the signed-in experience. It watches the user's
/// [effectiveRole] and swaps the entire screen — user emergency mode vs
/// responder mode — with a smooth cross-fade/slide whenever the mode changes.
///
/// Because it's reactive, switching modes is just a call to
/// `AuthProvider.switchMode(...)`; no manual navigation is needed and the whole
/// screen animates over in place.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.select<AuthProvider, String>(
        (a) => a.user?.effectiveRole ?? AppRoles.user);
    final isResponder = AppRoles.isResponder(role);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: isResponder
          ? const ResponderHomeScreen(key: ValueKey('responder'))
          : const UserHomeScreen(key: ValueKey('user')),
    );
  }
}
