import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../services/fcm_service.dart';

/// Bootstrap route. Deliberately draws nothing but the brand colour: the
/// branded artwork comes from the native launch screen (see the
/// `flutter_native_splash` block in pubspec.yaml), which main() holds on
/// screen until [_navigate] resolves auth and hands off to the first real
/// route. Painting a logo here too would read as a second splash.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Backstop so a stalled bootstrap can never wedge the app behind the
  /// native splash with no way out.
  static const _maxSplashHold = Duration(seconds: 6);

  Timer? _holdTimer;
  bool _splashRemoved = false;

  @override
  void initState() {
    super.initState();
    _holdTimer = Timer(_maxSplashHold, _removeNativeSplash);
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
  }

  void _removeNativeSplash() {
    if (_splashRemoved) return;
    _splashRemoved = true;
    _holdTimer?.cancel();
    FlutterNativeSplash.remove();
  }

  Future<void> _navigate() async {
    // Capture all context refs before any await
    final auth = context.read<AuthProvider>();
    final incidentProvider = context.read<IncidentProvider>();
    final nav = Navigator.of(context);

    // Tear the native splash down in the same beat as the route swap, so the
    // first frame revealed is already the destination screen.
    void go(String route) {
      _removeNativeSplash();
      nav.pushReplacementNamed(route);
    }

    // Wait for auth to resolve. AuthProvider starts out isLoading = true, so
    // this is the real gate — no artificial delay needed on top of it.
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 100));
      return auth.isLoading;
    });

    if (!mounted) return;

    if (!auth.isAuthenticated) {
      go(AppRoutes.login);
      return;
    }

    final token = await FCMService.getToken();
    if (token != null) auth.updateFcmToken(token);

    if (!mounted) return;

    if (!auth.hasAcceptedTerms) {
      go(AppRoutes.terms);
      return;
    }

    // Deliberately no profile gate here.
    //
    // Signing up in the app means you are an emergency user — there is no role
    // to choose, and nothing about a photo or a phone number should stand
    // between someone and the SOS button. The home screen prompts for the
    // missing details instead, and keeps prompting until they are filled in.

    final currentIncidentId = auth.user?.currentIncidentId;
    if (currentIncidentId != null) {
      incidentProvider.streamActiveIncident(currentIncidentId);
    }

    final role = auth.user?.effectiveRole ?? AppRoles.user;
    go(AppRoles.isResponder(role)
        ? AppRoutes.responderHome
        : AppRoutes.userHome);
  }

  @override
  void dispose() {
    // Covers the case where something else (e.g. the global auth guard)
    // navigates away before _navigate() gets there.
    _removeNativeSplash();
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: AppColors.primary);
}
