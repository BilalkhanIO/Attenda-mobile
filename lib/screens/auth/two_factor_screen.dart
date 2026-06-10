import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/attenda_logo.dart';

/// Completes a 2FA-challenged login. Receives the short-lived partial token
/// issued by /auth/login via GoRouter `extra`.
class TwoFactorScreen extends StatefulWidget {
  final String partialToken;
  const TwoFactorScreen({super.key, required this.partialToken});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().complete2faLogin(widget.partialToken, code);
      if (mounted) context.go('/home');
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      if (raw.contains('429')) {
        // Attempt limit reached — the partial token is burned; restart login.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Too many failed attempts. Please sign in again.'),
        ));
        context.go('/login');
        return;
      }
      setState(() {
        _error = raw.contains('401') && raw.toLowerCase().contains('token')
            ? 'Your session expired. Please sign in again.'
            : raw.contains('401')
                ? 'Invalid code. Please try again.'
                : 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.mesh),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),
                const AttendaLogo(iconSize: 48, variant: AttendaLogoVariant.dark),
                const SizedBox(height: 52),
                const Text('Two-factor authentication',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Text('Enter the 6-digit code from your authenticator app',
                    style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.55))),
                const SizedBox(height: 36),
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.danger500.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger500.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AppColors.danger500, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: AppColors.danger500, fontSize: 13, fontWeight: FontWeight.w500))),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],
                GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: TextField(
                    controller: _codeCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _verify(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 12),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                AppButton(label: 'Verify', onPressed: _verify, loading: _loading),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Back to sign in',
                        style: TextStyle(color: AppColors.primary600, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
