import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _phone = TextEditingController();
  final _license = TextEditingController();
  final _specialization = TextEditingController();
  final _vehicle = TextEditingController();
  bool _loading = false;
  bool _nameFromAccount = false;

  String get _role =>
      ModalRoute.of(context)?.settings.arguments as String? ?? AppRoles.user;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    final existingName = user?.name ?? '';
    _name = TextEditingController(text: existingName);
    _nameFromAccount = existingName.isNotEmpty;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
    };
    if (_role == AppRoles.practitioner) {
      data['licenseNumber'] = _license.text.trim();
      data['specialization'] = _specialization.text.trim();
    }
    if (_role == AppRoles.ambulance) {
      data['vehicleNumber'] = _vehicle.text.trim();
      data['licenseNumber'] = _license.text.trim();
    }
    await auth.updateProfile(data);
    if (!mounted) return;
    if (AppRoles.isResponder(_role)) {
      nav.pushReplacementNamed(AppRoutes.responderHome);
    } else {
      nav.pushReplacementNamed(AppRoutes.userHome);
    }
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

  @override
  Widget build(BuildContext context) {
    final role = _role;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Purple header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.badge_outlined,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Complete Profile',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      role == AppRoles.user
                          ? 'Help responders identify you quickly.'
                          : 'Provide your professional details.',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name field — pre-filled from Google/sign-up
                    _FormCard(
                      children: [
                        if (_nameFromAccount)
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle,
                                    size: 14, color: AppColors.success),
                                const SizedBox(width: 6),
                                Text(
                                  'Name from your account',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.success
                                          .withValues(alpha: 0.8),
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        _field(
                          _name,
                          'Full Name',
                          Icons.person_outline,
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Name is required' : null,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    _FormCard(
                      children: [
                        _field(
                          _phone,
                          'Phone Number',
                          Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          hint: '+254 700 000 000',
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Phone is required' : null,
                        ),
                      ],
                    ),

                    if (role == AppRoles.practitioner) ...[
                      const SizedBox(height: 12),
                      _FormCard(
                        children: [
                          _field(
                            _license,
                            'License / Registration No.',
                            Icons.badge_outlined,
                            validator: (v) => v!.trim().isEmpty
                                ? 'License is required'
                                : null,
                          ),
                          const Divider(height: 1, indent: 54),
                          _field(
                            _specialization,
                            'Specialization (e.g. Nurse, Doctor)',
                            Icons.medical_services_outlined,
                          ),
                        ],
                      ),
                    ],

                    if (role == AppRoles.ambulance) ...[
                      const SizedBox(height: 12),
                      _FormCard(
                        children: [
                          _field(
                            _license,
                            'Driving License No.',
                            Icons.badge_outlined,
                            validator: (v) => v!.trim().isEmpty
                                ? 'License is required'
                                : null,
                          ),
                          const Divider(height: 1, indent: 54),
                          _field(
                            _vehicle,
                            'Ambulance Registration No.',
                            Icons.local_shipping_outlined,
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 28),

                    ElevatedButton(
                      onPressed: _loading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Save & Continue',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(fontSize: 14, color: AppColors.textDark),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle:
              const TextStyle(fontSize: 13, color: AppColors.textMedium),
          prefixIcon:
              Icon(icon, size: 20, color: AppColors.primary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}

class _FormCard extends StatelessWidget {
  final List<Widget> children;
  const _FormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: children),
    );
  }
}
