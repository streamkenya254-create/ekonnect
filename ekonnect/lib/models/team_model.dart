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
  });

  bool get isPrivate => visibility == ResponderVisibility.private;

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
