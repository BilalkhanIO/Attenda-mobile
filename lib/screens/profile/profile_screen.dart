import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await api.getMe();
      if (!mounted) return;
      setState(() {
        _profile = data;
      });
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user!;
    final themeController = context.watch<ThemeController>();

    final hasPayroll = auth.hasFeature('payroll');
    final hasPerformance = auth.hasFeature('performance_reviews');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Card
            _buildProfileCard(user, themeController),

            const SizedBox(height: 32),
            
            // Professional Section
            if (hasPayroll || hasPerformance) ...[
              const _SectionLabel('PROFESSIONAL'),
              const SizedBox(height: 12),
              if (hasPayroll)
                _menuRow(Icons.receipt_long_outlined, 'Payslips', 
                    () => context.push('/profile/payslips')),
              if (hasPerformance)
                _menuRow(Icons.trending_up_rounded, 'Performance', 
                    () => context.push('/profile/performance')),
              const SizedBox(height: 24),
            ],

            // Account Settings
            const _SectionLabel('ACCOUNT SETTINGS'),
            const SizedBox(height: 12),
            _menuRow(Icons.person_outline, 'Edit Profile',
                () => context.push('/profile/edit')),
            _menuRow(Icons.notifications_outlined, 'Notifications',
                () => context.push('/profile/settings/notifications')),
            _menuRow(Icons.shield_outlined, 'Security & 2FA',
                () => context.push('/profile/settings/security')),
            _menuRow(Icons.track_changes_outlined, 'Tracking Reliability',
                () => context.push('/profile/settings/reliability')),
            _menuRow(Icons.palette_outlined, 'Appearance',
                () => context.push('/profile/settings/appearance')),

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
          ],
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 18),
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

  Widget _buildProfileCard(AuthUser user, ThemeController themeController) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: themeController.primaryGradient,
                ),
                child: UserAvatar(
                  name: user.name,
                  imageUrl: _profile?['avatar_url'] as String?,
                  size: 64,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      _profile?['job_title'] ?? user.role.replaceAll('_', ' '),
                      style: TextStyle(
                          fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    Text(
                      _profile?['department'] ?? '',
                      style: TextStyle(
                          fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => context.push('/profile/edit'),
                icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 20),
              ),
            ],
          ),
          if (_profile != null) ...[
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('Employee ID', _profile?['employee_id'] ?? '—'),
                _statItem('Joined', _profile?['joined_date'] != null 
                    ? DateFormat('MMM yyyy').format(DateTime.parse(_profile!['joined_date']))
                    : '—'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: Color(0x66FFFFFF)));
  }
}
