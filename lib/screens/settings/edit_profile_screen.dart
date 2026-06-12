import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();
  DateTime? _dob;
  String _gender = ''; // '' = prefer not to say
  bool _loading = false;
  // Personal details are only written back once they've been prefilled from
  // the server, so a failed GET /users/me can't silently wipe stored values.
  bool _detailsLoaded = false;
  String? _error;

  static const _genderOptions = [
    ('', 'Prefer not to say'),
    ('male', 'Male'),
    ('female', 'Female'),
    ('other', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user!;
    _nameCtrl.text = user.name;
    _phoneCtrl.text = user.phone ?? '';
    _loadDetails();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    try {
      final me = await api.getMe();
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = me['name'] as String? ?? _nameCtrl.text;
        _phoneCtrl.text = me['phone'] as String? ?? _phoneCtrl.text;
        _addressCtrl.text = me['address'] as String? ?? '';
        _cityCtrl.text = me['city'] as String? ?? '';
        _countryCtrl.text = me['country'] as String? ?? '';
        _emergencyNameCtrl.text = me['emergency_contact_name'] as String? ?? '';
        _emergencyPhoneCtrl.text = me['emergency_contact_phone'] as String? ?? '';
        final dobStr = me['date_of_birth'] as String?;
        _dob = dobStr != null ? DateTime.tryParse(dobStr) : null;
        final gender = me['gender'] as String? ?? '';
        _gender = _genderOptions.any((o) => o.$1 == gender) ? gender : '';
        _detailsLoaded = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Couldn\'t load your saved details — ${ApiFailure.fromError(e).userMessage}');
      }
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      builder: (ctx, child) => Theme(data: AppTheme.glass, child: child!),
    );
    if (picked != null && mounted) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'name': name,
        'phone': phone.isNotEmpty ? phone : null,
        if (_detailsLoaded) ...{
          'date_of_birth':
              _dob != null ? DateFormat('yyyy-MM-dd').format(_dob!) : null,
          'gender': _gender,
          'address': _addressCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'country': _countryCtrl.text.trim(),
          'emergency_contact_name': _emergencyNameCtrl.text.trim(),
          'emergency_contact_phone': _emergencyPhoneCtrl.text.trim(),
        },
      };
      await api.updateMe(data);
      if (!mounted) return;
      await context.read<AuthProvider>().refreshUser();
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = ApiFailure.fromError(e).userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: const Icon(Icons.arrow_back_ios,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Text('Edit Profile',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ]),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.danger500.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.danger500.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.danger500, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.danger500, fontSize: 13))),
                ]),
              ),
            ],

            _sectionLabel('BASICS'),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline,
                        size: 18, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+44 7700 000000',
                    prefixIcon: Icon(Icons.phone_outlined,
                        size: 18, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 24),
            _sectionLabel('PERSONAL DETAILS'),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                // Date of birth
                GestureDetector(
                  onTap: _pickDob,
                  child: AbsorbPointer(
                    child: TextFormField(
                      key: ValueKey('dob-${_dob?.toIso8601String() ?? ''}'),
                      initialValue: _dob != null
                          ? DateFormat('d MMMM yyyy').format(_dob!)
                          : '',
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Date of Birth',
                        hintText: 'Select date',
                        prefixIcon: Icon(Icons.cake_outlined,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('gender-$_gender'),
                  initialValue: _gender,
                  isExpanded: true,
                  dropdownColor: AppColors.bgDark3,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Gender',
                    prefixIcon: Icon(Icons.wc_outlined,
                        size: 18, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  items: _genderOptions
                      .map((o) => DropdownMenuItem<String>(
                            value: o.$1,
                            child: Text(o.$2),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _gender = v ?? ''),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.home_outlined,
                        size: 18, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _countryCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Country'),
                    ),
                  ),
                ]),
              ]),
            ),

            const SizedBox(height: 24),
            _sectionLabel('EMERGENCY CONTACT'),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                TextFormField(
                  controller: _emergencyNameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Contact Name',
                    prefixIcon: Icon(Icons.contact_emergency_outlined,
                        size: 18, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emergencyPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Contact Phone',
                    prefixIcon: Icon(Icons.phone_in_talk_outlined,
                        size: 18, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 24),
            AppButton(
                label: 'Save Changes', loading: _loading, onPressed: _save),
          ]),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: Color(0x66FFFFFF)));
}
