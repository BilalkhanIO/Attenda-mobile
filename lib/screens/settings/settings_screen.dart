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
    final auth = context.watch<AuthProvider>();
    // Approvals hub entry: shown for anyone who can review corrections or see
    // the team late summary; the role helper covers a failed capability fetch.
    final showApprovals = auth.hasPermission('attendance.override') ||
        auth.hasPermission('attendance.view_team') ||
        (auth.capabilities == null && (auth.user?.isManager ?? false));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('ACCOUNT'),
            const SizedBox(height: 12),
            _menuRow(context, Icons.person_outline, 'Edit Profile',
                () => context.push('/profile/edit')),
            _menuRow(context, Icons.shield_outlined, 'Security & 2FA',
                () => context.push('/profile/settings/security')),

            if (showApprovals) ...[
              const SizedBox(height: 24),
              const _SectionLabel('MANAGEMENT'),
              const SizedBox(height: 12),
              _menuRow(context, Icons.fact_check_outlined, 'Team Approvals',
                  () => context.push('/profile/approvals')),
            ],

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
                style: AppTextStyles.caption,
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
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary))),
          const Icon(Icons.chevron_right, color: AppColors.gray300, size: 18),
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
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.gray500)),
    );
  }
}
