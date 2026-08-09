import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/care_point_model.dart';
import '../../models/incident_model.dart';
import '../../services/care_point_service.dart';

/// Lets a responder hand an emergency on to a care point.
///
/// Used from "arrived" onward, and repeatedly: if the first facility turns the
/// patient away, the responder reopens this and refers again. Every attempt is
/// appended to the incident's referral chain rather than replacing the last.
class ReferralSheet extends StatefulWidget {
  final IncidentModel incident;
  final LatLng origin;

  const ReferralSheet({
    super.key,
    required this.incident,
    required this.origin,
  });

  @override
  State<ReferralSheet> createState() => _ReferralSheetState();
}

class _ReferralSheetState extends State<ReferralSheet> {
  final _needCtrl = TextEditingController();
  List<CarePoint>? _results;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _needCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      var found = await CarePointService.findNearby(
        origin: widget.origin,
        incidentType: widget.incident.type,
        need: _needCtrl.text.trim(),
      );
      // Road travel time only for the few actually shown — each is a billed call.
      found = await CarePointService.withTravelTimes(found, widget.origin);
      if (!mounted) return;
      setState(() => _results = found);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _refer(CarePoint point) async {
    Navigator.pop(context, point);
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final alreadyTried = widget.incident.referrals
        .map((r) => r['carePointId'] as String?)
        .whereType<String>()
        .toSet();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Refer to a care point',
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    alreadyTried.isEmpty
                        ? 'Find somewhere that can take this patient.'
                        : '${alreadyTried.length} place(s) already tried — '
                            'they stay on the record.',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textMedium),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _needCtrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          decoration: InputDecoration(
                            hintText: 'What do they need? e.g. trauma surgery',
                            filled: true,
                            fillColor: AppColors.surfaceAlt,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _searching ? null : _search,
                        style: IconButton.styleFrom(
                            backgroundColor: AppColors.primary),
                        icon: const Icon(Icons.search_rounded, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _body(scrollController, alreadyTried)),
          ],
        ),
      ),
    );
  }

  Widget _body(ScrollController controller, Set<String> alreadyTried) {
    if (_searching && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _message('Could not search right now.\nCheck your connection.');
    }
    final results = _results ?? const <CarePoint>[];
    if (results.isEmpty) {
      return _message(
        'No care points found nearby.\n'
        'Registered facilities appear here first; Google results fill the rest.',
      );
    }

    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _CarePointCard(
        point: results[i],
        alreadyTried: alreadyTried.contains(results[i].id),
        onRefer: () => _refer(results[i]),
        onCall: results[i].phone == null
            ? null
            : () => _call(results[i].phone!),
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13.5, height: 1.5, color: AppColors.textMedium),
          ),
        ),
      );
}

class _CarePointCard extends StatelessWidget {
  final CarePoint point;
  final bool alreadyTried;
  final VoidCallback onRefer;
  final VoidCallback? onCall;

  const _CarePointCard({
    required this.point,
    required this.alreadyTried,
    required this.onRefer,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alreadyTried ? AppColors.surfaceAlt : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alreadyTried
              ? AppColors.divider
              : point.isRegistered
                  ? AppColors.success.withValues(alpha: 0.45)
                  : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(point.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(CarePointType.label(point.type),
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.textMedium)),
                        if (!point.isVisitable) ...[
                          const SizedBox(width: 6),
                          const Text('• dispatches to you',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMedium)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Registered facilities declared their services; Google results
              // did not. Never let the two look equally trustworthy.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: point.isRegistered
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  point.isRegistered ? 'Registered' : 'Unverified',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: point.isRegistered
                        ? AppColors.success
                        : AppColors.textMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _chip(Icons.route_outlined, point.distanceText),
              if (point.travelTimeText.isNotEmpty) ...[
                const SizedBox(width: 6),
                _chip(Icons.timer_outlined, point.travelTimeText),
              ],
              if (point.open24Hours) ...[
                const SizedBox(width: 6),
                _chip(Icons.schedule_rounded, '24 hrs'),
              ],
            ],
          ),
          if (point.matchReason != null &&
              point.matchReason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(point.matchReason!,
                      style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.primary)),
                ),
              ],
            ),
          ],
          if (point.services.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final s in point.services.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $s',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textDark)),
              ),
          ],
          if ((point.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(point.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, height: 1.35, color: AppColors.textMedium)),
          ],
          if (point.address != null) ...[
            const SizedBox(height: 8),
            Text(point.address!,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textLight)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (onCall != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call, size: 16),
                    label: const Text('Call'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: alreadyTried ? null : onRefer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.divider,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(alreadyTried ? 'Already tried' : 'Refer here'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.textMedium),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
          ],
        ),
      );
}
