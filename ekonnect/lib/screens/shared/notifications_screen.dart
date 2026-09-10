import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';

/// Everything the app has told this person, kept.
///
/// A push is a one-shot: miss the banner, swipe it away, or have the phone in
/// a pocket during a call, and the message is gone. An approval, a cover
/// confirmation or a job update deserves somewhere it can be found again —
/// and somewhere a tap reliably leads to the thing it is about.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().user?.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 20, color: AppColors.textDark),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Notifications', style: AppText.appBarTitle),
        actions: [
          if (uid != null)
            TextButton(
              onPressed: () => FirestoreService.markAllNotificationsRead(uid),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: uid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: FirestoreService.streamNotifications(uid),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) return const _Empty();

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _Row(item: items[i]),
                );
              },
            ),
    );
  }
}

class _Row extends StatelessWidget {
  final Map<String, dynamic> item;
  const _Row({required this.item});

  /// The same routing a tapped push uses, so the two can never disagree about
  /// where a message leads.
  void _open(BuildContext context) {
    final id = item['id'] as String?;
    if (id != null && item['read'] != true) {
      FirestoreService.markNotificationRead(id);
    }

    final route = (item['route'] as String?) ?? '';
    if (route.isEmpty) return;

    final incidentId = item['incidentId'] as String?;
    Object? args;
    if (incidentId != null && incidentId.isNotEmpty) {
      args = route == AppRoutes.activeJob
          ? incidentId
          : {'incidentId': incidentId, 'type': item['type'] ?? ''};
    }
    Navigator.pushNamed(context, route, arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    final read = item['read'] == true;
    final ts = item['createdAt'];
    final when = ts is Timestamp ? ts.toDate() : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: read ? Colors.white : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                  color: read
                      ? AppColors.divider
                      : AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unread is carried by a dot rather than only by the tint, so
                // it survives for anyone who cannot separate the two shades.
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 6, right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: read ? Colors.transparent : AppColors.accent,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['title'] as String? ?? 'Update',
                          style: AppText.cardTitle),
                      const SizedBox(height: AppSpacing.xs),
                      Text(item['body'] as String? ?? '', style: AppText.body),
                      if (when != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(_ago(when), style: AppText.meta),
                      ],
                    ],
                  ),
                ),
                if ((item['route'] as String? ?? '').isNotEmpty)
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textLight, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_none_rounded,
                    size: 46, color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Nothing yet', style: AppText.sectionTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Approvals, cover confirmations and updates about your '
                'emergencies will be kept here.',
                textAlign: TextAlign.center,
                style: AppText.pageSubtitle,
              ),
            ],
          ),
        ),
      );
}
