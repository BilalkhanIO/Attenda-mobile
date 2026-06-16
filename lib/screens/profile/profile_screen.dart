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
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/profile/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: Column(
          children: [
            // Profile Card (Header)
            _buildProfileHeader(user, themeController),

            const SizedBox(height: 24),
            
            // Professional Section
            if (hasPayroll || hasPerformance) ...[
              const SectionHeader(title: 'Professional'),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  if (hasPayroll)
                    _professionalCard(
                      context,
                      icon: Icons.receipt_long_outlined,
                      label: 'Payslips',
                      onTap: () => context.push('/profile/payslips'),
                    ),
                  if (hasPerformance)
                    _professionalCard(
                      context,
                      icon: Icons.trending_up_rounded,
                      label: 'Performance',
                      onTap: () => context.push('/profile/performance'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Employment Details
            const SectionHeader(title: 'Employment'),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _infoRow(Icons.badge_outlined, 'Employee ID', _profile?['employee_id'] ?? '—'),
                  _infoRow(Icons.business_outlined, 'Department', _profile?['department'] ?? 'General'),
                  _infoRow(Icons.calendar_month_outlined, 'Joined', _profile?['joined_date'] != null
                      ? DateFormat('d MMMM yyyy').format(DateTime.parse(_profile!['joined_date']))
                      : '—'),
                ],
              ),
            ),

            const SizedBox(height: 32),
            
            // Edit Profile Button (Quick Action)
            AppButton(
              label: 'Edit Profile Info',
              outline: true,
              icon: Icons.edit_outlined,
              onPressed: () => context.push('/profile/edit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _professionalCard(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap}) {
    final primary = Theme.of(context).colorScheme.primary;
    return GlassCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GradientIcon(
              icon: icon,
              size: 28,
              gradient: primary == AppColors.primary
                  ? AppGradients.aurora
                  : LinearGradient(colors: [primary, primary.withValues(alpha: 0.8)]),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(AuthUser user, ThemeController themeController) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        const SizedBox(height: 12),
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: themeController.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: UserAvatar(
                name: user.name,
                imageUrl: _profile?['avatar_url'] as String?,
                size: 96,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.bgDark3,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.camera_alt_outlined, size: 16, color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(user.name,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            (_profile?['job_title'] ?? user.role.replaceAll('_', ' ')).toUpperCase(),
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: primary),
          ),
        ),
      ],
    );
  }
}
