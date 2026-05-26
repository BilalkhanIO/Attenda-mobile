import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  bool _obscure     = true;
  bool _loading     = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().login(_emailCtrl.text.trim(), _passCtrl.text);
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() { _error = _parseError(e.toString()); });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(String raw) {
    if (raw.contains('401')) return 'Invalid email or password';
    if (raw.contains('423')) return 'Account locked. Try again in 30 minutes.';
    if (raw.contains('SocketException') || raw.contains('Connection')) return 'Cannot connect to server. Check your network.';
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              // Logo
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppColors.primary600, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.wifi_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Text('Attenda', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.dark950)),
              ]),

              const SizedBox(height: 48),
              const Text('Welcome back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.dark950)),
              const SizedBox(height: 6),
              const Text('Sign in to your workspace', style: TextStyle(fontSize: 15, color: AppColors.gray500)),
              const SizedBox(height: 32),

              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.danger100, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: AppColors.danger800, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger800, fontSize: 13, fontWeight: FontWeight.w500))),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              Form(
                key: _formKey,
                child: Column(children: [
                  // Email
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Work Email',
                      hintText: 'you@company.com',
                      prefixIcon: Icon(Icons.mail_outline, size: 20, color: AppColors.gray500),
                    ),
                    validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20, color: AppColors.gray500),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: AppColors.gray500),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => v != null && v.isNotEmpty ? null : 'Password required',
                  ),
                ]),
              ),

              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showForgotPassword(),
                  child: const Text('Forgot password?', style: TextStyle(color: AppColors.primary600, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),

              AppButton(label: 'Sign In', onPressed: _login, loading: _loading),

              const SizedBox(height: 32),
              const Center(
                child: Text(
                  "Don't have an account? Contact your HR Admin.",
                  style: TextStyle(fontSize: 12, color: AppColors.gray500),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showForgotPassword() {
    final emailCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reset your password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Enter your email and we\'ll send a reset link.', style: TextStyle(color: AppColors.gray500)),
              const SizedBox(height: 20),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.mail_outline, size: 20, color: AppColors.gray500)),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Send Reset Link',
                onPressed: () async {
                  final email = emailCtrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email address')));
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    await api.forgotPassword(email);
                  } catch (_) {}
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('If that email exists, a reset link has been sent.')),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
