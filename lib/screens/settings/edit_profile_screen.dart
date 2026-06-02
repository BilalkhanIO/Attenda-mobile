import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user!;
    _nameCtrl.text  = user.name;
    _phoneCtrl.text = user.phone ?? '';
  }

  @override
  void dispose() { _nameCtrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final name  = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Name is required'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await api.updateProfile(name: name, phone: phone.isNotEmpty ? phone : null);
      if (!mounted) return;
      await context.read<AuthProvider>().refreshUser();
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = 'Failed to save. Please try again.');
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withOpacity(0.18)),
                      ),
                      child: Icon(Icons.arrow_back, color: Colors.white.withOpacity(0.8), size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Text('Edit Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.danger500.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger500.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.danger500, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger500, fontSize: 13))),
                ]),
              ),
            ],
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline, size: 18, color: Colors.white.withOpacity(0.4)),
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
                    prefixIcon: Icon(Icons.phone_outlined, size: 18, color: Colors.white.withOpacity(0.4)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            AppButton(label: 'Save Changes', loading: _loading, onPressed: _save),
          ]),
        ),
      ),
    );
  }
}
