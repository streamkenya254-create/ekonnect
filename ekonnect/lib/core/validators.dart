/// Lightweight, dependency-free input validation for auth forms.
///
/// Validators return `null` when the value is acceptable, or a short,
/// user-facing error message when it isn't.
class Validators {
  Validators._();

  // Reasonable, pragmatic email pattern — not RFC-perfect, but rejects the
  // obviously-malformed values before we spend a round-trip on Firebase.
  static final RegExp _emailRegExp = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$",
  );

  static const int minPasswordLength = 6;

  static bool isValidEmail(String email) =>
      _emailRegExp.hasMatch(email.trim());

  /// Returns an error message for an email field, or null if valid.
  static String? email(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Please enter your email.';
    if (!isValidEmail(email)) return 'Enter a valid email address.';
    return null;
  }

  /// Returns an error message for a password field, or null if valid.
  /// [requireStrong] applies the sign-up length rule; sign-in only checks
  /// that something was entered (Firebase decides if it's correct).
  static String? password(String? value, {bool requireStrong = false}) {
    final password = value ?? '';
    if (password.isEmpty) return 'Please enter your password.';
    if (requireStrong && password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters.';
    }
    return null;
  }

  /// Returns an error message for a name field, or null if valid.
  static String? name(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Please enter your name.';
    if (name.length < 2) return 'Please enter your full name.';
    return null;
  }
}
