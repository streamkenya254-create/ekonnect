import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/incident_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/connection_state_view.dart';
import '../../widgets/incident_journey_view.dart';

class IncidentHistoryScreen extends StatefulWidget {
  const IncidentHistoryScreen({super.key});

  @override
  State<IncidentHistoryScreen> createState() => _IncidentHistoryScreenState();
}

class _IncidentHistoryScreenState extends State<IncidentHistoryScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  Stream<List<IncidentModel>>? _userStream;
  Stream<List<IncidentModel>>? _responderStream;
  bool _isResponder = false;

  @override
  void initState() {
    super.initState();
    // Capture uid ONCE in initState. Never read it again from build() so
    // provider rebuilds (GPS pings, auth refreshes) cannot swap the stream.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final uid = auth.user?.uid ?? '';
      if (uid.isEmpty) return;

      final isResponder = AppRoles.isResponder(auth.user?.role ?? '');
      final tabCtrl = isResponder ? TabController(length: 2, vsync: this) : null;

      setState(() {
        _isResponder = isResponder;
        _tabController = tabCtrl;
        _userStream = FirestoreService.streamUserIncidents(uid);
        if (isResponder) {
          _responderStream = FirestoreService.streamResponderIncidents(uid);
        }
      });
    });
  }

  /// Rebuilds the Firestore subscriptions. A failed snapshot stream stays dead
  /// for that subscription, so a real retry has to hand StreamBuilder a new
  /// stream instance — re-rendering the old one would change nothing.
  void _reloadStreams() {
    final uid = context.read<AuthProvider>().user?.uid ?? '';
    if (uid.isEmpty) return;
    setState(() {
      _userStream = FirestoreService.streamUserIncidents(uid);
      if (_isResponder) {
        _responderStream = FirestoreService.streamResponderIncidents(uid);
      }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textDark),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Emergency History',
            style: TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        centerTitle: false,
        bottom: _isResponder && _tabController != null
            ? TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMedium,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: 'My Calls'),
                  Tab(text: 'Jobs Handled'),
                ],
              )
            : null,
      ),
      body: _userStream == null
          ? const Center(child: CircularProgressIndicator())
          : _isResponder && _tabController != null
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _HistoryList(
                        stream: _userStream!,
                        isResponderView: false,
                        onRetry: _reloadStreams,
                        onReRequest: _reRequest),
                    _HistoryList(
                        stream: _responderStream!,
                        isResponderView: true,
                        onRetry: _reloadStreams,
                        onReRequest: _reRequest),
                  ],
                )
              : _HistoryList(
                  stream: _userStream!,
                  isResponderView: false,
                  onRetry: _reloadStreams,
                  onReRequest: _reRequest),
    );
  }

  Future<void> _reRequest(String type) async {
    final provider = context.read<IncidentProvider>();
    final nav = Navigator.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(IncidentType.icon(type), color: IncidentType.color(type)),
          const SizedBox(width: 8),
          Text(IncidentType.label(type)),
        ]),
        content: const Text(
            'This will send a new emergency request with your current GPS location.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: IncidentType.color(type)),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final id = await provider.createSOS(type);
    if (!mounted) return;
    if (id != null) {
      nav.pushReplacementNamed(AppRoutes.sosWaiting,
          arguments: {'type': type, 'incidentId': id});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not send SOS. Please try again or call 999.'),
            backgroundColor: AppColors.emergency),
      );
    }
  }
}

// ── Shared list widget (used for both tabs) ───────────────────────────────────

class _HistoryList extends StatefulWidget {
  final Stream<List<IncidentModel>> stream;
  final bool isResponderView;
  final void Function(String type) onReRequest;
  final VoidCallback onRetry;

  const _HistoryList({
    required this.stream,
    required this.isResponderView,
    required this.onReRequest,
    required this.onRetry,
  });

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  List<IncidentModel>? _data; // null = loading, [] = genuinely empty

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<IncidentModel>>(
      stream: widget.stream,
      builder: (context, snap) {
        // First real emission: store it so we never revert to empty.
        if (snap.hasData) {
          _data = snap.data;
        }

        // Show spinner only on first load (before any emission).
        if (_data == null) {
          if (snap.hasError) {
            return _errorState(snap.error.toString());
          }
          return const Center(child: CircularProgressIndicator());
        }

        if (_data!.isEmpty) return _EmptyState(isResponder: widget.isResponderView);

        final grouped = _groupByMonth(_data!);

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          itemCount: grouped.length,
          itemBuilder: (_, i) {
            final entry = grouped[i];
            if (entry is String) {
              // Month header
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(entry,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: AppColors.textDark)),
              );
            }
            final incident = entry as IncidentModel;
            return _IncidentRow(
              incident: incident,
              isResponderView: widget.isResponderView,
              onReRequest: widget.onReRequest,
            );
          },
        );
      },
    );
  }

  Widget _errorState(String err) {
    // A missing Firestore index is a build-time problem, not a connectivity
    // one — say so rather than blaming the user's network.
    final isIndexBuilding = err.contains('index') || err.contains('Index');

    return ConnectionStateView(
      title: isIndexBuilding ? 'Preparing your history' : 'Could not load history',
      message: isIndexBuilding
          ? 'A database index is still being built. This usually clears within '
              'a minute — try again shortly.'
          : 'We could not reach the server. Check your connection and try again.',
      onRetry: widget.onRetry,
    );
  }

  // Returns a flat list alternating String (month headers) and IncidentModel rows.
  List<Object> _groupByMonth(List<IncidentModel> incidents) {
    final result = <Object>[];
    String? lastMonth;
    for (final i in incidents) {
      final month = DateFormat('MMMM yyyy').format(i.createdAt);
      if (month != lastMonth) {
        result.add(month);
        lastMonth = month;
      }
      result.add(i);
    }
    return result;
  }
}

// ── Single incident row (Bolt "Rides" style) ──────────────────────────────────

class _IncidentRow extends StatelessWidget {
  final IncidentModel incident;
  final bool isResponderView;
  final void Function(String) onReRequest;

  const _IncidentRow({
    required this.incident,
    required this.isResponderView,
    required this.onReRequest,
  });

  @override
  Widget build(BuildContext context) {
    final isClosed = incident.isClosed;
    final isCancelled = incident.status == IncidentStatus.cancelled;
    final isResolved = incident.status == IncidentStatus.resolved;
    final color = IncidentType.color(incident.type);
    final dateStr = DateFormat('d MMM').format(incident.createdAt);
    final timeStr = DateFormat('HH:mm').format(incident.createdAt);

    return InkWell(
      // Tapping opens the full journey: patients are entitled to the same
      // account of their emergency that the admin audits.
      onTap: () => _showJourney(context),
      child: Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Type icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isClosed
                  ? AppColors.background
                  : color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCancelled
                  ? Icons.block_outlined
                  : IncidentType.icon(incident.type),
              color: isClosed ? AppColors.textLight : color,
              size: 20,
            ),
          ),

          const SizedBox(width: 14),

          // Middle: date + title + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date + status line
                Row(
                  children: [
                    Text('$dateStr · ',
                        style: const TextStyle(
                            color: AppColors.textMedium, fontSize: 12)),
                    _StatusChip(status: incident.status),
                  ],
                ),
                const SizedBox(height: 3),
                // Type label
                Text(
                  IncidentType.label(incident.type),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textDark),
                ),
                const SizedBox(height: 2),
                // Responder or time detail
                Text(
                  isResponderView
                      ? 'Patient: ${incident.userName.isNotEmpty ? incident.userName : "Unknown"}'
                      : incident.assignedToName != null
                          ? 'Responder: ${incident.assignedToName}'
                          : timeStr,
                  style: const TextStyle(
                      color: AppColors.textMedium, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Right: Re-request button (user view, closed incidents only)
          if (!isResponderView && isClosed)
            GestureDetector(
              onTap: () => onReRequest(incident.type),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: AppColors.divider, width: 1.5),
                ),
                child: Icon(
                  isResolved
                      ? Icons.replay_rounded
                      : Icons.refresh_rounded,
                  size: 18,
                  color: AppColors.textMedium,
                ),
              ),
            )
          else if (isResponderView)
            Text(timeStr,
                style: const TextStyle(
                    color: AppColors.textLight,
                    fontSize: 12)),
        ],
      ),
      ),
    );
  }

  void _showJourney(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(IncidentType.label(incident.type),
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                DateFormat('EEEE d MMMM, HH:mm').format(incident.createdAt),
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textMedium),
              ),
              if ((incident.cancelReason ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Reason: ${CancelReasons.label(incident.cancelReason)}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textMedium)),
              ],
              const SizedBox(height: 20),
              IncidentJourneyView(incident: incident, showMetrics: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case IncidentStatus.resolved:
        color = AppColors.success;
        label = 'Resolved';
        break;
      case IncidentStatus.cancelled:
        color = AppColors.textLight;
        label = 'Cancelled';
        break;
      case IncidentStatus.assigned:
      case IncidentStatus.enRoute:
      case IncidentStatus.arrived:
        color = AppColors.info;
        label = IncidentStatus.label(status);
        break;
      default:
        color = AppColors.warning;
        label = 'Waiting';
    }
    return Text(label,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w500));
  }
}

class _EmptyState extends StatelessWidget {
  final bool isResponder;
  const _EmptyState({required this.isResponder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isResponder ? Icons.work_history_outlined : Icons.history_rounded,
              size: 52,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isResponder ? 'No jobs yet' : 'No emergency history',
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark),
          ),
          const SizedBox(height: 6),
          Text(
            isResponder
                ? 'Jobs you respond to will appear here'
                : 'Your past emergency requests will appear here',
            style: const TextStyle(color: AppColors.textMedium, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
