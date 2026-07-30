import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  // Change password
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true, _obscureNew = true, _obscureConfirm = true;
  bool _savingPw = false;
  String? _pwError;

  // 2FA
  bool _saving2fa = false;
  String? _setupSecret;
  final _codeCtrl = TextEditingController();
  bool _verifying = false;

  @override
  void dispose() {
    _currentCtrl.dispose(); _newCtrl.dispose(); _confirmCtrl.dispose(); _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final current = _currentCtrl.text.trim();
    final next = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (current.isEmpty || next.isEmpty) { setState(() => _pwError = 'All fields required'); return; }
    if (next.length < 8) { setState(() => _pwError = 'New password must be at least 8 characters'); return; }
    if (next != confirm) { setState(() => _pwError = 'Passwords do not match'); return; }
    setState(() { _pwError = null; _savingPw = true; });
    try {
      await api.changePassword(current, next);
      if (!mounted) return;
      _currentCtrl.clear(); _newCtrl.clear(); _confirmCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed ✅')));
    } catch (e) {
      if (!mounted) return;
      final failure = ApiFailure.fromError(e);
      setState(() => _pwError =
          failure is UnauthorizedFailure || failure is ForbiddenFailure
              ? 'Current password is incorrect'
              : failure.userMessage);
    } finally {
      if (mounted) setState(() => _savingPw = false);
    }
  }

  Future<void> _setup2fa() async {
    setState(() => _saving2fa = true);
    try {
      final data = await api.setup2fa();
      if (!mounted) return;
      setState(() { _setupSecret = data['secret'] as String?; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiFailure.fromError(e).userMessage)));
      }
    } finally {
      if (mounted) setState(() => _saving2fa = false);
    }
  }

  Future<void> _verify2fa() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) return;
    setState(() => _verifying = true);
    try {
      await api.verify2fa(code);
      if (!mounted) return;
      setState(() { _setupSecret = null; _codeCtrl.clear(); });
      context.read<AuthProvider>().refreshUser();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('2FA enabled ✅')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid code — try again')));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _disable2fa() async {
    final confirmed = await showConfirmDialog(context, title: 'Disable 2FA', message: 'Enter your current 2FA code to confirm.', confirmLabel: 'Disable', isDanger: true);
    if (confirmed != true || !mounted) return;
    String code = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verification Code'),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          onChanged: (v) => code = v,
          decoration: const InputDecoration(labelText: '6-digit code from your app'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger500),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (code.length != 6) return;
    try {
      await api.disable2fa(code);
      if (!mounted) return;
      context.read<AuthProvider>().refreshUser();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('2FA disabled')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid code')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user!;
    final has2fa = user.totpEnabled;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Back header
            Row(children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: AppColors.gray600, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              const Text('Security & 2FA', style: AppTextStyles.headline),
            ]),
            const SizedBox(height: 24),

            // ── Change Password ────────────────────────────────
            const Text('CHANGE PASSWORD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.gray500)),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (_pwError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.danger500.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Text(_pwError!,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.danger800)),
                  ),
                ],
                _passField('Current Password', _currentCtrl, _obscureCurrent, () => setState(() => _obscureCurrent = !_obscureCurrent)),
                const SizedBox(height: 12),
                _passField('New Password', _newCtrl, _obscureNew, () => setState(() => _obscureNew = !_obscureNew)),
                const SizedBox(height: 12),
                _passField('Confirm New Password', _confirmCtrl, _obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
                const SizedBox(height: 16),
                AppButton(label: 'Update Password', loading: _savingPw, onPressed: _changePassword),
              ]),
            ),

            const SizedBox(height: 24),

            // ── Two-Factor Authentication ──────────────────────
            const Text('TWO-FACTOR AUTH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.gray500)),
            const SizedBox(height: 10),
            GlassCard(
              tint: has2fa ? AppColors.success500 : null,
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: has2fa
                          ? AppColors.success500.withValues(alpha: 0.10)
                          : AppColors.gray100,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Icon(Icons.shield,
                        color: has2fa
                            ? AppColors.success500
                            : AppColors.gray400,
                        size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Authenticator App', style: AppTextStyles.title),
                    Text(has2fa ? 'Enabled — your account is protected' : 'Not enabled — add extra security',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: has2fa
                                ? AppColors.success700
                                : AppColors.gray500)),
                  ])),
                  if (has2fa)
                    const GlassBadge(text: 'ON', color: AppColors.success500)
                  else
                    const GlassBadge(text: 'OFF', color: AppColors.gray500),
                ]),

                // Setup flow
                if (!has2fa && _setupSecret == null) ...[
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Enable 2FA',
                    icon: Icons.qr_code,
                    loading: _saving2fa,
                    onPressed: _setup2fa,
                  ),
                ],

                if (!has2fa && _setupSecret != null) ...[
                  const SizedBox(height: 16),
                  const Text('Scan the QR code in your authenticator app, or enter this key manually:', style: AppTextStyles.body),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: SelectableText(_setupSecret!, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, letterSpacing: 2, color: AppColors.textPrimary), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.timer.copyWith(letterSpacing: 8),
                    decoration: const InputDecoration(hintText: '000000', counterText: '', labelText: 'Enter 6-digit code'),
                  ),
                  const SizedBox(height: 14),
                  AppButton(label: 'Verify & Enable', loading: _verifying, onPressed: _verify2fa),
                  const SizedBox(height: 8),
                  AppButton(label: 'Cancel', outline: true, onPressed: () => setState(() { _setupSecret = null; _codeCtrl.clear(); })),
                ],

                if (has2fa) ...[
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Disable 2FA',
                    outline: true,
                    color: AppColors.danger500,
                    icon: Icons.shield_outlined,
                    onPressed: _disable2fa,
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _passField(String label, TextEditingController ctrl, bool obscure, VoidCallback toggle) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline,
            size: 18, color: AppColors.gray400),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: AppColors.gray400),
          onPressed: toggle,
        ),
      ),
    );
  }
}
