import 'dart:math';

/// How a person is identified across eKonnect, providers and care centres.
///
/// The design separates two things that are easy to conflate and dangerous to
/// mix up:
///
///   * an **identifier** says who someone *claims* to be. It is memorable,
///     searchable, and can be typed by anybody — including someone typing a
///     stranger's details. A national ID is an identifier.
///
///   * a **credential** proves the claim. It is held only by the real person,
///     or asserted by a party who can actually check.
///
/// A national ID number is therefore never treated as proof of anything here.
/// It is a lookup key, exactly as it is at a hospital reception desk, and the
/// proof always comes from somewhere else.
class Identity {
  Identity._();

  // ── eKonnect ID ───────────────────────────────────────────────────────────

  /// Ambiguous characters are excluded: no O/0, I/1, S/5, Z/2. These IDs get
  /// read aloud over a phone and copied off a screen by hand at a reception
  /// desk, where a misread character means the wrong patient.
  static const _alphabet = '34679ACDEFGHJKLMNPQRTUVWXY';

  /// A public handle for a person, e.g. `EK-7H4K-2M9P`.
  ///
  /// Safe to share: it identifies an eKonnect account and nothing else. Knowing
  /// someone's eKonnect ID does not let you act as them, which is precisely
  /// what makes it the right thing to read out at a care centre desk.
  static String generateEkonnectId([Random? rng]) {
    final r = rng ?? Random.secure();
    String block() => List.generate(
          4,
          (_) => _alphabet[r.nextInt(_alphabet.length)],
        ).join();
    return 'EK-${block()}-${block()}';
  }

  static final _ekPattern = RegExp(r'^EK-[A-Z0-9]{4}-[A-Z0-9]{4}$');

  static bool isValidEkonnectId(String? id) =>
      id != null && _ekPattern.hasMatch(id.trim().toUpperCase());

  /// Accepts what a human types — lowercase, missing dashes, stray spaces —
  /// and returns the canonical form, or null if it cannot be one.
  static String? normaliseEkonnectId(String input) {
    var s = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.startsWith('EK')) s = s.substring(2);
    if (s.length != 8) return null;
    final id = 'EK-${s.substring(0, 4)}-${s.substring(4)}';
    return isValidEkonnectId(id) ? id : null;
  }

  // ── National ID ───────────────────────────────────────────────────────────

  /// Kenyan national ID numbers are 7–9 digits.
  static bool isPlausibleNationalId(String? value) {
    if (value == null) return false;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 7 && digits.length <= 9;
  }

  static String digitsOnly(String value) =>
      value.replaceAll(RegExp(r'\D'), '');

  /// What a provider sees before a match is confirmed: `••••4821`.
  ///
  /// Enough to recognise a record they already hold, never enough to copy down
  /// and reuse. The full number is only ever revealed to a provider once the
  /// link between person and provider has been established.
  static String maskNationalId(String? value) {
    final d = value == null ? '' : digitsOnly(value);
    if (d.length < 4) return '••••';
    return '••••${d.substring(d.length - 4)}';
  }

  static String? last4(String? value) {
    final d = value == null ? '' : digitsOnly(value);
    return d.length < 4 ? null : d.substring(d.length - 4);
  }
}

/// How a person came to be linked to a provider. Recorded on the subscription
/// so any link can be audited later and, if necessary, undone.
class LinkMethod {
  /// The provider already had them on their roster; the person confirmed by
  /// entering a code sent to the number the *provider* holds.
  static const rosterMatch = 'roster_match';

  /// The person asked to join and a provider staff member approved them
  /// against their own records.
  static const providerApproved = 'provider_approved';

  /// An eKonnect administrator linked them directly — used for corrections,
  /// and always attributable.
  static const adminOverride = 'admin_override';

  static String label(String? m) {
    switch (m) {
      case rosterMatch:
        return 'Matched to provider roster';
      case providerApproved:
        return 'Approved by provider';
      case adminOverride:
        return 'Linked by eKonnect admin';
      default:
        return 'Unlinked';
    }
  }
}

/// Where a request to join a provider currently sits.
class LinkStatus {
  /// Person asked to join; the provider has not yet decided.
  static const requested = 'requested';

  /// The provider's roster matched, but the one-time code has not been
  /// confirmed yet. No cover is active in this state.
  static const awaitingCode = 'awaiting_code';

  /// Linked and covered.
  static const active = 'active';

  static const rejected = 'rejected';
  static const revoked = 'revoked';

  static bool isCovered(String? s) => s == active;
}
