import 'package:flutter/material.dart';

/// Names, routes and domain vocabulary.
///
/// Everything visual — colour, type, spacing, shape — lives in theme.dart
/// and is re-exported here, so the hundred screens that already import this
/// file keep AppColors and AppText in scope without an extra import.
export 'theme.dart';
import 'theme.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const userHome = '/user/home';
  static const sosWaiting = '/user/sos';
  static const incidentHistory = '/user/history';
  static const responderHome = '/responder/home';
  static const incidentCard = '/responder/incident';
  static const activeJob = '/responder/active';
  static const chat = '/chat';
  static const profile = '/profile';
  static const settings = '/settings';
  static const tutorial = '/tutorial';
  static const aiChat = '/ai-chat';
  static const myProviders = '/my-providers';
  static const notifications = '/notifications';
}

class AppRoles {
  static const user = 'user';
  static const ambulance = 'ambulance';
  static const practitioner = 'practitioner';
  static const admin = 'admin';

  static bool isResponder(String role) =>
      role == ambulance || role == practitioner;

  static String displayLabel(String role) {
    switch (role) {
      case user: return 'Emergency User';
      case ambulance: return 'Ambulance Driver';
      case practitioner: return 'Medical Practitioner';
      default: return 'User';
    }
  }
}

class IncidentType {
  static const medical = 'medical';
  static const fire = 'fire';
  static const flood = 'flood';
  static const security = 'security';

  static String label(String type) {
    switch (type) {
      case medical: return 'Medical Emergency';
      case fire: return 'Fire Incident';
      case flood: return 'Flood / Disaster';
      case security: return 'Security / Police';
      default: return type;
    }
  }

  static Color color(String type) {
    switch (type) {
      case medical: return AppColors.medicalColor;
      case fire: return AppColors.fireColor;
      case flood: return AppColors.floodColor;
      case security: return AppColors.securityColor;
      default: return AppColors.primary;
    }
  }

  static IconData icon(String type) {
    switch (type) {
      case medical: return Icons.medical_services;
      case fire: return Icons.local_fire_department;
      case flood: return Icons.water;
      case security: return Icons.security;
      default: return Icons.warning;
    }
  }
}

class IncidentStatus {
  static const pending = 'pending';
  static const assigned = 'assigned';
  static const enRoute = 'en_route';
  static const arrived = 'arrived';
  static const resolved = 'resolved';
  static const cancelled = 'cancelled';

  /// A crew attended and could not finish the job — no ambulance available for
  /// transport, patient refused care, wrong address.
  ///
  /// Deliberately not `cancelled`. A cancel means nothing was needed; this
  /// means something was needed and the network did not deliver it. Filing
  /// both in one bucket would hide exactly the failures worth measuring.
  static const closedUnresolved = 'closed_unresolved';

  /// Statuses after which nobody may accept, re-open or act on the incident.
  static const closed = [resolved, cancelled, closedUnresolved];

  static bool isClosed(String? status) => closed.contains(status);

  static String label(String status) {
    switch (status) {
      case pending: return 'Waiting for responder…';
      case assigned: return 'Responder assigned';
      case enRoute: return 'Responder on the way';
      case arrived: return 'Responder arrived';
      case resolved: return 'Incident resolved';
      case cancelled: return 'Cancelled';
      case closedUnresolved: return 'Closed — not resolved';
      default: return status;
    }
  }
}

class AssignmentMode {
  static const firstAccept = 'first_accept';
  static const autoNearest = 'auto_nearest';
}

class Collections {
  static const users = 'users';
  static const incidents = 'incidents';
  static const teams = 'teams';
  static const messages = 'messages';
  static const appConfig = 'appConfig';

  /// Clients registered with a private provider. A private team only answers
  /// calls from people who appear here.
  static const subscriptions = 'subscriptions';

  /// A kept copy of each push, so a missed banner is still findable.
  static const notifications = 'notifications';
}

/// Who a responder is allowed to serve.
///
/// This is the core of the admin decision: an unvetted stranger must never be
/// able to put themselves on the public emergency network, and a private
/// provider must not receive calls from the general public.
class ResponderVisibility {
  /// Part of the open emergency network — eligible for any nearby SOS.
  /// County ambulances, public hospitals, fire service.
  static const public = 'public';

  /// Serves only their own organisation's people, or incidents an admin
  /// assigns directly. Company medics, private hospital fleets.
  static const private = 'private';

  /// Narrower still: only the specific clients on their Care Point's list, and
  /// never the open network — not even when a private call is opened to the
  /// public after its exclusivity window expires.
  ///
  /// This is the difference a retained corporate crew pays for: they are never
  /// pulled onto a passing road traffic accident.
  static const clients = 'clients';

  static const values = [public, private, clients];

  /// Scopes that never see an open-network call.
  static bool isExclusive(String? v) => v == private || v == clients;

  static String label(String? v) {
    switch (v) {
      case private: return 'Private responder';
      case clients: return 'Named clients only';
      default: return 'Public responder';
    }
  }

  static String describe(String? v) {
    switch (v) {
      case private:
        return 'Only receives calls from their own organisation, or ones an '
            'admin assigns directly.';
      case clients:
        return 'Only receives calls from clients on their Care Point list. '
            'Never joins the open network.';
      default:
        return 'Receives any nearby emergency on the public network.';
    }
  }

  static IconData icon(String? v) {
    switch (v) {
      case private: return Icons.business_rounded;
      case clients: return Icons.workspace_premium_rounded;
      default: return Icons.public_rounded;
    }
  }
}

/// Where a responder sits in the admin approval pipeline.
class VerificationStatus {
  /// Claimed an invite; documents not yet checked. Cannot go on duty.
  static const pending = 'pending';

  /// Admin confirmed identity and credentials. Can go on duty.
  static const verified = 'verified';

  /// Admin declined. Cannot go on duty, and is told why.
  static const rejected = 'rejected';

  /// Was verified, now withdrawn — e.g. a lapsed licence.
  static const suspended = 'suspended';

  static bool canGoOnDuty(String? status) => status == verified;

  static String label(String? s) {
    switch (s) {
      case verified:
        return 'Verified';
      case rejected:
        return 'Rejected';
      case suspended:
        return 'Suspended';
      default:
        return 'Awaiting verification';
    }
  }

  static Color color(String? s) {
    switch (s) {
      case verified:
        return AppColors.success;
      case rejected:
      case suspended:
        return AppColors.emergency;
      default:
        return AppColors.accent;
    }
  }
}

/// How an emergency actually ended.
///
/// The status field alone cannot answer "did this person get help?" — a
/// cancelled call and one where the crew arrived to find the patient fine are
/// both "not resolved", but they mean opposite things operationally. Recording
/// the outcome separately is what makes a response rate meaningful.
class IncidentOutcome {
  /// Care was delivered by the responder.
  static const treated = 'treated';

  /// Crew arrived, help was no longer needed. The "I'm OK on arrival" case.
  static const stoodDown = 'stood_down';

  /// Handed over to a care point — hospital, clinic, fire station.
  static const referred = 'referred';

  /// Ended by the caller before any responder arrived.
  static const cancelledByUser = 'cancelled_by_user';

  /// The assigned responder could not continue.
  static const cancelledByResponder = 'cancelled_by_responder';

  /// Nobody accepted it in time.
  static const noResponder = 'no_responder';

  static String label(String? o) {
    switch (o) {
      case treated:
        return 'Treated on scene';
      case stoodDown:
        return 'Stood down — help not needed';
      case referred:
        return 'Referred to a care point';
      case cancelledByUser:
        return 'Cancelled by caller';
      case cancelledByResponder:
        return 'Responder unavailable';
      case noResponder:
        return 'No responder available';
      default:
        return 'Closed';
    }
  }

  /// Outcomes that count as the system having worked.
  static bool isSuccessful(String? o) =>
      o == treated || o == stoodDown || o == referred;
}

/// A client's registration with a private provider.
class SubscriptionStatus {
  static const active = 'active';
  static const expired = 'expired';
  static const cancelled = 'cancelled';
}

/// One selectable answer to "why are you cancelling?".
class CancelReasonOption {
  final String code;
  final String label;
  final String hint;
  final IconData icon;

  const CancelReasonOption(this.code, this.label, this.hint, this.icon);
}

/// Why an SOS ended early. Persisted on the incident as `cancelReason` so
/// cancellations can be told apart afterwards — an accidental press is a very
/// different signal from "found help elsewhere", and lumping them together
/// hides both.
class CancelReasons {
  // ── User-selected ────────────────────────────────────────────────────────
  static const accidental = 'accidental';
  static const imOk = 'im_ok';
  static const foundOtherHelp = 'found_other_help';
  static const goingMyself = 'going_myself';
  static const wrongType = 'wrong_type';
  static const other = 'other';

  // ── Recorded by the app, not chosen by the user ──────────────────────────
  static const noResponder = 'no_responder';
  static const responderCancelled = 'responder_cancelled';
  static const rebroadcast = 'rebroadcast';

  /// Offered to the user, in display order.
  static const options = <CancelReasonOption>[
    CancelReasonOption(
      accidental,
      'Pressed by accident',
      'The SOS button was triggered without me meaning to',
      Icons.touch_app_outlined,
    ),
    CancelReasonOption(
      imOk,
      "I'm OK now",
      'The emergency has passed — I no longer need help',
      Icons.check_circle_outline,
    ),
    CancelReasonOption(
      foundOtherHelp,
      'Found help another way',
      'Someone else is already assisting',
      Icons.volunteer_activism_outlined,
    ),
    CancelReasonOption(
      goingMyself,
      'Making my own way',
      'I am heading to a hospital or clinic myself',
      Icons.directions_car_outlined,
    ),
    CancelReasonOption(
      wrongType,
      'Wrong emergency type',
      'I picked the wrong category and will start again',
      Icons.swap_horiz_rounded,
    ),
    CancelReasonOption(
      other,
      'Another reason',
      'Tell us briefly what happened',
      Icons.more_horiz_rounded,
    ),
  ];

  /// Human-readable label for any stored code, including the system ones.
  static String label(String? code) {
    if (code == null || code.isEmpty) return 'No reason given';
    for (final o in options) {
      if (o.code == code) return o.label;
    }
    switch (code) {
      case noResponder:
        return 'No responder available';
      case responderCancelled:
        return 'Responder became unavailable';
      case rebroadcast:
        return 'Re-broadcast as a new SOS';
      default:
        return 'No reason given';
    }
  }
}
