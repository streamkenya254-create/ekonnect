import 'dart:async';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/firestore_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _userSub;
  // True while an auth flow is in progress (OTP entry, etc.) so _AuthGuard
  // doesn't redirect to login during the unauthenticated window.
  bool _authFlowActive = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  /// True if Firebase Auth has a current user (even before Firestore doc loads).
  bool get hasFirebaseUser => AuthService.currentUser != null;
  bool get authFlowActive => _authFlowActive;
  bool get hasAcceptedTerms => _user?.termsAccepted ?? false;
  bool get hasCompletedProfile => _user?.profileComplete ?? false;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    AuthService.authStateChanges.listen((firebaseUser) {
      if (firebaseUser == null) {
        _userSub?.cancel();
        _userSub = null;
        _user = null;
        _isLoading = false;
        notifyListeners();
        return;
      }
      // Firebase has a user — subscribe to their Firestore doc.
      // Keep _isLoading=true until the doc actually arrives so the auth guard
      // never sees the transient (isLoading=false, user=null) state that would
      // cause a spurious redirect to the login screen.
      _userSub?.cancel();
      _userSub = FirestoreService.streamUser(firebaseUser.uid).listen(
        (u) {
          _user = u;
          if (u != null) _isLoading = false; // only mark done when doc exists
          notifyListeners();
        },
        onError: (e) {
          // A malformed user document must not brick the app on an infinite
          // spinner. Surface an error and stop loading so the UI can recover.
          _error = 'Could not load your profile. Please try again.';
          _isLoading = false;
          notifyListeners();
        },
      );
    });
  }

  Future<void> signInWithGoogle() async {
    _setLoading(true);
    _error = null;
    try {
      final cred = await AuthService.signInWithGoogle();
      final firebaseUser = cred.user!;
      final existing = await FirestoreService.getUser(firebaseUser.uid);
      if (existing == null) {
        final token = await FCMService.getToken();
        await FirestoreService.createUser(UserModel(
          uid: firebaseUser.uid,
          name: firebaseUser.displayName ?? '',
          email: firebaseUser.email ?? '',
          phone: firebaseUser.phoneNumber ?? '',
          role: 'user',
          fcmToken: token,
          profileComplete: false,
          termsAccepted: false,
        ));
      } else {
        final token = await FCMService.getToken();
        if (token != null && token != existing.fcmToken) {
          await FirestoreService.updateUser(firebaseUser.uid, {'fcmToken': token});
        }
      }
    } catch (e) {
      // User backing out of the Google account picker isn't an error worth
      // showing — just quietly return to the login screen.
      if (_isCancellation(e.toString())) {
        _error = null;
      } else {
        _error = _friendlyAuthError(e.toString());
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signInWithEmail(
      {required String email, required String password}) async {
    _setLoading(true);
    _error = null;
    try {
      final cred = await AuthService.signInWithEmail(email, password);
      final firebaseUser = cred.user!;
      final existing = await FirestoreService.getUser(firebaseUser.uid);
      if (existing == null) {
        final token = await FCMService.getToken();
        await FirestoreService.createUser(UserModel(
          uid: firebaseUser.uid,
          name: firebaseUser.displayName ?? email.split('@').first,
          email: firebaseUser.email ?? '',
          phone: '',
          role: 'user',
          fcmToken: token,
          profileComplete: false,
          termsAccepted: false,
        ));
      }
    } catch (e) {
      _error = _friendlyAuthError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signUpWithEmail(
      {required String name,
      required String email,
      required String password}) async {
    _setLoading(true);
    _error = null;
    try {
      final cred = await AuthService.signUpWithEmail(email, password);
      final firebaseUser = cred.user!;
      await firebaseUser.updateDisplayName(name);
      final token = await FCMService.getToken();
      await FirestoreService.createUser(UserModel(
        uid: firebaseUser.uid,
        name: name,
        email: email,
        phone: '',
        role: 'user',
        fcmToken: token,
        profileComplete: false,
        termsAccepted: false,
      ));
    } catch (e) {
      _error = _friendlyAuthError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Sends a password-reset email. Returns true on success, false on failure
  /// (with [error] populated). We intentionally treat "user-not-found" as a
  /// success at the UI layer to avoid leaking which emails have accounts —
  /// see the login screen's forgot-password handler.
  Future<bool> sendPasswordReset(String email) async {
    _error = null;
    try {
      await AuthService.sendPasswordReset(email.trim());
      return true;
    } catch (e) {
      final raw = e.toString();
      // Report "no such account" as success so the screen shows the same
      // neutral "check your inbox" message either way — this prevents email
      // enumeration (probing which addresses have accounts).
      if (raw.contains('user-not-found')) return true;
      _error = _friendlyAuthError(raw);
      notifyListeners();
      return false;
    }
  }

  bool _isCancellation(String raw) {
    return raw.contains('sign-in cancelled') ||
        raw.contains('sign_in_canceled') ||
        raw.contains('canceled') ||
        raw.contains('cancelled') ||
        raw.contains('ERROR_ABORTED_BY_USER');
  }

  String _friendlyAuthError(String raw) {
    if (raw.contains('user-not-found') || raw.contains('wrong-password') ||
        raw.contains('invalid-credential')) {
      return 'Invalid email or password.';
    }
    if (raw.contains('email-already-in-use')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (raw.contains('user-disabled')) {
      return 'This account has been disabled. Contact support.';
    }
    if (raw.contains('too-many-requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (raw.contains('operation-not-allowed')) {
      return 'This sign-in method is not enabled. Try another option.';
    }
    if (raw.contains('account-exists-with-different-credential')) {
      return 'This email is linked to a different sign-in method.';
    }
    if (raw.contains('requires-recent-login')) {
      return 'Please sign in again to continue.';
    }
    if (raw.contains('weak-password')) return 'Password is too weak.';
    if (raw.contains('invalid-email')) return 'Invalid email address.';
    if (raw.contains('network-request-failed') || raw.contains('network')) {
      return 'No internet connection. Check your network and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  // Returns verificationId; caller shows OTP screen.
  // Returns '__auto__' when Android auto-verifies (no OTP needed).
  // Sets _authFlowActive so _AuthGuard doesn't redirect during OTP entry.
  Future<String> startPhoneSignIn(String phoneNumber) async {
    _authFlowActive = true;
    _setLoading(true);
    try {
      final result = await AuthService.startPhoneVerification(phoneNumber);

      if (result == '__auto__') {
        // Android auto-verified: ensure Firestore user doc exists.
        final firebaseUser = AuthService.currentUser;
        if (firebaseUser != null) {
          final existing = await FirestoreService.getUser(firebaseUser.uid);
          if (existing == null) {
            final token = await FCMService.getToken();
            await FirestoreService.createUser(UserModel(
              uid: firebaseUser.uid,
              name: firebaseUser.displayName ?? '',
              email: firebaseUser.email ?? '',
              phone: firebaseUser.phoneNumber ?? phoneNumber,
              role: 'user',
              fcmToken: token,
              profileComplete: false,
              termsAccepted: false,
            ));
          }
        }
        _authFlowActive = false; // done — no OTP screen needed
      }

      return result;
    } catch (e) {
      _authFlowActive = false;
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> verifyOTP(String verificationId, String otp) async {
    _setLoading(true);
    try {
      final cred = await AuthService.verifyOTP(verificationId, otp);
      final firebaseUser = cred.user!;
      final existing = await FirestoreService.getUser(firebaseUser.uid);
      if (existing == null) {
        final token = await FCMService.getToken();
        await FirestoreService.createUser(UserModel(
          uid: firebaseUser.uid,
          name: firebaseUser.displayName ?? '',
          email: firebaseUser.email ?? '',
          phone: firebaseUser.phoneNumber ?? '',
          role: 'user',
          fcmToken: token,
          profileComplete: false,
          termsAccepted: false,
        ));
      }
      // Only clear the flow guard on SUCCESS so that an invalid OTP doesn't
      // evict the PhoneAuthScreen before the user sees the error message.
      _authFlowActive = false;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> acceptTerms() async {
    if (_user == null) return;
    await FirestoreService.updateUser(_user!.uid, {'termsAccepted': true});
  }

  Future<void> setRole(String role) async {
    if (_user == null) return;
    await FirestoreService.updateUser(_user!.uid, {'role': role});
  }

  /// Switch the active mode without changing the registered role.
  /// Pass null to go back to the user's primary registered role.
  /// Pass [AppRoles.user] to enter user/emergency mode.
  Future<void> switchMode(String? mode) async {
    if (_user == null) return;
    final updates = <String, dynamic>{'activeMode': mode};
    // Go off duty when switching away from responder mode
    if (mode == AppRoles.user && _user!.isAvailable) {
      updates['isAvailable'] = false;
    }
    await FirestoreService.updateUser(_user!.uid, updates);
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    if (_user == null) return;
    data['profileComplete'] = true;
    await FirestoreService.updateUser(_user!.uid, data);
  }

  Future<void> updateFcmToken(String token) async {
    if (_user == null) return;
    await FirestoreService.updateUser(_user!.uid, {'fcmToken': token});
  }

  Future<void> signOut() async {
    if (_user != null) {
      await FirestoreService.setOnlineStatus(_user!.uid, isOnline: false);
    }
    await AuthService.signOut();
    _user = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }
}
