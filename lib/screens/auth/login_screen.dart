import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/attenda_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure    = true;
  bool _loading    = false;
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
      final tempToken = await context.read<AuthProvider>().login(
        _emailCtrl.text.trim(), _passCtrl.text,
      );
      if (!mounted) return;
      if (tempToken != null) {
        context.go('/2fa', extra: tempToken);
      } else {
        context.go('/home');
      }
    } catch (e) {
      final failure = ApiFailure.fromError(e);
      setState(() {
        // Login-specific copy for bad credentials; everything else uses the
        // failure's own message.
        _error = failure is UnauthorizedFailure
            ? 'Invalid email or password'
            : failure.userMessage;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),

                // Logo
                const Center(
                  child: AttendaLogo(
                    iconSize: 64,
                    showWordmark: false,
                    variant: AttendaLogoVariant.light,
                  ),
                ),

                const SizedBox(height: 52),

                // Heading
                const Text('Welcome back', style: AppTextStyles.display),
                const SizedBox(height: 6),
                const Text('Sign in to your workspace',
                    style: AppTextStyles.body),
                const SizedBox(height: 36),

                // Error banner
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.danger500.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AppColors.danger500, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: AppColors.danger800, fontSize: 13, fontWeight: FontWeight.w500))),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],

                // Form card
                GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Form(
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
                          prefixIcon: Icon(Icons.mail_outline,
                              size: 20, color: AppColors.gray400),
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
                          prefixIcon: const Icon(Icons.lock_outline,
                              size: 20, color: AppColors.gray400),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.gray400,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v != null && v.isNotEmpty ? null : 'Password required',
                      ),
                    ]),
                  ),
                ),

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPassword,
                    child: Text('Forgot password?',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),

                AppButton(label: 'Sign In', onPressed: _login, loading: _loading),

                const SizedBox(height: 36),
                const Center(
                  child: Text(
                    "Don't have an account? Contact your HR Admin.",
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
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
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: GlassCard(
          borderRadius: AppRadius.card,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reset your password', style: AppTextStyles.headline),
              const SizedBox(height: 6),
              const Text("Enter your email and we'll send a reset link.",
                  style: AppTextStyles.body),
              const SizedBox(height: 20),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline,
                      size: 20, color: AppColors.gray400),
                ),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Send Reset Link',
                onPressed: () async {
                  final email = emailCtrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a valid email address')));
                    return;
                  }
                  Navigator.pop(ctx);
                  try { await api.forgotPassword(email); } catch (_) {}
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('If that email exists, a reset link has been sent.')),
                    );
                  }
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
