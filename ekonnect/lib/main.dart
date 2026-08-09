import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/incident_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/profile_setup_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/auth/terms_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/responder/active_job_screen.dart';
import 'screens/responder/incident_card_screen.dart';
import 'screens/shared/chat_screen.dart';
import 'screens/shared/profile_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/ai/ai_chat_screen.dart';
import 'screens/user/incident_history_screen.dart';
import 'screens/user/my_providers_screen.dart';
import 'screens/user/settings_screen.dart';
import 'screens/user/sos_waiting_screen.dart';
import 'screens/user/tutorial_screen.dart';

@pragma('vm:entry-point')
Future<void> _bgMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Hold the native launch screen up through Firebase init and the auth
  // bootstrap in SplashScreen, which removes it before it navigates away.
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_bgMessageHandler);
  runApp(const EKonnectApp());
}

class EKonnectApp extends StatefulWidget {
  const EKonnectApp({super.key});
  @override
  State<EKonnectApp> createState() => _EKonnectAppState();
}

class _EKonnectAppState extends State<EKonnectApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, IncidentProvider>(
          create: (_) => IncidentProvider(),
          update: (_, auth, incident) => incident!..updateCurrentUser(auth.user),
        ),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'eKonnect',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: AppRoutes.splash,
        builder: (context, child) => _AuthGuard(
          navigatorKey: _navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        routes: {
          AppRoutes.splash: (_) => const SplashScreen(),
          AppRoutes.terms: (_) => const TermsScreen(),
          AppRoutes.login: (_) => const LoginScreen(),
          AppRoutes.roleSelect: (_) => const RoleSelectionScreen(),
          AppRoutes.profileSetup: (_) => const ProfileSetupScreen(),
          AppRoutes.userHome: (_) => const HomeShell(),
          AppRoutes.incidentHistory: (_) => const IncidentHistoryScreen(),
          AppRoutes.responderHome: (_) => const HomeShell(),
          AppRoutes.chat: (_) => const ChatScreen(),
          AppRoutes.profile: (_) => const ProfileScreen(),
          AppRoutes.settings: (_) => const SettingsScreen(),
          AppRoutes.tutorial: (_) => const TutorialScreen(),
          AppRoutes.aiChat: (_) => const AiChatScreen(),
          AppRoutes.myProviders: (_) => const MyProvidersScreen(),
        },
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case AppRoutes.phoneAuth:
              return MaterialPageRoute(
                builder: (_) => const LoginScreen(),
                settings: settings,
              );
            case AppRoutes.sosWaiting:
              final args = settings.arguments as Map<String, dynamic>;
              return MaterialPageRoute(
                builder: (_) => SOSWaitingScreen(
                  incidentType: args['type'] as String,
                  incidentId: args['incidentId'] as String,
                ),
              );
            case AppRoutes.incidentCard:
              return MaterialPageRoute(
                builder: (_) => IncidentCardScreen(
                  incidentId: settings.arguments as String,
                ),
              );
            case AppRoutes.activeJob:
              return MaterialPageRoute(
                builder: (_) => ActiveJobScreen(
                  incidentId: settings.arguments as String,
                ),
              );
            default:
              return MaterialPageRoute(builder: (_) => const SplashScreen());
          }
        },
      ),
    );
  }
}

// Watches auth globally and redirects to login when the user is definitively
// signed out. Uses a 600 ms debounce so transient states during sign-in
// (Firestore doc not yet created, token refresh, etc.) don't fire a redirect.
class _AuthGuard extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  const _AuthGuard({required this.navigatorKey, required this.child});

  @override
  State<_AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<_AuthGuard> {
  Timer? _redirectTimer;

  bool _shouldRedirect(AuthProvider auth) =>
      !auth.isLoading &&
      !auth.isAuthenticated &&
      !auth.hasFirebaseUser &&
      !auth.authFlowActive;

  /// Screens that are already part of signing in. Redirecting to login from any
  /// of these is pointless, and actively harmful on the login screen itself.
  static const _authRoutes = {
    AppRoutes.login,
    AppRoutes.phoneAuth,
    AppRoutes.terms,
    AppRoutes.roleSelect,
    AppRoutes.profileSetup,
    AppRoutes.splash,
  };

  /// Reads the name of the route currently on top. `popUntil` with an
  /// always-true predicate inspects without popping anything.
  String? _currentRouteName() {
    String? name;
    widget.navigatorKey.currentState?.popUntil((route) {
      name = route.settings.name;
      return true;
    });
    return name;
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_shouldRedirect(auth)) {
      // Schedule redirect only if one isn't already pending.
      _redirectTimer ??= Timer(const Duration(milliseconds: 600), () {
        _redirectTimer = null;
        if (!mounted) return;
        // Re-evaluate; state may have resolved during the debounce window.
        final a = context.read<AuthProvider>();
        if (!_shouldRedirect(a)) return;

        // Never redirect while the user is already in the sign-in flow.
        //
        // A failed login leaves exactly this state (not loading, not
        // authenticated, no Firebase user), so the guard used to rebuild
        // LoginScreen on top of itself ~600ms later — throwing away the error
        // message that had just been set. The result was a wrong password
        // silently clearing the form with no explanation at all.
        if (_authRoutes.contains(_currentRouteName())) return;

        widget.navigatorKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.login,
          (_) => false,
        );
      });
    } else {
      // Auth state is valid — cancel any pending redirect.
      _redirectTimer?.cancel();
      _redirectTimer = null;
    }

    return widget.child;
  }
}
