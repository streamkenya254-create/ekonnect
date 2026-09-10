import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _phone;
  late TextEditingController _license;
  late TextEditingController _specialization;
  late TextEditingController _vehicle;

  bool _uploadingPhoto = false;
  bool _editing = false;
  bool _loading = false;

  bool _appliedRouteArgs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedRouteArgs) return;
    _appliedRouteArgs = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['edit'] == true) {
      setState(() => _editing = true);
    }
  }

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _name = TextEditingController(text: user?.name ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _license = TextEditingController(text: user?.licenseNumber ?? '');
    _specialization =
        TextEditingController(text: user?.specialization ?? '');
    _vehicle = TextEditingController(text: user?.vehicleNumber ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _license.dispose();
    _specialization.dispose();
    _vehicle.dispose();
    super.dispose();
  }


  /// Sets the profile picture.
  ///
  /// The picker does the downscaling for us — 720px at 70% quality — because
  /// the image is stored inline on the user document and a raw camera frame
  /// is several megabytes against a 1MiB document ceiling. It is also all a
  /// 90px avatar could ever use.
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Profile photo',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('A responder sees this when they accept your call.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textLight)),
            ),
            const SizedBox(height: 16),
            ListTile(
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('Take a photo'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.divider)),
            ),
            const SizedBox(height: 8),
            ListTile(
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Choose from gallery'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.divider)),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    try {
      final shot = await ImagePicker().pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 70,
      );
      if (shot == null) return;

      final bytes = await shot.readAsBytes();
      // Guard the document ceiling: base64 inflates by about a third, and a
      // rejected write would otherwise surface as a silent failure to save.
      if (bytes.length > 600 * 1024) {
        messenger.showSnackBar(const SnackBar(
            content: Text('That picture is too large. Try another one.')));
        return;
      }

      final data = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      await auth.updateProfile({'profilePhoto': data});
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Profile photo updated')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not set that photo. Try again.')));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    await context.read<AuthProvider>().updateProfile({
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'licenseNumber': _license.text.trim(),
      'specialization': _specialization.text.trim(),
      'vehicleNumber': _vehicle.text.trim(),
    });
    if (!mounted) return;
    setState(() {
      _editing = false;
      _loading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const _SignedOutPlaceholder();

    final initials = user.name
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            // ── Gradient hero header ──────────────────────────────────
            SliverAppBar(
              expandedHeight: 250,
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 20, color: Colors.white),
                onPressed: () => Navigator.maybePop(context),
              ),
              actions: [
                if (!_editing)
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.edit_outlined,
                          color: Colors.white, size: 18),
                    ),
                    onPressed: () => setState(() => _editing = true),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -70,
                        right: -50,
                        child: Container(
                          width: 190,
                          height: 190,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -95,
                        left: -55,
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 42),
                            // Avatar
                      GestureDetector(
                        onTap: _uploadingPhoto ? null : _pickPhoto,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 104,
                              height: 104,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.15),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    width: 3),
                                // Shared cache: decoding here on every build
                                // gave MemoryImage a new key each frame and
                                // made the hero flicker as the header
                                // collapsed.
                                image: UserAvatar.decodePhoto(
                                            user.profilePhoto) ==
                                        null
                                    ? null
                                    : DecorationImage(
                                        image: MemoryImage(
                                            UserAvatar.decodePhoto(
                                                user.profilePhoto)!),
                                        fit: BoxFit.cover),
                              ),
                              child: user.hasPhoto
                                  ? null
                                  : Center(
                                      child: Text(
                                        initials.isEmpty ? '?' : initials,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 36,
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ),
                            ),
                            if (_uploadingPhoto)
                              const SizedBox(
                                width: 104,
                                height: 104,
                                child: CircularProgressIndicator(
                                    strokeWidth: 3, color: Colors.white),
                              ),
                            // Always visible: an avatar that happens to be
                            // tappable is an avatar nobody taps.
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2.5),
                                ),
                                child: const Icon(Icons.camera_alt_rounded,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                            const SizedBox(height: 14),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                user.name.isEmpty ? 'User' : user.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: AppText.pageTitleOnColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppRoles.displayLabel(user.role),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Form body ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: 'Personal',
                      onTapWhenLocked:
                          _editing ? null : () => setState(() => _editing = true),
                      children: [
                        _ProfileField(
                          controller: _name,
                          label: 'Full Name',
                          enabled: _editing,
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Required' : null,
                        ),
                        _ProfileField(
                          controller: _phone,
                          label: 'Phone Number',
                          enabled: _editing,
                          keyboardType: TextInputType.phone,
                        ),
                        _ProfileField(
                          controller: TextEditingController(
                              text: user.email),
                          label: 'Email',
                          enabled: false,
                        ),
                      ],
                    ),

                    if (user.role == AppRoles.practitioner ||
                        user.role == AppRoles.ambulance) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _Section(
                        title: 'Professional',
                        onTapWhenLocked: _editing
                            ? null
                            : () => setState(() => _editing = true),
                        children: [
                          _ProfileField(
                            controller: _license,
                            label: 'License Number',
                            enabled: _editing,
                          ),
                          if (user.role == AppRoles.practitioner)
                            _ProfileField(
                              controller: _specialization,
                              label: 'Specialization',
                              enabled: _editing,
                            ),
                          if (user.role == AppRoles.ambulance)
                            _ProfileField(
                              controller: _vehicle,
                              label: 'Vehicle / Ambulance No.',
                              enabled: _editing,
                            ),
                        ],
                      ),
                    ],

                    const SizedBox(height: AppSpacing.lg),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 2, 4, 12),
                      child: Text('Cover', style: AppText.sectionTitle),
                    ),
                    _MyProvidersCard(uid: user.uid),

                    if (_editing) ...[
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        onPressed: _loading ? null : _save,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Save changes'),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        onPressed: () => setState(() => _editing = false),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.textMedium,
                            minimumSize: const Size(double.infinity, 48)),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cover of everything the user has arranged for their own emergencies.
///
/// Registering with a provider is the one setting here with a consequence
/// people cannot see: their SOS stops going to the public network. So the
/// state — who, how many, and whether the cover has lapsed — belongs on the
/// profile itself, not only behind a tap.
class _MyProvidersCard extends StatelessWidget {
  final String uid;
  const _MyProvidersCard({required this.uid});

  /// A registration only becomes cover when the facility confirms payment and
  /// writes the dates. No date means waiting, not protected.
  static DateTime? _until(Map<String, dynamic> s) {
    final raw = s['expiresAt'];
    return raw is Timestamp ? raw.toDate() : null;
  }

  static bool _isCovered(Map<String, dynamic> s) {
    if (s['status'] != SubscriptionStatus.active) return false;
    final until = _until(s);
    return until != null && until.isAfter(DateTime.now());
  }

  static bool _isLapsed(Map<String, dynamic> s) {
    if (s['status'] == SubscriptionStatus.expired) return true;
    final until = _until(s);
    return until != null && until.isBefore(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.streamSubscriptions(uid),
      builder: (context, snap) {
        final all = snap.data ?? const <Map<String, dynamic>>[];
        final live = all.where(_isCovered).toList();
        final lapsed = all.where(_isLapsed).toList();
        final pending = all
            .where((s) =>
                s['status'] == SubscriptionStatus.active &&
                _until(s) == null)
            .toList();

        final String headline;
        final String action;
        final Color tone;
        final IconData icon;
        if (lapsed.isNotEmpty && live.isEmpty) {
          headline = 'Cover expired — renew to keep priority';
          action = 'Renew';
          tone = AppColors.emergency;
          icon = Icons.error_outline_rounded;
        } else if (pending.isNotEmpty && live.isEmpty) {
          headline = 'Waiting for your provider to confirm payment';
          action = 'View';
          tone = AppColors.accent;
          icon = Icons.hourglass_top_rounded;
        } else if (live.isEmpty) {
          headline = 'No provider yet — your SOS goes to the public network';
          action = 'Set up';
          tone = AppColors.primary;
          icon = Icons.shield_outlined;
        } else {
          action = 'Manage';
          headline = live.length == 1
              ? live.first['teamName'] as String? ?? 'One provider'
              : '${live.length} providers cover you';
          tone = AppColors.success;
          icon = Icons.verified_rounded;
        }

        return InkWell(
          onTap: () => Navigator.pushNamed(context, AppRoutes.myProviders),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: tone.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: tone.withValues(alpha: 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: tone, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('My Providers', style: AppText.cardTitle),
                      const SizedBox(height: 4),
                      Text(headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body
                              .copyWith(fontSize: 13.5, color: tone)),
                      if (lapsed.isNotEmpty && live.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('${lapsed.length} expired',
                            style: AppText.chip
                                .copyWith(color: AppColors.emergency)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // A labelled pill rather than a chevron: this is the way in to
                // arranging cover and paying for it, not a status read-out.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: tone.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(action,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// Tapping a locked group starts editing, so the pencil in the bar is not
  /// the only way in.
  final VoidCallback? onTapWhenLocked;

  const _Section({
    required this.title,
    required this.children,
    this.onTapWhenLocked,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
          child: Text(title, style: AppText.sectionTitle),
        ),
        InkWell(
          onTap: onTapWhenLocked,
          borderRadius: BorderRadius.circular(18),
          child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            // Stretch, not the default centre: without it each row shrank to
            // the width of its own text and floated in the middle of the card.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in children) ...[
                  c,
                  if (c != children.last)
                    const Divider(height: 1, color: AppColors.divider),
                ],
              ],
            ),
          ),
          ),
        ),
      ],
    );
  }
}

/// One line of the profile.
///
/// Reading and editing used to look identical — every value sat in a filled
/// input box with its own coloured icon, so a page of five facts looked like
/// a form of five questions. Now it is a label and a value until the page is
/// actually in edit mode.
class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const _ProfileField({
    required this.controller,
    required this.label,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      final value = controller.text.trim();
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.cardTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value.isEmpty ? 'Not set' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                  color: value.isEmpty
                      ? AppColors.textLight
                      : AppColors.textMedium),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: AppText.bodyStrong.copyWith(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
      ),
    );
  }
}

class _SignedOutPlaceholder extends StatefulWidget {
  const _SignedOutPlaceholder();

  @override
  State<_SignedOutPlaceholder> createState() => _SignedOutPlaceholderState();
}

class _SignedOutPlaceholderState extends State<_SignedOutPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Layered icon stack
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.12),
                                AppColors.primary.withValues(alpha: 0.04),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.lock_person_outlined,
                            size: 40,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Session Ended',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'You\'ve been signed out.\nSign in again to view your profile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textMedium,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context,
                            AppRoutes.login,
                            (_) => false,
                          ),
                          icon: const Icon(Icons.login_rounded, size: 18),
                          label: const Text('Sign In'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            textStyle: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => Navigator.maybePop(context),
                      child: const Text(
                        'Go Back',
                        style: TextStyle(
                            color: AppColors.textMedium, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
