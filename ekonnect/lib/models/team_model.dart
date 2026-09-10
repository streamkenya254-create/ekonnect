import '../core/constants.dart';

/// A responder organisation — a county ambulance service, a private hospital
/// fleet, a company's on-site medics. Created and owned by admins; responders
/// are attached to one via their `teamId`.
class TeamModel {
  final String id;
  final String name;
  final String color;
  final String icon;
  final List<String> respondsTo;
  final String assignmentMode;
  final List<String> memberIds;

  /// `ResponderVisibility.public` or `.private`.
  ///
  /// Public teams answer any nearby emergency. Private teams answer only their
  /// own subscribers — which is the whole point of letting a company register
  /// clients: those clients get their provider dispatched directly.
  final String visibility;

  /// Contact shown to a subscriber, and used on the responder's profile.
  final String? contactPhone;

  /// The 3am line, when the facility keeps one separate from reception.
  final String? dispatchPhone;

  /// `verified` once an administrator has checked the licence. Nothing else
  /// should ever be offered to a subscriber.
  final String? verificationStatus;

  final String? description;
  final String? county;
  final String? town;
  final String? type;
  final List<String> services;

  /// False when they are full. A provider that cannot take a case is worse
  /// than useless to a subscriber who thinks they can.
  final bool acceptingCases;
  final bool open24Hours;

  /// What this facility charges its own subscribers, and how to pay it.
  ///
  /// eKonnect collects nothing and processes nothing: money goes straight
  /// to the facility, so all the app can do is show the client where to
  /// send it. Any of these may be blank on a Care Point that has not filled
  /// them in, and the UI has to survive that.
  final String? coverPrice;
  final String? coverDays;
  final String? payBill;
  final String? payAccount;

  const TeamModel({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    required this.respondsTo,
    this.assignmentMode = 'first_accept',
    this.memberIds = const [],
    this.visibility = ResponderVisibility.public,
    this.contactPhone,
    this.dispatchPhone,
    this.verificationStatus,
    this.description,
    this.county,
    this.town,
    this.type,
    this.services = const [],
    this.acceptingCases = true,
    this.open24Hours = false,
    this.coverPrice,
    this.coverDays,
    this.payBill,
    this.payAccount,
  });

  bool get isPrivate => visibility == ResponderVisibility.private;

  /// True when a subscriber can actually be told how to pay them.
  bool get hasPaymentDetails => (payBill ?? '').trim().isNotEmpty;

  bool get isVerified => verificationStatus == 'verified';

  /// Where they are, in the one line a subscriber cares about.
  String get placeLabel {
    final parts = [town, county].where((p) => (p ?? '').isNotEmpty);
    return parts.isEmpty ? '' : parts.join(', ');
  }

  factory TeamModel.fromMap(String id, Map<String, dynamic> map) {
    return TeamModel(
      id: id,
      name: map['name'] ?? '',
      color: map['color'] ?? '#1B4080',
      icon: map['icon'] ?? 'shield',
      respondsTo: List<String>.from(map['respondsTo'] ?? []),
      assignmentMode: map['assignmentMode'] ?? 'first_accept',
      memberIds: List<String>.from(map['memberIds'] ?? []),
      // Default to public so teams created before this field existed keep
      // behaving exactly as they did.
      visibility: map['visibility'] ?? ResponderVisibility.public,
      contactPhone: map['contactPhone'],
      dispatchPhone: map['dispatchPhone'],
      verificationStatus: map['verificationStatus'],
      description: map['description'],
      county: map['county'],
      town: map['town'],
      type: map['type'],
      services: List<String>.from(map['services'] ?? const []),
      acceptingCases: map['acceptingCases'] ?? true,
      open24Hours: map['open24Hours'] ?? false,
      // Written as text by the console's number inputs.
      coverPrice: map['coverPrice']?.toString(),
      coverDays: map['coverDays']?.toString(),
      payBill: map['payBill']?.toString(),
      payAccount: map['payAccount']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'color': color,
        'icon': icon,
        'respondsTo': respondsTo,
        'assignmentMode': assignmentMode,
        'memberIds': memberIds,
        'visibility': visibility,
        'contactPhone': contactPhone,
      };

  TeamModel copyWith({
    String? name,
    String? color,
    String? icon,
    List<String>? respondsTo,
    String? assignmentMode,
    List<String>? memberIds,
    String? visibility,
    String? contactPhone,
  }) =>
      TeamModel(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        icon: icon ?? this.icon,
        respondsTo: respondsTo ?? this.respondsTo,
        assignmentMode: assignmentMode ?? this.assignmentMode,
        memberIds: memberIds ?? this.memberIds,
        visibility: visibility ?? this.visibility,
        contactPhone: contactPhone ?? this.contactPhone,
      );
}
