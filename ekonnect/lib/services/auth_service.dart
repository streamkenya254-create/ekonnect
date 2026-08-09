import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _googleSignIn = GoogleSignIn();

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static Future<UserCredential> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled');
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  // Returns verificationId for OTP confirmation, or '__auto__' when Android
  // auto-verifies without needing an OTP. Uses a Completer so:
  //   • verificationFailed errors actually propagate to the caller
  //   • codeSent is awaited properly instead of relying on a timing hack
  static Future<String> startPhoneVerification(String phoneNumber) {
    final completer = Completer<String>();

    _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android instant-verification: Firebase signs in automatically.
        try {
          await _auth.signInWithCredential(credential);
        } catch (_) {}
        if (!completer.isCompleted) completer.complete('__auto__');
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      codeSent: (String vId, int? resendToken) {
        if (!completer.isCompleted) completer.complete(vId);
      },
      codeAutoRetrievalTimeout: (_) {},
    );

    return completer.future;
  }

  static Future<UserCredential> verifyOTP(
      String verificationId, String otp) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    return _auth.signInWithCredential(credential);
  }

  static Future<UserCredential> signInWithEmail(
      String email, String password) async {
    return _auth.signInWithEmailAndPassword(
        email: email, password: password);
  }

  static Future<UserCredential> signUpWithEmail(
      String email, String password) async {
    return _auth.createUserWithEmailAndPassword(
        email: email, password: password);
  }

  static Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
