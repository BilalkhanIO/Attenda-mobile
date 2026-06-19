import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('ACCOUNT'),
            const SizedBox(height: 12),
            _menuRow(context, Icons.person_outline, 'Edit Profile',
                () => context.push('/profile/edit')),
            _menuRow(context, Icons.shield_outlined, 'Security & 2FA',
                () => context.push('/profile/settings/security')),

            const SizedBox(height: 24),
            const _SectionLabel('PREFERENCES'),
            const SizedBox(height: 12),
            _menuRow(context, Icons.notifications_outlined, 'Notifications',
                () => context.push('/profile/settings/notifications')),
            _menuRow(context, Icons.palette_outlined, 'Appearance',
                () => context.push('/profile/settings/appearance')),
            _menuRow(context, Icons.track_changes_outlined, 'Tracking Reliability',
                () => context.push('/profile/settings/reliability')),

            const SizedBox(height: 32),
            AppButton(
              label: 'Sign Out',
              outline: true,
              color: AppColors.danger500,
              icon: Icons.logout,
              onPressed: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: 'Sign Out',
                  message: 'Are you sure you want to sign out?',
                  isDanger: true,
                  confirmLabel: 'Sign Out',
                );
                if (ok == true && context.mounted) {
                  await context.read<AuthProvider>().logout();
                }
              },
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Version 1.0.0 (Build 1)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuRow(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onTap: onTap,
        child: Row(children: [
          GradientIcon(
            icon: icon,
            size: 20,
            gradient: Theme.of(context).colorScheme.primary == AppColors.primary
                ? AppGradients.aurora
                : LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)]),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white))),
          Icon(Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.25), size: 18),
        ]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: Color(0x66FFFFFF))),
    );
  }
}
