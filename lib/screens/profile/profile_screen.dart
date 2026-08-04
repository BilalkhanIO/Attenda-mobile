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

  /// The Onboarding tile only appears while I have onboarding tasks —
  /// resolved on load like the rest of this screen's async data.
  bool _hasOnboardingTasks = false;

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
    try {
      final tasks = await api.getMyOnboardingTasks();
      if (!mounted) return;
      setState(() {
        _hasOnboardingTasks = tasks.isNotEmpty;
      });
    } catch (e) {
      // ignore — the tile simply stays hidden
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: Column(
          children: [
            // Profile Card (Header)
            _buildProfileHeader(user, themeController),

            const SizedBox(height: 24),
            
            // Professional Section — Expenses is available to everyone;
            // Payslips/Performance are feature-gated.
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
                _professionalCard(
                  context,
                  icon: Icons.request_quote_outlined,
                  label: 'Expenses',
                  onTap: () => context.push('/profile/expenses'),
                ),
                _professionalCard(
                  context,
                  icon: Icons.folder_outlined,
                  label: 'Documents',
                  onTap: () => context.push('/profile/documents'),
                ),
                _professionalCard(
                  context,
                  icon: Icons.campaign_outlined,
                  label: 'Announcements',
                  onTap: () => context.push('/profile/announcements'),
                ),
                if (_hasOnboardingTasks)
                  _professionalCard(
                    context,
                    icon: Icons.fact_check_outlined,
                    label: 'Onboarding',
                    onTap: () => context.push('/profile/onboarding'),
                  ),
                _professionalCard(
                  context,
                  icon: Icons.volunteer_activism_outlined,
                  label: 'Kudos',
                  onTap: () => context.push('/profile/kudos'),
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

            // Employment Details
            const SectionHeader(title: 'Employment'),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _infoRow(Icons.badge_outlined, 'Employee ID',
                      _profile?['employee_id'] ?? '—'),
                  _infoRow(Icons.business_outlined, 'Department',
                      _profile?['department'] ?? 'General'),
                  _infoRow(Icons.calendar_month_outlined, 'Joined', (() {
                    try {
                      final joined = _profile?['joined_date'];
                      if (joined == null) return '—';
                      return DateFormat('d MMMM yyyy')
                          .format(DateTime.parse(joined.toString()));
                    } catch (_) {
                      return '—';
                    }
                  })()),
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
          Icon(icon, size: 18, color: AppColors.gray400),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption),
                Text(
                  value,
                  style: AppTextStyles.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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
            Icon(icon, size: 28, color: primary),
            const SizedBox(height: 8),
            Text(label, style: AppTextStyles.bodyStrong),
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
            UserAvatar(
              name: user.name,
              imageUrl: _profile?['avatar_url'] as String?,
              size: 96,
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.camera_alt_outlined,
                  size: 16, color: AppColors.gray500),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(user.name, style: AppTextStyles.display),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Text(
            (_profile?['job_title'] ?? user.role.replaceAll('_', ' ')).toUpperCase(),
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: primary),
          ),
        ),
      ],
    );
  }
}
