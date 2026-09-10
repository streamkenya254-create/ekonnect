import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/app_assets.dart';
import '../core/constants.dart';
import '../models/user_model.dart';

/// The signed-in person's face, wherever they appear.
///
/// One widget because a profile photo that only shows on the profile page is
/// not a profile photo. Every other surface drew a generic person icon or a
/// pair of initials, so setting a picture appeared to do nothing.
///
/// Falls back through photo → initials → icon, so it is never empty and never
/// needs a null check at the call site.
class UserAvatar extends StatelessWidget {
  final UserModel? user;
  final double size;
  final Color? background;
  final Color? foreground;

  /// Ring drawn around the photo. Useful on a coloured header where the edge
  /// would otherwise disappear into the background.
  final Color? ring;

  /// Square with rounded corners instead of a circle. The responder header
  /// carried its role illustration in that shape, and the face replacing it
  /// should sit in the same slot rather than change the layout.
  final double? cornerRadius;

  /// A name to draw initials from when there is no user document — a patient
  /// the crew is treating is known by the name on the incident long before
  /// their profile has been fetched, or at all.
  final String? fallbackName;

  const UserAvatar({
    super.key,
    required this.user,
    this.fallbackName,
    this.size = 40,
    this.background,
    this.foreground,
    this.ring,
    this.cornerRadius,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background ?? AppColors.primarySoft;
    final fg = foreground ?? AppColors.primary;
    final bytes = _photoBytes;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: cornerRadius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: cornerRadius == null
            ? null
            : BorderRadius.circular(cornerRadius!),
        border: ring == null ? null : Border.all(color: ring!, width: 2),
        image: bytes == null
            ? null
            : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
      ),
      child: bytes != null
          ? null
          : Center(
              child: _initials.isEmpty
                  // The brand's own person mark rather than a Material glyph,
                  // tinted to whatever surface it is sitting on.
                  ? SvgPicture.asset(
                      AppAssets.user,
                      width: size * 0.5,
                      height: size * 0.5,
                      colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                    )
                  : Text(
                      _initials,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.bold,
                        fontSize: size * 0.36,
                      ),
                    ),
            ),
    );
  }

  /// Decoded photos, keyed by the raw string they came from.
  ///
  /// [MemoryImage] compares by byte-list *identity*, so decoding afresh on
  /// every build produced a new key each time and Flutter reloaded the image —
  /// which is why the avatar flickered while the sheet above it scrolled.
  /// Returning the same instance for the same string makes the key stable and
  /// the paint free. Bounded because a screen only ever shows a handful of
  /// people, and a changed photo is a different string.
  static final _decoded = <String, Uint8List?>{};

  Uint8List? get _photoBytes => decodePhoto(user?.profilePhoto);

  /// Decodes an inline profile photo, once per distinct string.
  ///
  /// Photos are stored as `data:image/jpeg;base64,…` on the user document. A
  /// malformed value must never take a screen down, so failures fall through
  /// to initials.
  static Uint8List? decodePhoto(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (_decoded.containsKey(raw)) return _decoded[raw];

    Uint8List? bytes;
    try {
      bytes = base64Decode(raw.contains(',') ? raw.split(',').last : raw);
    } catch (_) {
      bytes = null; // Cached as null so a bad string is not retried per frame.
    }
    if (_decoded.length > 24) _decoded.clear();
    _decoded[raw] = bytes;
    return bytes;
  }

  String get _initials {
    final source = (user?.name ?? '').trim().isNotEmpty
        ? user!.name
        : (fallbackName ?? '');
    final parts = source
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    if (parts.isEmpty) return '';
    return parts.take(2).map((w) => w[0].toUpperCase()).join();
  }
}
