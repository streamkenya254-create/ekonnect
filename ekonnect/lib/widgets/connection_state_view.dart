import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/app_assets.dart';
import '../core/constants.dart';

/// Shared empty/error state for anything that failed because the device could
/// not reach the network — used across screens so an offline map, an offline
/// history list and an offline chat all look and behave the same.
///
/// Always offers a retry: an emergency app must never leave a user staring at
/// a dead screen with no way forward.
class ConnectionStateView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Optional secondary escape hatch, e.g. "Call 999".
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Renders inline (inside a card or list) rather than filling the screen.
  final bool compact;

  const ConnectionStateView({
    super.key,
    this.title = 'No internet connection',
    this.message =
        'Check your mobile data or Wi-Fi. Your emergency features still work '
            'over a call.',
    this.onRetry,
    this.retryLabel = 'Try again',
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final art = SvgPicture.asset(
      AppAssets.noInternet,
      width: compact ? 76 : 132,
      height: compact ? 76 : 132,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        art,
        SizedBox(height: compact ? 12 : 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 15 : 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 12.5 : 13.5,
            height: 1.4,
            color: AppColors.textMedium,
          ),
        ),
        if (onRetry != null) ...[
          SizedBox(height: compact ? 14 : 20),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(retryLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                  horizontal: 22, vertical: compact ? 10 : 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
        if (secondaryLabel != null && onSecondary != null) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: onSecondary,
            style: TextButton.styleFrom(foregroundColor: AppColors.emergency),
            child: Text(secondaryLabel!),
          ),
        ],
      ],
    );

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 20 : 32, vertical: compact ? 16 : 24),
        child: content,
      ),
    );
  }
}
