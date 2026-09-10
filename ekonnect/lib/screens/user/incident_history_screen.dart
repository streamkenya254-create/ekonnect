import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../../core/app_assets.dart';
import '../../core/constants.dart';
import 'incident_detail_screen.dart';
import '../../models/incident_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/connection_state_view.dart';

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
        title: const Text('Emergency History', style: AppText.appBarTitle),
        centerTitle: false,
        bottom: _isResponder && _tabController != null
            ? TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMedium,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
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
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 36),
          itemCount: grouped.length,
          itemBuilder: (_, i) {
            final entry = grouped[i];
            if (entry is String) {
              // Month header
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                child: Text(entry, style: AppText.sectionTitle),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          // Tapping opens the full journey: patients are entitled to the same
          // account of their emergency that the admin audits.
          onTap: () => _showJourney(context),
          borderRadius: BorderRadius.circular(18),
          child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Type icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isClosed
                  ? AppColors.surfaceAlt
                  : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: isCancelled
                  ? Icon(Icons.block_outlined,
                      color: AppColors.textLight, size: 24)
                  : SvgPicture.asset(
                      AppAssets.forIncident(incident.type),
                      width: 30,
                      height: 30,
                      // Cancelled or closed calls fade back; a live one keeps
                      // the illustration's own colours.
                      colorFilter: isClosed
                          ? const ColorFilter.mode(
                              AppColors.textLight, BlendMode.srcIn)
                          : null,
                    ),
            ),
          ),

          const SizedBox(width: 14),

          // Middle: date + title + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(IncidentType.label(incident.type),
                    style: AppText.cardTitle),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _StatusChip(status: incident.status),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('$dateStr · $timeStr',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.meta),
                    ),
                  ],
                ),
                // Who was on the other end of it.
                if (isResponderView || incident.assignedToName != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    isResponderView
                        ? incident.userName.isNotEmpty
                            ? incident.userName
                            : 'Unknown caller'
                        : incident.assignedToName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(fontSize: 13.5),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Right: Re-request button (user view, closed incidents only)
          if (!isResponderView && isClosed)
            GestureDetector(
              onTap: () => onReRequest(incident.type),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceAlt,
                  border: Border.all(color: AppColors.divider),
                ),
                child: Icon(
                  isResolved
                      ? Icons.replay_rounded
                      : Icons.refresh_rounded,
                  size: 19,
                  color: AppColors.textMedium,
                ),
              ),
            )
          else
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textLight, size: 22),
        ],
      ),
          ),
        ),
      ),
    );
  }

  void _showJourney(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncidentDetailScreen(incident: incident),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: AppText.chip.copyWith(color: color)),
    );
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
            style: AppText.sectionTitle,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              isResponder
                  ? 'Jobs you respond to will appear here'
                  : 'Your past emergency requests will appear here',
              style: AppText.pageSubtitle,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
