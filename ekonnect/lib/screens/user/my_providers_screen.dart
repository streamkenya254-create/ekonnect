import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/team_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/connection_state_view.dart';

/// Everything about the private cover a user has arranged for themselves.
///
/// This is what makes private organisations meaningful: once registered, that
/// provider's own crew is dispatched to your emergencies directly, instead of
/// the call going out to the open public network. Because that quietly changes
/// who hears an SOS, this page has to answer four questions without being
/// asked — am I covered, by whom, until when, and how do I reach them.
///
/// Registered but unconfirmed, covered, or lapsed.
enum _Cover { pending, active, expired }

class MyProvidersScreen extends StatefulWidget {
  const MyProvidersScreen({super.key});

  @override
  State<MyProvidersScreen> createState() => _MyProvidersScreenState();
}

class _MyProvidersScreenState extends State<MyProvidersScreen> {
  List<TeamModel>? _privateTeams;
  String? _loadError;
  String? _busyTeamId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  /// Reloads the provider list.
  ///
  /// Keeps whatever is already on screen while it runs. Blanking the list
  /// swapped the ListView for a bare spinner mid-pull, which leaves
  /// RefreshIndicator animating against a child that is no longer scrollable —
  /// and it then dereferences its own null drag state during layout.
  Future<void> _loadTeams() async {
    setState(() => _loadError = null);
    try {
      final teams = await FirestoreService.getTeams();
      if (!mounted) return;
      setState(() => _privateTeams =
          teams.where((t) => t.isPrivate && t.isVerified).toList());
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Future<void> _subscribe(TeamModel team, String uid) async {
    setState(() => _busyTeamId = team.id);
    final user = context.read<AuthProvider>().user;
    try {
      await FirestoreService.subscribeToTeam(
        userId: uid,
        team: team,
        userName: user?.name,
        userPhone: user?.phone,
      );
      if (mounted) {
        _toast(team.hasPaymentDetails
            ? 'Registered. Pay ${team.name} to start your cover.'
            : 'Registered with ${team.name}. They will confirm your cover.');
      }
    } catch (_) {
      if (mounted) _toast('Could not register. Check your connection.');
    } finally {
      if (mounted) setState(() => _busyTeamId = null);
    }
  }

  /// Leaving is not a small tap: it hands the person back to the public
  /// network, and they will not find out until the next emergency. So it is
  /// confirmed, and the consequence is spelled out.
  Future<void> _confirmLeave(String subscriptionId, String name) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Leave this provider?'),
        content: Text(
          '$name will stop receiving your emergencies. Your next SOS goes to '
          'the public network instead.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay registered'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.emergency),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave != true) return;

    setState(() => _busyTeamId = subscriptionId);
    try {
      await FirestoreService.cancelSubscription(subscriptionId);
    } catch (_) {
      if (mounted) _toast('Could not leave. Check your connection.');
    } finally {
      if (mounted) setState(() => _busyTeamId = null);
    }
  }

  /// The number a subscriber actually needs — their provider's own dispatch
  /// desk, not a generic office line.
  Future<void> _call(TeamModel team) async {
    final number = (team.dispatchPhone ?? team.contactPhone ?? '').trim();
    if (number.isEmpty) {
      _toast('${team.name} has not published a dispatch number.');
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: number));
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  static DateTime? _expiry(Map<String, dynamic> s) =>
      s['expiresAt'] is Timestamp ? (s['expiresAt'] as Timestamp).toDate() : null;

  /// Where one registration stands.
  ///
  /// eKonnect handles no money, so cover only becomes real when the facility
  /// records that it has been paid. A registration with no end date has not
  /// been confirmed yet — treating it as open-ended cover would tell someone
  /// they are protected when nobody has agreed to protect them.
  static _Cover _coverOf(Map<String, dynamic> s) {
    final until = _expiry(s);
    if (until == null) return _Cover.pending;
    return until.isBefore(DateTime.now()) ? _Cover.expired : _Cover.active;
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
        title: const Text('My Providers', style: AppText.appBarTitle),
        centerTitle: false,
      ),
      body: uid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: FirestoreService.streamSubscriptions(uid),
              builder: (context, snap) {
                if (_loadError != null) {
                  return ConnectionStateView(
                    title: 'Could not load providers',
                    message:
                        'We could not reach the server. Check your connection '
                        'and try again.',
                    onRetry: _loadTeams,
                  );
                }
                if (_privateTeams == null || !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final registered = snap.data!
                    .where((s) => s['status'] == SubscriptionStatus.active)
                    .toList()
                  // Anything not currently covering them comes first — those
                  // are the only rows with something to do.
                  ..sort((a, b) {
                    int rank(Map<String, dynamic> s) =>
                        _coverOf(s) == _Cover.active ? 1 : 0;
                    return rank(a).compareTo(rank(b));
                  });
                final registeredIds =
                    registered.map((s) => s['teamId'] as String?).toSet();
                final live = registered
                    .where((s) => _coverOf(s) == _Cover.active)
                    .toList();
                final pending = registered
                    .where((s) => _coverOf(s) == _Cover.pending)
                    .toList();

                final available = _privateTeams!
                    .where((t) => !registeredIds.contains(t.id))
                    .where(_matchesQuery)
                    .toList();
                return RefreshIndicator(
                  onRefresh: _loadTeams,
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _coverHero(live.length, pending.length,
                          registered.length - live.length - pending.length),
                      const SizedBox(height: 22),
                      if (registered.isNotEmpty) ...[
                        _sectionTitle('Registered with',
                            trailing: '${registered.length}'),
                        const SizedBox(height: 10),
                        for (final s in registered)
                          _registeredCard(
                            name: s['teamName'] as String? ?? 'Provider',
                            subscriptionId: s['id'] as String,
                            team: _teamById(s['teamId'] as String?),
                            cover: _coverOf(s),
                            since: s['createdAt'] is Timestamp
                                ? (s['createdAt'] as Timestamp).toDate()
                                : null,
                            expiresAt: _expiry(s),
                          ),
                        const SizedBox(height: 24),
                      ],
                      _sectionTitle(registered.isEmpty
                          ? 'Available private providers'
                          : 'Add another provider'),
                      const SizedBox(height: 10),
                      // Always present, even with nothing to filter yet: a
                      // search that only appears once the list is long is a
                      // search nobody discovers, and this list is expected to
                      // grow to every private facility in the country.
                      _searchField(),
                      const SizedBox(height: 12),
                      if (_privateTeams!.isEmpty)
                        _emptyProviders()
                      else if (available.isEmpty)
                        _noMatches(registeredIds.isNotEmpty)
                      else
                        for (final t in available) _providerTile(t, uid),
                    ],
                  ),
                );
              },
            ),
    );
  }

  bool _matchesQuery(TeamModel t) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return t.name.toLowerCase().contains(q) ||
        t.placeLabel.toLowerCase().contains(q) ||
        (t.type ?? '').toLowerCase().contains(q) ||
        t.services.any((s) => s.toLowerCase().contains(q));
  }

  // ── Cover status ────────────────────────────────────────────────────────

  /// The headline answer, before any list: is anyone on the hook for me?
  Widget _coverHero(int live, int pending, int lapsed) {
    late final String title;
    late final String body;
    late final IconData icon;
    late final List<Color> gradient;

    if (live > 0) {
      title = live == 1 ? 'You are covered' : 'Covered by $live providers';
      body = 'An SOS goes straight to your provider’s own crew. The '
          'public network does not see it.';
      icon = Icons.verified_user_rounded;
      gradient = [AppColors.primary, AppColors.primaryDark];
    } else if (pending > 0) {
      title = 'Waiting on your provider';
      body = 'You have registered, but your cover only starts once they '
          'confirm your payment. Until then your SOS goes to the public '
          'network.';
      icon = Icons.hourglass_top_rounded;
      gradient = [AppColors.accent, const Color(0xFFB25A00)];
    } else if (lapsed > 0) {
      title = 'Your cover has expired';
      body = 'Until it is renewed, your emergencies go to the public network '
          'like anyone else’s.';
      icon = Icons.gpp_maybe_rounded;
      gradient = [AppColors.emergency, const Color(0xFF9B1C2E)];
    } else {
      title = 'On the public network';
      body = 'Your SOS is broadcast to every nearby responder. Register with '
          'a provider below to be dispatched by their own crew instead.';
      icon = Icons.public_rounded;
      gradient = [const Color(0xFF3A3A4A), const Color(0xFF23232F)];
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(body,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.45)),
          if (live > 0 && (lapsed > 0 || pending > 0)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (pending > 0) _heroPill('$pending awaiting payment'),
                if (lapsed > 0) _heroPill('$lapsed expired'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroPill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      );

  // ── Registered providers ────────────────────────────────────────────────

  /// One provider you are registered with, and everything you would need from
  /// them in a hurry: their state, their number, and the way out.
  Widget _registeredCard({
    required String name,
    required String subscriptionId,
    required _Cover cover,
    TeamModel? team,
    DateTime? since,
    DateTime? expiresAt,
  }) {
    final busy = _busyTeamId == subscriptionId;
    final paused = team != null && !team.acceptingCases;
    final tone = cover == _Cover.expired
        ? AppColors.emergency
        : cover == _Cover.pending || paused
            ? AppColors.accent
            : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      cover == _Cover.expired
                          ? Icons.gpp_maybe_rounded
                          : cover == _Cover.pending
                              ? Icons.hourglass_top_rounded
                              : Icons.verified_user_rounded,
                      color: tone,
                      size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppText.cardTitle),
                      if (team != null && team.placeLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(team.placeLabel,
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textLight)),
                      ],
                      const SizedBox(height: 7),
                      _statusLine(cover, paused, expiresAt),
                      if (since != null) ...[
                        const SizedBox(height: 3),
                        Text('Registered ${_dateLabel(since)}',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textLight)),
                      ],
                      if (team != null && team.respondsTo.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                            team.respondsTo
                                .map(IncidentType.label)
                                .join(' · '),
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textMedium)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // How to pay them — only while it matters, and only when the
          // facility has published the details.
          if (cover != _Cover.active && team != null && team.hasPaymentDetails)
            _payBlock(team),

          const Divider(height: 1, color: AppColors.divider),
          Row(
            children: [
              _cardAction(
                icon: Icons.call_rounded,
                label: 'Call dispatch',
                enabled: team != null,
                onTap: () => _call(team!),
              ),
              const SizedBox(
                  height: 22, child: VerticalDivider(width: 1)),
              _cardAction(
                icon: Icons.info_outline_rounded,
                label: 'Details',
                enabled: team != null,
                onTap: () => _showProvider(team!, null),
              ),
              const SizedBox(
                  height: 22, child: VerticalDivider(width: 1)),
              _cardAction(
                icon: Icons.logout_rounded,
                label: 'Leave',
                tone: AppColors.textMedium,
                busy: busy,
                onTap: () => _confirmLeave(subscriptionId, name),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusLine(_Cover cover, bool paused, DateTime? expiresAt) {
    // Never assert non-null here. The date and the state are read from the
    // same record, so they agree — but a status line is not worth crashing a
    // page over if a document is ever written by hand or half-migrated.
    final until = expiresAt == null ? null : _dateLabel(expiresAt);

    switch (cover) {
      case _Cover.expired:
        return _statusPill(
            Icons.error_outline_rounded,
            until == null ? 'Cover expired' : 'Expired $until — pay to renew',
            AppColors.emergency);
      case _Cover.pending:
        return _statusPill(Icons.hourglass_top_rounded,
            'Awaiting payment — not covered yet', AppColors.accent);
      case _Cover.active:
        if (paused) {
          return _statusPill(Icons.pause_circle_outline,
              'Not taking cases now', AppColors.accent);
        }
        return _statusPill(
            Icons.bolt_rounded,
            until == null ? 'Active' : 'Active until $until',
            AppColors.success);
    }
  }

  /// How to pay this facility, in the four lines someone needs at the till.
  ///
  /// eKonnect neither collects nor confirms the money — the facility does,
  /// from its own portal — so this says exactly that rather than implying a
  /// tap here completes anything.
  Widget _payBlock(TeamModel team) {
    final price = (team.coverPrice ?? '').trim();
    final days = (team.coverDays ?? '').trim();
    final account = (team.payAccount ?? '').trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined,
                  size: 15, color: AppColors.textMedium),
              const SizedBox(width: 7),
              Text('Pay ${team.name} directly',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark)),
            ],
          ),
          const SizedBox(height: 8),
          _payRow('Paybill / till', team.payBill!.trim()),
          if (account.isNotEmpty) _payRow('Account', account),
          if (price.isNotEmpty)
            _payRow('Amount',
                'KSh $price${days.isEmpty ? '' : ' · $days days'}'),
          const SizedBox(height: 8),
          const Text(
            'Your cover starts when they confirm the payment. eKonnect does '
            'not handle this money.',
            style: TextStyle(
                fontSize: 12.5, height: 1.4, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  /// Tap to copy, rather than a selectable string.
  ///
  /// `SelectableText` inside a ListView calls markNeedsLayout during layout —
  /// it threw '!_debugDoingThisLayout' the moment this page had a pending
  /// registration to draw. Copying a paybill whole is what people want anyway.
  Widget _payRow(String label, String value) => InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          _toast('$label copied');
        },
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textLight)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark)),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.copy_rounded, size: 14, color: AppColors.textLight),
          ],
        ),
        ),
      );

  Widget _statusPill(IconData icon, String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.5, color: colour),
            const SizedBox(width: 5),
            Flexible(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colour)),
            ),
          ],
        ),
      );

  Widget _cardAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color tone = AppColors.primary,
    bool enabled = true,
    bool busy = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: enabled && !busy ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(icon,
                    size: 16,
                    color: enabled ? tone : AppColors.textLight),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: enabled ? tone : AppColors.textLight)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Browsing ────────────────────────────────────────────────────────────

  Widget _searchField() => TextField(
        onChanged: (v) => setState(() => _query = v.trim()),
        decoration: InputDecoration(
          hintText: 'Search by name, town or service',
          hintStyle:
              const TextStyle(fontSize: 14, color: AppColors.textLight),
          prefixIcon:
              const Icon(Icons.search_rounded, size: 20, color: AppColors.textLight),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
        ),
      );

  Widget _sectionTitle(String text, {String? trailing}) => Row(
        children: [
          Text(text, style: AppText.sectionTitle),
          if (trailing != null) ...[
            const SizedBox(width: 7),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(trailing,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
          ],
        ],
      );

  /// The live record for a subscription, when we have it. A provider can be
  /// unverified or full after someone registered with them, and the person
  /// depending on them is exactly who needs to know.
  TeamModel? _teamById(String? id) {
    if (id == null) return null;
    for (final t in _privateTeams ?? const <TeamModel>[]) {
      if (t.id == id) return t;
    }
    return null;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _dateLabel(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// Everything about a provider, before you commit to them.
  ///
  /// Registering hands this organisation your emergencies exclusively — the
  /// public network stops hearing them. That is a real decision, and it was
  /// previously made from a name and a Register button. Passing a null [uid]
  /// opens the same sheet read-only, for a provider you are already with.
  Future<void> _showProvider(TeamModel team, String? uid) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.business_rounded,
                        color: AppColors.primary, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(team.name, style: AppText.sectionTitle),
                        if (team.placeLabel.isNotEmpty)
                          Text(team.placeLabel,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textLight)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(Icons.verified_rounded, 'Verified by eKonnect',
                      AppColors.primary),
                  if (team.open24Hours)
                    _chip(Icons.schedule_rounded, 'Open 24 hours',
                        AppColors.primary),
                  _chip(
                      team.acceptingCases
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      team.acceptingCases
                          ? 'Accepting cases'
                          : 'Not taking cases right now',
                      team.acceptingCases
                          ? AppColors.primary
                          : AppColors.accent),
                  if ((team.type ?? '').isNotEmpty)
                    _chip(Icons.local_hospital_outlined, team.type!,
                        AppColors.primary),
                ],
              ),
              if ((team.description ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                _label('About'),
                Text(team.description!,
                    style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textMedium)),
              ],
              const SizedBox(height: 18),
              _label('Answers'),
              Text(
                team.respondsTo.isEmpty
                    ? 'General emergencies'
                    : team.respondsTo.map(IncidentType.label).join(' · '),
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textMedium),
              ),
              if (team.services.isNotEmpty) ...[
                const SizedBox(height: 18),
                _label('Services'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final svc in team.services)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(svc,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textMedium)),
                      ),
                  ],
                ),
              ],
              if ((team.dispatchPhone ?? team.contactPhone ?? '')
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(height: 18),
                _label('Dispatch line'),
                InkWell(
                  onTap: () => _call(team),
                  child: Row(
                    children: [
                      const Icon(Icons.call_rounded,
                          size: 17, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                          (team.dispatchPhone ?? team.contactPhone)!.trim(),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
              ],
              if (team.hasPaymentDetails) ...[
                const SizedBox(height: 18),
                _label('Cover'),
                _payBlock(team),
              ],
              if (uid != null) ...[
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _subscribe(team, uid);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Register with this provider',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.bold,
                color: AppColors.textLight)),
      );

  Widget _chip(IconData icon, String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colour),
            const SizedBox(width: 5),
            Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colour)),
          ],
        ),
      );

  Widget _providerTile(TeamModel team, String uid) {
    final busy = _busyTeamId == team.id;
    return GestureDetector(
      onTap: () => _showProvider(team, uid),
      child: Container(
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
                  Text(team.name, style: AppText.cardTitle),
                  const SizedBox(height: 2),
                  Text(
                    team.respondsTo.isEmpty
                        ? 'General emergencies'
                        : team.respondsTo
                            .map(IncidentType.label)
                            .join(' · '),
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textMedium),
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.verified_rounded,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 3),
                    const Text('Verified',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                    if (team.open24Hours) ...[
                      const Text('  ·  ',
                          style: TextStyle(
                              fontSize: 11.5, color: AppColors.textLight)),
                      const Text('24 hrs',
                          style: TextStyle(
                              fontSize: 11.5, color: AppColors.textLight)),
                    ],
                    if (team.placeLabel.isNotEmpty) ...[
                      const Text('  ·  ',
                          style: TextStyle(
                              fontSize: 11.5, color: AppColors.textLight)),
                      Flexible(
                        child: Text(team.placeLabel,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.textLight)),
                      ),
                    ],
                  ]),
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
      ),
    );
  }

  Widget _noMatches(bool hasRegistered) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          _query.isNotEmpty
              ? 'No provider matches “$_query”.'
              : hasRegistered
                  ? 'That is every verified provider available to you right now.'
                  : 'No other providers are available right now.',
          style: AppText.body,
        ),
      );

  Widget _emptyProviders() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No private providers yet', style: AppText.cardTitle),
            SizedBox(height: AppSpacing.xs),
            // The distinction people trip on: a hospital being on eKonnect
            // does not make it something you register with. Only a facility
            // that has chosen to take its own clients appears here.
            Text(
              'Hospitals and ambulance services on eKonnect answer any nearby '
              'SOS already. Only a facility that sells its own cover appears '
              'here, and none has been listed yet.',
              style: AppText.body,
            ),
          ],
        ),
      );
}
