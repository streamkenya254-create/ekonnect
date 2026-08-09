import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

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
  bool _editing = false;
  bool _loading = false;

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

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content:
            const Text('You will need to sign in again to use the app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign Out',
                  style: TextStyle(color: AppColors.emergency))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    await auth.signOut();
    nav.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
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
              expandedHeight: 220,
              pinned: true,
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      // Avatar
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 3),
                        ),
                        child: Center(
                          child: Text(
                            initials.isEmpty ? '?' : initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        user.name.isEmpty ? 'User' : user.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      _RoleBadge(role: user.role),
                    ],
                  ),
                ),
              ),
            ),

            // ── Form body ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: 'Personal Info',
                      children: [
                        _ProfileField(
                          controller: _name,
                          label: 'Full Name',
                          icon: Icons.person_outline,
                          enabled: _editing,
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Required' : null,
                        ),
                        _ProfileField(
                          controller: _phone,
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                          enabled: _editing,
                          keyboardType: TextInputType.phone,
                        ),
                        _ProfileField(
                          controller: TextEditingController(
                              text: user.email),
                          label: 'Email',
                          icon: Icons.email_outlined,
                          enabled: false,
                        ),
                      ],
                    ),

                    if (user.role == AppRoles.practitioner ||
                        user.role == AppRoles.ambulance) ...[
                      const SizedBox(height: 8),
                      _Section(
                        title: 'Professional Info',
                        children: [
                          _ProfileField(
                            controller: _license,
                            label: 'License Number',
                            icon: Icons.badge_outlined,
                            enabled: _editing,
                          ),
                          if (user.role == AppRoles.practitioner)
                            _ProfileField(
                              controller: _specialization,
                              label: 'Specialization',
                              icon: Icons.medical_services_outlined,
                              enabled: _editing,
                            ),
                          if (user.role == AppRoles.ambulance)
                            _ProfileField(
                              controller: _vehicle,
                              label: 'Vehicle / Ambulance No.',
                              icon: Icons.local_shipping_outlined,
                              enabled: _editing,
                            ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    if (_editing) ...[
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _save,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save Changes'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => setState(() => _editing = false),
                        child: const Text('Cancel'),
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout,
                            color: AppColors.emergency, size: 18),
                        label: const Text('Sign Out',
                            style: TextStyle(color: AppColors.emergency)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.emergency)),
                      ),
                    ],
                    const SizedBox(height: 32),
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

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textLight,
                letterSpacing: 0.8),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: children
                .map((c) => Column(children: [
                      c,
                      if (c != children.last)
                        const Divider(height: 1, indent: 54),
                    ]))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const _ProfileField({
    required this.controller,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(
            fontSize: 14,
            color: enabled ? AppColors.textDark : AppColors.textMedium),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              const TextStyle(fontSize: 12, color: AppColors.textLight),
          prefixIcon: Icon(icon,
              size: 20,
              color: enabled ? AppColors.primary : AppColors.textLight),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          filled: false,
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

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String label;
    switch (role) {
      case AppRoles.ambulance:
        icon = Icons.local_shipping;
        label = 'Ambulance';
        break;
      case AppRoles.practitioner:
        icon = Icons.medical_services;
        label = 'Practitioner';
        break;
      case AppRoles.admin:
        icon = Icons.admin_panel_settings;
        label = 'Admin';
        break;
      default:
        icon = Icons.person;
        label = 'User';
    }
    // Sits on the purple hero — render in white so it stays legible.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
