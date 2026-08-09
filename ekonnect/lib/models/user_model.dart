import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String? teamId;
  final String? fcmToken;
  final double? lat;
  final double? lng;
  final bool isOnline;
  final bool isAvailable;
  final String? currentIncidentId;
  final String? profilePhoto;
  final String? licenseNumber;
  final String? specialization;
  final String? vehicleNumber;
  final bool profileComplete;
  final bool termsAccepted;
  final DateTime? createdAt;
  // null means use [role] as the active mode
  final String? activeMode;

  // ── Identity ──────────────────────────────────────────────────────────────

  /// Public handle, e.g. `EK-7H4K-2M9P`. Read out at a care centre desk.
  /// Safe to share — it identifies an account and confers nothing.
  final String? ekonnectId;

  /// National ID, used only as a lookup key against a provider's own roster.
  /// Never treated as proof of identity: anyone can type someone else's.
  final String? nationalId;

  /// Cached last four digits so a provider can recognise a record they already
  /// hold without the full number being exposed to them.
  final String? nationalIdLast4;

  // ── Admin-controlled responder fields ─────────────────────────────────────
  // Set when an admin issues an invitation and when they verify the claimant.
  // Never writable by the responder themselves.

  /// `ResponderVisibility.public` or `.private`. Null for ordinary users.
  final String? visibility;

  /// `VerificationStatus.*`. Null for ordinary users, who need no vetting.
  final String? verificationStatus;

  /// The body this responder answers for, e.g. "Kakamega County Ambulance".
  final String? organisation;

  /// Admin uid and timestamp of the last verification decision, plus the
  /// reason shown to the responder if they were rejected or suspended.
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? verificationNote;

  /// The mode currently active for routing/UI. A practitioner can set this
  /// to 'user' to access the emergency SOS screen without changing their role.
  String get effectiveRole => activeMode ?? role;

  bool get isAdmin => role == AppRoles.admin;

  // ── Profile completeness ──────────────────────────────────────────────────
  // Signing up no longer forces a setup form, so the app has to know what is
  // still missing in order to keep asking for it.

  bool get hasPhoto => (profilePhoto ?? '').isNotEmpty;
  bool get hasPhone => phone.trim().length >= 9;
  bool get hasName => name.trim().isNotEmpty;

  /// Whether the user has said who should respond to them — the public network
  /// or a private provider they are registered with.
  bool get hasChosenResponders => (visibility ?? '').isNotEmpty;

  /// The steps still outstanding, in the order worth asking for them.
  ///
  /// Phone comes first because a responder cannot call a patient without it;
  /// a photo is last because it is the least operationally important.
  List<String> get missingProfileSteps => [
        if (!hasName) 'Your name',
        if (!hasPhone) 'Phone number',
        if (!hasChosenResponders) 'Who responds to you',
        if (!hasPhoto) 'Profile photo',
      ];

  /// 0.0–1.0, for the progress ring on the home prompt.
  double get profileProgress {
    const total = 4;
    return (total - missingProfileSteps.length) / total;
  }

  bool get isProfileComplete => missingProfileSteps.isEmpty;

  /// Whether this responder may accept emergencies. Ordinary users are
  /// unaffected; responders must have been verified by an admin.
  bool get canRespond =>
      AppRoles.isResponder(role) &&
      VerificationStatus.canGoOnDuty(verificationStatus);

  bool get isPrivateResponder => visibility == ResponderVisibility.private;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.teamId,
    this.fcmToken,
    this.lat,
    this.lng,
    this.isOnline = false,
    this.isAvailable = false,
    this.currentIncidentId,
    this.profilePhoto,
    this.licenseNumber,
    this.specialization,
    this.vehicleNumber,
    this.profileComplete = false,
    this.termsAccepted = false,
    this.createdAt,
    this.activeMode,
    this.ekonnectId,
    this.nationalId,
    this.nationalIdLast4,
    this.visibility,
    this.verificationStatus,
    this.organisation,
    this.verifiedBy,
    this.verifiedAt,
    this.verificationNote,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'] ?? 'user',
      activeMode: map['activeMode'] as String?,
      teamId: map['teamId'],
      fcmToken: map['fcmToken'],
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      isOnline: map['isOnline'] ?? false,
      isAvailable: map['isAvailable'] ?? false,
      currentIncidentId: map['currentIncidentId'],
      profilePhoto: map['profilePhoto'],
      licenseNumber: map['licenseNumber'],
      specialization: map['specialization'],
      vehicleNumber: map['vehicleNumber'],
      profileComplete: map['profileComplete'] ?? false,
      termsAccepted: map['termsAccepted'] ?? false,
      createdAt: _parseDate(map['createdAt']),
      ekonnectId: map['ekonnectId'],
      nationalId: map['nationalId'],
      nationalIdLast4: map['nationalIdLast4'],
      visibility: map['visibility'],
      verificationStatus: map['verificationStatus'],
      organisation: map['organisation'],
      verifiedBy: map['verifiedBy'],
      verifiedAt: _parseDate(map['verifiedAt']),
      verificationNote: map['verificationNote'],
    );
  }

  /// Tolerant date parsing — Firestore docs written by different clients have
  /// stored createdAt as a Timestamp, an ISO-8601 String, or epoch millis.
  /// A single bad cast here used to crash the whole user stream (and block
  /// login routing), so we accept all three and fall back to null.
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'teamId': teamId,
        'fcmToken': fcmToken,
        'lat': lat,
        'lng': lng,
        'isOnline': isOnline,
        'isAvailable': isAvailable,
        'currentIncidentId': currentIncidentId,
        'profilePhoto': profilePhoto,
        'licenseNumber': licenseNumber,
        'specialization': specialization,
        'vehicleNumber': vehicleNumber,
        'profileComplete': profileComplete,
        'termsAccepted': termsAccepted,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
        'activeMode': activeMode,
        'ekonnectId': ekonnectId,
        'nationalId': nationalId,
        'nationalIdLast4': nationalIdLast4,
        'visibility': visibility,
        'verificationStatus': verificationStatus,
        'organisation': organisation,
        'verifiedBy': verifiedBy,
        'verifiedAt': verifiedAt != null ? Timestamp.fromDate(verifiedAt!) : null,
        'verificationNote': verificationNote,
      };

  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? role,
    String? teamId,
    String? fcmToken,
    double? lat,
    double? lng,
    bool? isOnline,
    bool? isAvailable,
    String? currentIncidentId,
    String? profilePhoto,
    String? licenseNumber,
    String? specialization,
    String? vehicleNumber,
    bool? profileComplete,
    bool? termsAccepted,
    Object? activeMode = _sentinel,
  }) =>
      UserModel(
        uid: uid,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role ?? this.role,
        teamId: teamId ?? this.teamId,
        fcmToken: fcmToken ?? this.fcmToken,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        isOnline: isOnline ?? this.isOnline,
        isAvailable: isAvailable ?? this.isAvailable,
        currentIncidentId: currentIncidentId ?? this.currentIncidentId,
        profilePhoto: profilePhoto ?? this.profilePhoto,
        licenseNumber: licenseNumber ?? this.licenseNumber,
        specialization: specialization ?? this.specialization,
        vehicleNumber: vehicleNumber ?? this.vehicleNumber,
        profileComplete: profileComplete ?? this.profileComplete,
        termsAccepted: termsAccepted ?? this.termsAccepted,
        createdAt: createdAt,
        activeMode: activeMode == _sentinel ? this.activeMode : activeMode as String?,
      );

  static const Object _sentinel = Object();

  String get displayName => name.isNotEmpty ? name : email;
}
