import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

class FCMService {
  static final _fcm = FirebaseMessaging.instance;

  static Future<String?> initialize() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('FCM foreground: ${message.notification?.title}');
    });

    // Handle notification tap when app was in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FCM tapped from background: ${message.data}');
    });

    return _fcm.getToken();
  }

  static Future<String?> getToken() => _fcm.getToken();

  static Stream<String> get tokenRefreshStream => _fcm.onTokenRefresh;
}
