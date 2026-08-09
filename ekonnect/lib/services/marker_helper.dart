import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/constants.dart';

/// Builds custom map marker bitmaps drawn entirely on canvas.
/// Results are cached per key so they are only rasterized once.
class MarkerHelper {
  MarkerHelper._();

  static final _cache = <String, BitmapDescriptor>{};

  // ── Public factories ──────────────────────────────────────────────────────

  /// Colored teardrop pin for an SOS incident type (medical, fire, flood, security).
  static Future<BitmapDescriptor> incidentPin(String type) {
    final color = IncidentType.color(type);
    final icon = IncidentType.icon(type);
    return _pin(
      cacheKey: 'incident_$type',
      bgColor: color,
      icon: icon,
    );
  }

  /// Ambulance/practitioner moving marker — shows role icon + initials badge.
  static Future<BitmapDescriptor> responderPin(
      String role, String initials) {
    final isAmbulance = role == AppRoles.ambulance;
    final color = isAmbulance ? AppColors.medicalColor : AppColors.success;
    final icon = isAmbulance
        ? Icons.local_shipping_rounded
        : Icons.medical_services_rounded;
    return _pin(
      cacheKey: 'responder_${role}_$initials',
      bgColor: color,
      icon: icon,
      badgeText: initials,
    );
  }

  /// Purple user/patient pin.
  static Future<BitmapDescriptor> userPin(String initials) {
    return _pin(
      cacheKey: 'user_$initials',
      bgColor: AppColors.primary,
      icon: Icons.person_rounded,
      badgeText: initials,
    );
  }

  /// Small colored dot for a live responder position on the "near you" map.
  /// [key] must be stable per colour so the bitmap is cached/reused.
  static Future<BitmapDescriptor> dot(String key, Color color) async {
    final cacheKey = 'dot_$key';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    const px = 60.0;
    final c = px / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Soft shadow
    canvas.drawCircle(
      Offset(c, c + 1),
      c * 0.66,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );
    // White ring
    canvas.drawCircle(Offset(c, c), c * 0.74, Paint()..color = Colors.white);
    // Colored core
    canvas.drawCircle(Offset(c, c), c * 0.52, Paint()..color = color);

    final picture = recorder.endRecording();
    final img = await picture.toImage(px.toInt(), px.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
    _cache[cacheKey] = descriptor;
    return descriptor;
  }

  // ── Core painter ──────────────────────────────────────────────────────────

  static Future<BitmapDescriptor> _pin({
    required String cacheKey,
    required Color bgColor,
    required IconData icon,
    String? badgeText,
    double px = 96,
  }) async {
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final r = px / 2; // radius of the circle head
    final totalH = px * 1.45; // circle + teardrop tail

    // ── Shadow ──────────────────────────────────────────────────────────────
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(Offset(r + 2, r + 2), r * 0.88, shadowPaint);

    // ── Teardrop tail ────────────────────────────────────────────────────────
    final tailPaint = Paint()..color = bgColor;
    final tail = Path()
      ..moveTo(r - r * 0.22, px * 0.72)
      ..quadraticBezierTo(r, totalH, r + r * 0.22, px * 0.72)
      ..close();
    canvas.drawPath(tail, tailPaint);

    // ── Circle head ───────────────────────────────────────────────────────────
    canvas.drawCircle(Offset(r, r), r * 0.88, tailPaint);

    // White inner circle
    canvas.drawCircle(
        Offset(r, r), r * 0.64, Paint()..color = Colors.white);

    // ── Icon ──────────────────────────────────────────────────────────────────
    _drawIcon(canvas, icon, Offset(r, r), r * 0.46, bgColor);

    // ── Initials badge (top-right corner) ─────────────────────────────────────
    if (badgeText != null && badgeText.isNotEmpty) {
      final bx = r + r * 0.54;
      final by = r - r * 0.54;
      canvas.drawCircle(
          Offset(bx, by), r * 0.28, Paint()..color = Colors.white);
      canvas.drawCircle(
          Offset(bx, by),
          r * 0.26,
          Paint()..color = bgColor.withValues(alpha: 0.9));
      _drawText(canvas, badgeText.length > 2 ? badgeText.substring(0, 2) : badgeText,
          Offset(bx, by), r * 0.17, Colors.white, FontWeight.bold);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(px.toInt(), totalH.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
    );
    _cache[cacheKey] = descriptor;
    return descriptor;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static void _drawIcon(
      Canvas canvas, IconData icon, Offset center, double size, Color color) {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      )
      ..layout();
    tp.paint(
        canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static void _drawText(Canvas canvas, String text, Offset center,
      double size, Color color, FontWeight weight) {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: text,
        style: TextStyle(
            fontSize: size, color: color, fontWeight: weight),
      )
      ..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static void clearCache() => _cache.clear();
}

/// Rotated variant — re-rasterizes with heading so the ambulance
/// icon faces the direction of travel (cached per 15° bucket).
class MovingMarkerHelper {
  MovingMarkerHelper._();

  static final _cache = <String, BitmapDescriptor>{};

  static Future<BitmapDescriptor> ambulanceMoving({
    required String role,
    required String initials,
    required double headingDeg,
  }) async {
    // Snap to nearest 15° to limit cache size
    final bucket = ((headingDeg / 15).round() * 15) % 360;
    final key = '${role}_${initials}_$bucket';
    if (_cache.containsKey(key)) return _cache[key]!;

    const px = 96.0;
    final totalH = px * 1.45;
    final isAmbulance = role == AppRoles.ambulance;
    final color = isAmbulance ? AppColors.medicalColor : AppColors.success;
    final icon = isAmbulance
        ? Icons.local_shipping_rounded
        : Icons.medical_services_rounded;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final r = px / 2;

    // Rotate canvas around the icon centre for heading
    if (bucket != 0) {
      canvas.save();
      canvas.translate(r, r);
      canvas.rotate(bucket * math.pi / 180);
      canvas.translate(-r, -r);
    }

    // Shadow
    canvas.drawCircle(
        Offset(r + 1.5, r + 1.5),
        r * 0.88,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.2)
          ..maskFilter =
              const ui.MaskFilter.blur(ui.BlurStyle.normal, 3));

    // Directional arrow (points up = north by default, rotated by heading)
    final arrowPaint = Paint()..color = color;
    final arrow = Path()
      ..moveTo(r, r - r * 1.1) // tip
      ..lineTo(r - r * 0.2, r - r * 0.7)
      ..lineTo(r + r * 0.2, r - r * 0.7)
      ..close();
    canvas.drawPath(arrow, arrowPaint);

    // Circle
    canvas.drawCircle(Offset(r, r), r * 0.88, arrowPaint);
    canvas.drawCircle(
        Offset(r, r), r * 0.64, Paint()..color = Colors.white);

    _drawIcon(canvas, icon, Offset(r, r), r * 0.46, color);

    if (bucket != 0) canvas.restore();

    // Initials badge (does not rotate)
    final bx = r + r * 0.54;
    final by = r - r * 0.54;
    canvas.drawCircle(Offset(bx, by), r * 0.28, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(bx, by), r * 0.26,
        Paint()..color = color.withValues(alpha: 0.9));
    _drawText(canvas, initials.length > 2 ? initials.substring(0, 2) : initials,
        Offset(bx, by), r * 0.17, Colors.white, FontWeight.bold);

    final picture = recorder.endRecording();
    final img = await picture.toImage(px.toInt(), totalH.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor =
        BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
    _cache[key] = descriptor;
    return descriptor;
  }

  static void _drawIcon(
      Canvas canvas, IconData icon, Offset center, double size, Color color) {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      )
      ..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static void _drawText(Canvas canvas, String text, Offset center,
      double size, Color color, FontWeight weight) {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
          text: text,
          style: TextStyle(
              fontSize: size, color: color, fontWeight: weight))
      ..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }
}
