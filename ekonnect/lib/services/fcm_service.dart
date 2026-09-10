import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/constants.dart';
import '../firebase_options.dart';

/// Push notifications, end to end on the device side.
///
/// What this replaces: a stub that asked for permission, fetched a token and
/// `debugPrint`ed every message. On Android a foreground message displays
/// nothing on its own, so an approval or an incoming emergency arriving while
/// the app was open was silently swallowed — and a tap on a background
/// notification went nowhere.
///
/// Messages are sent **data-only** by the Cloud Functions, deliberately. A
/// `notification` payload is drawn by the OS before the app sees it, which
/// means no control over the channel, no deep link, and duplicate banners in
/// the foreground. Data-only puts every message through one path here.
class FCMService {
  FCMService._();

  static final _fcm = FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();

  /// Set by [main] so a tapped notification can navigate.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// High importance so an emergency actually interrupts. Must match the
  /// channel id declared in AndroidManifest for background messages.
  static const _channel = AndroidNotificationChannel(
    'ekonnect_alerts',
    'Emergency alerts',
    description: 'Incoming emergencies, approvals and job updates.',
    importance: Importance.max,
  );

  static bool _ready = false;

  static Future<String?> initialize() async {
    if (!_ready) {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);

      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload == null) return;
          _openFromData(
              Map<String, dynamic>.from(jsonDecode(r.payload!) as Map));
        },
      );

      // Foreground: the OS shows nothing, so draw it ourselves.
      FirebaseMessaging.onMessage.listen(_show);

      // Tapped while the app was backgrounded but alive.
      FirebaseMessaging.onMessageOpenedApp
          .listen((m) => _openFromData(m.data));

      // Tapped from cold start. Read once, after the tree is up.
      final initial = await _fcm.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _openFromData(initial.data));
      }

      _ready = true;
    }
    final token = await _fcm.getToken();
    // Printed in debug only: the token is what you address a test push to,
    // and there is otherwise no way to read it off the device.
    if (kDebugMode) debugPrint('FCM TOKEN: $token');
    return token;
  }

  static Future<String?> getToken() => _fcm.getToken();

  static Stream<String> get tokenRefreshStream => _fcm.onTokenRefresh;

  /// Drops this device's token.
  ///
  /// Called on sign-out. Without it, the next person to use a shared phone —
  /// a station tablet, a handed-over handset — keeps receiving the previous
  /// responder's emergencies.
  static Future<void> clearToken() async {
    try {
      await _fcm.deleteToken();
    } catch (_) {
      // Losing the token is not worth failing a sign-out over.
    }
  }

  /// Renders a data-only message as a system notification.
  static Future<void> _show(RemoteMessage message) async {
    final d = message.data;
    final title = d['title'] as String?;
    final body = d['body'] as String?;
    if (title == null && body == null) return;

    await _local.show(
      // Same id per subject collapses repeats: three status updates on one job
      // replace each other instead of stacking.
      id: (d['collapseId'] ??
              d['incidentId'] ??
              DateTime.now().millisecondsSinceEpoch)
          .hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          color: AppColors.primary,
          // An emergency should be readable without expanding it.
          styleInformation: BigTextStyleInformation(body ?? ''),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(d),
    );
  }

  /// Where a tap should land.
  ///
  /// The route travels in the message so a new kind of notification never
  /// needs an app release to be routable.
  static void _openFromData(Map<String, dynamic> data) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    final route = data['route'] as String?;
    if (route == null || route.isEmpty) return;

    Object? args;
    final incidentId = data['incidentId'] as String?;
    if (incidentId != null) {
      args = route == AppRoutes.activeJob
          ? incidentId
          : {'incidentId': incidentId, 'type': data['type'] ?? ''};
    }

    try {
      nav.pushNamed(route, arguments: args);
    } catch (e) {
      debugPrint('FCM route "$route" could not be opened: $e');
    }
  }
}

/// Background isolate handler.
///
/// Must be a top-level function: the isolate that runs it has none of the
/// app's state. Registered in [main] before `runApp`.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  // The isolate starts cold: without this, any Firebase call here throws.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Nothing to do: Android draws data-only messages via the channel already
  // created on first run, and the tap is handled by getInitialMessage. This
  // exists so the plugin does not warn about a missing handler, and as the
  // place any future silent-data work belongs.
}
