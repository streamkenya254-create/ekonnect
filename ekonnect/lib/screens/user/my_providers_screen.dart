import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/team_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/connection_state_view.dart';

/// Lets a user register with a private emergency provider.
///
/// This is what makes private organisations meaningful: once registered, that
/// provider's own crew is dispatched to your emergencies directly, instead of
/// the call going out to the open public network.
class MyProvidersScreen extends StatefulWidget {
  const MyProvidersScreen({super.key});

  @override
  State<MyProvidersScreen> createState() => _MyProvidersScreenState();
}

class _MyProvidersScreenState extends State<MyProvidersScreen> {
  List<TeamModel>? _privateTeams;
  String? _loadError;
  String? _busyTeamId;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loadError = null;
      _privateTeams = null;
    });
    try {
      final teams = await FirestoreService.getTeams();
      if (!mounted) return;
      setState(() =>
          _privateTeams = teams.where((t) => t.isPrivate).toList());
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Future<void> _subscribe(TeamModel team, String uid) async {
    setState(() => _busyTeamId = team.id);
    try {
      await FirestoreService.subscribeToTeam(userId: uid, team: team);
    } finally {
      if (mounted) setState(() => _busyTeamId = null);
    }
  }

  Future<void> _cancel(String subscriptionId) async {
    setState(() => _busyTeamId = subscriptionId);
    try {
      await FirestoreService.cancelSubscription(subscriptionId);
    } finally {
      if (mounted) setState(() => _busyTeamId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().user?.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 20, color: AppColors.textDark),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('My Providers',
            style: TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        centerTitle: false,
      ),
      body: uid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: FirestoreService.streamSubscriptions(uid),
              builder: (context, snap) {
                final subs = (snap.data ?? [])
                    .where((s) => s['status'] == SubscriptionStatus.active)
                    .toList();
                final subscribedIds =
                    subs.map((s) => s['teamId'] as String?).toSet();

                if (_loadError != null) {
                  return ConnectionStateView(
                    title: 'Could not load providers',
                    message:
                        'We could not reach the server. Check your connection '
                        'and try again.',
                    onRetry: _loadTeams,
                  );
                }
                if (_privateTeams == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _explainer(subs.isNotEmpty),
                    const SizedBox(height: 18),
                    if (subs.isNotEmpty) ...[
                      _sectionTitle('Registered with'),
                      const SizedBox(height: 8),
                      for (final s in subs)
                        _subscriptionTile(
                          name: s['teamName'] as String? ?? 'Provider',
                          subscriptionId: s['id'] as String,
                        ),
                      const SizedBox(height: 22),
                    ],
                    _sectionTitle('Available private providers'),
                    const SizedBox(height: 8),
                    if (_privateTeams!.isEmpty)
                      _emptyProviders()
                    else
                      for (final t in _privateTeams!
                          .where((t) => !subscribedIds.contains(t.id)))
                        _providerTile(t, uid),
                  ],
                );
              },
            ),
    );
  }

  Widget _explainer(bool hasAny) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasAny
                  ? 'Your emergencies go straight to the providers you are '
                      'registered with, instead of the public network.'
                  : 'Register with a private provider — a hospital, insurer or '
                      'your employer — and your emergencies go directly to their '
                      'own crew. Without one, calls go to the public network.',
              style: const TextStyle(
                  fontSize: 12.5, height: 1.4, color: AppColors.textMedium),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textMedium,
            letterSpacing: 0.3),
      );

  Widget _subscriptionTile(
      {required String name, required String subscriptionId}) {
    final busy = _busyTeamId == subscriptionId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded,
              color: AppColors.success, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                const Text('Dispatched to you directly',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textMedium)),
              ],
            ),
          ),
          busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: () => _cancel(subscriptionId),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMedium),
                  child: const Text('Leave'),
                ),
        ],
      ),
    );
  }

  Widget _providerTile(TeamModel team, String uid) {
    final busy = _busyTeamId == team.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.business_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.name,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  team.respondsTo.isEmpty
                      ? 'General emergencies'
                      : team.respondsTo
                          .map(IncidentType.label)
                          .join(' · '),
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMedium),
                ),
              ],
            ),
          ),
          busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : ElevatedButton(
                  onPressed: () => _subscribe(team, uid),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Register'),
                ),
        ],
      ),
    );
  }

  Widget _emptyProviders() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'No private providers are available yet. Public emergency responders '
          'will still answer your calls.',
          style: TextStyle(
              fontSize: 13, height: 1.4, color: AppColors.textMedium),
        ),
      );
}
