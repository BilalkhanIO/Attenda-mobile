import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _payslips = [];
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _goals = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final results = await Future.wait([
        api.getMe(),
        auth.hasFeature('payroll') ? api.getMyPayslips() : Future.value([]),
        auth.hasFeature('performance_reviews')
            ? api.getMyReviews()
            : Future.value([]),
        auth.hasFeature('performance_reviews')
            ? api.getMyGoals()
            : Future.value([]),
      ]);

      setState(() {
        _profile = results[0] as Map<String, dynamic>;
        _payslips = (results[1] as List).cast<Map<String, dynamic>>();
        _reviews = (results[2] as List).cast<Map<String, dynamic>>();
        _goals = (results[3] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user!;

    final hasPayroll = auth.hasFeature('payroll');
    final hasPerformance = auth.hasFeature('performance_reviews');

    final tabWidgets = [
      if (hasPayroll) const Tab(text: 'Payslips'),
      if (hasPerformance) const Tab(text: 'Performance'),
    ];

    return DefaultTabController(
      length: tabWidgets.length,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              // This AppBar will be pinned at the top
              title: const Text('Profile'),
              pinned: true,
              centerTitle: true,
              backgroundColor: AppColors.bgDark, // Make it fully opaque
              elevation: 0,
              bottom: tabWidgets.isNotEmpty
                  ? TabBar(
                      tabs: tabWidgets,
                      indicatorColor: AppColors.primary,
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.onGlassMuted,
                    )
                  : null,
            ),
            SliverOverlapAbsorber(
              // This absorbs the space of the TabBar
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverToBoxAdapter(
                // This contains the profile card, settings, sign out
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Unified Profile Card
                      _buildUnifiedProfileCard(user),

                      const SizedBox(height: 24),
                      const Text('ACCOUNT SETTINGS',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: AppColors.onGlassMuted)),
                      const SizedBox(height: 12),
                      _settingsRow(Icons.person_outline, 'Edit Profile',
                          () => context.push('/profile/edit')),
                      _settingsRow(
                          Icons.notifications_outlined,
                          'Notification Preferences',
                          () =>
                              context.push('/profile/settings/notifications')),
                      _settingsRow(Icons.shield_outlined, 'Security & 2FA',
                          () => context.push('/profile/settings/security')),
                      _settingsRow(Icons.palette_outlined, 'Appearance',
                          () => context.push('/profile/settings/appearance')),

                      const SizedBox(height: 20),
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
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: tabWidgets.isEmpty
              ? const SizedBox.shrink()
              : TabBarView(
                  children: [
                    // Payslips
                    if (hasPayroll)
                      Builder(builder: (context) {
                        return CustomScrollView(
                          key: const PageStorageKey('payslips'),
                          slivers: [
                            SliverOverlapInjector(
                                handle: NestedScrollView
                                    .sliverOverlapAbsorberHandleFor(context)),
                            if (_loading)
                              const SliverFillRemaining(
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          color: AppColors.primary600)))
                            else if (_payslips.isEmpty)
                              const SliverFillRemaining(
                                child: EmptyStateWidget(
                                  icon: Icons.receipt_long,
                                  title: 'No payslips',
                                  description:
                                      'Your payslips will appear here once payroll is processed.',
                                ),
                              )
                            else
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 100),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, i) {
                                      final p = _payslips[i];
                                      final month =
                                          p['period_month'] as int? ?? 1;
                                      final year = p['period_year'] as int? ??
                                          DateTime.now().year;
                                      final gross = p['gross_pay'];
                                      final ready = p['status'] == 'processed';
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: GlassCard(
                                          tint: ready
                                              ? AppColors.success500
                                              : null,
                                          child: Row(children: [
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: ready
                                                    ? AppColors.success500
                                                        .withValues(alpha: 0.2)
                                                    : Colors.white
                                                        .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                    color: ready
                                                        ? AppColors.success500
                                                            .withValues(
                                                                alpha: 0.4)
                                                        : Colors.white
                                                            .withValues(
                                                                alpha: 0.15)),
                                              ),
                                              child: Icon(Icons.receipt_long,
                                                  color: ready
                                                      ? AppColors.success500
                                                      : Colors.white.withValues(
                                                          alpha: 0.4),
                                                  size: 20),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(
                                                      DateFormat('MMMM yyyy')
                                                          .format(DateTime(
                                                              year, month)),
                                                      style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Colors.white)),
                                                  Text(
                                                      ready
                                                          ? 'Ready to download'
                                                          : 'Processing',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: ready
                                                              ? AppColors
                                                                  .success500
                                                              : Colors.white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.4))),
                                                ])),
                                            Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  if (gross != null)
                                                    Text('\$$gross',
                                                        style: const TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color:
                                                                Colors.white)),
                                                  if (ready)
                                                    GestureDetector(
                                                      onTap: () async {
                                                        try {
                                                          final res = await api
                                                              .downloadPayslip(
                                                                  p['id']
                                                                      as String);
                                                          final url = res['url']
                                                              as String?;
                                                          if (url != null) {
                                                            final uri =
                                                                Uri.parse(url);
                                                            if (await canLaunchUrl(
                                                                uri)) {
                                                              await launchUrl(
                                                                  uri,
                                                                  mode: LaunchMode
                                                                      .externalApplication);
                                                            }
                                                          }
                                                        } catch (e) {
                                                          if (context.mounted) {
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                                    SnackBar(
                                                                        content:
                                                                            Text('Download failed: $e')));
                                                          }
                                                        }
                                                      },
                                                      child: const Icon(
                                                          Icons
                                                              .download_outlined,
                                                          size: 18,
                                                          color: AppColors
                                                              .primary600),
                                                    ),
                                                ]),
                                          ]),
                                        ),
                                      );
                                    },
                                    childCount: _payslips.length,
                                  ),
                                ),
                              ),
                          ],
                        );
                      }),

                    // Performance
                    if (hasPerformance)
                      Builder(builder: (context) {
                        return CustomScrollView(
                          key: const PageStorageKey('performance'),
                          slivers: [
                            SliverOverlapInjector(
                                handle: NestedScrollView
                                    .sliverOverlapAbsorberHandleFor(context)),
                            if (_loading)
                              const SliverFillRemaining(
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          color: AppColors.primary600)))
                            else if (_error != null)
                              SliverFillRemaining(
                                child: Center(
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.error_outline,
                                            size: 40,
                                            color: AppColors.danger500),
                                        const SizedBox(height: 12),
                                        const Text(
                                            'Failed to load performance data',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white)),
                                        const SizedBox(height: 8),
                                        AppButton(
                                            label: 'Retry', onPressed: _load),
                                      ]),
                                ),
                              )
                            else
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 100),
                                sliver: SliverList(
                                  delegate: SliverChildListDelegate([
                                    const SectionHeader(title: 'My Reviews'),
                                    const SizedBox(height: 12),
                                    if (_reviews.isEmpty)
                                      const EmptyStateWidget(
                                        icon: Icons.trending_up,
                                        title: 'No reviews yet',
                                        description:
                                            'Your performance reviews will appear here once submitted by your manager.',
                                      )
                                    else
                                      ..._reviews.map((r) {
                                        final month =
                                            r['period_month'] as int? ?? 1;
                                        final year = r['period_year'] as int? ??
                                            DateTime.now().year;
                                        final score = r['overall_score'];
                                        final stars =
                                            r['manager_rating'] as int? ?? 0;
                                        final submitted =
                                            r['submitted_at'] != null;
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: GlassCard(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                          DateFormat(
                                                                  'MMMM yyyy')
                                                              .format(DateTime(
                                                                  year, month)),
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 15,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: Colors
                                                                      .white)),
                                                      if (submitted &&
                                                          score != null)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 4),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: (double.tryParse(score
                                                                            .toString()) ??
                                                                        0) >=
                                                                    80
                                                                ? AppColors
                                                                    .success100
                                                                : AppColors
                                                                    .warning100,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        20),
                                                          ),
                                                          child: Text(
                                                              '$score/100',
                                                              style: TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  color: (double.tryParse(score.toString()) ??
                                                                              0) >=
                                                                          80
                                                                      ? AppColors
                                                                          .success700
                                                                      : AppColors
                                                                          .warning800)),
                                                        ),
                                                    ]),
                                                if (submitted) ...[
                                                  const SizedBox(height: 8),
                                                  Row(
                                                      children: List.generate(
                                                          5,
                                                          (j) => Icon(
                                                              j < stars
                                                                  ? Icons
                                                                      .star_rounded
                                                                  : Icons
                                                                      .star_border_rounded,
                                                              size: 18,
                                                              color: AppColors
                                                                  .warning500))),
                                                  if (r['notes'] != null) ...[
                                                    const SizedBox(height: 6),
                                                    Text(r['notes'] as String,
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: Colors.white
                                                                .withValues(
                                                                    alpha:
                                                                        0.55)),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                  ],
                                                ] else
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 4),
                                                    child: Text(
                                                        'Review pending',
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: Colors.white
                                                                .withValues(
                                                                    alpha:
                                                                        0.4))),
                                                  ),
                                              ])),
                                        );
                                      }),
                                    const SizedBox(height: 24),
                                    const SectionHeader(title: 'My Goals'),
                                    const SizedBox(height: 12),
                                    if (_goals.isEmpty)
                                      const EmptyStateWidget(
                                        icon: Icons.flag_outlined,
                                        title: 'No goals set',
                                        description:
                                            'Goals assigned by your manager will appear here.',
                                      )
                                    else
                                      ..._goals.map((g) {
                                        final completion =
                                            (g['completion'] as num?)
                                                    ?.toInt() ??
                                                0;
                                        final targetDate =
                                            g['target_date'] as String?;
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: GlassCard(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                            g['title']
                                                                    as String? ??
                                                                '—',
                                                            style: const TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: Colors
                                                                    .white)),
                                                      ),
                                                      Text('${g['weight']}%',
                                                          style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Colors
                                                                  .white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.5))),
                                                    ]),
                                                if (g['description'] !=
                                                    null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                      g['description']
                                                          as String,
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.white
                                                              .withValues(
                                                                  alpha: 0.5)),
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                ],
                                                const SizedBox(height: 10),
                                                Row(children: [
                                                  Expanded(
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                      child:
                                                          LinearProgressIndicator(
                                                        value: completion / 100,
                                                        minHeight: 6,
                                                        backgroundColor: Colors
                                                            .white
                                                            .withValues(
                                                                alpha: 0.12),
                                                        valueColor:
                                                            AlwaysStoppedAnimation<
                                                                Color>(
                                                          completion >= 100
                                                              ? AppColors
                                                                  .success500
                                                              : completion >= 50
                                                                  ? AppColors
                                                                      .primary600
                                                                  : AppColors
                                                                      .warning500,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text('$completion%',
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Colors.white)),
                                                ]),
                                                if (targetDate != null) ...[
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'Due ${DateFormat('MMM d, yyyy').format(DateTime.parse(targetDate))}',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.white
                                                            .withValues(
                                                                alpha: 0.4)),
                                                  ),
                                                ],
                                              ])),
                                        );
                                      }),
                                  ]),
                                ),
                              ),
                          ],
                        );
                      }),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _settingsRow(IconData icon, String label, VoidCallback onTap) {
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
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white))),
          Icon(Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.35), size: 18),
        ]),
      ),
    );
  }

  Widget _buildUnifiedProfileCard(AuthUser user) {
    final items = [
      ('Email', _profile?['email'] as String? ?? '—'),
      ('Phone', _profile?['phone'] as String? ?? '—'),
      ('Department', _profile?['department'] as String? ?? '—'),
      ('Manager', (_profile?['manager'] as Map?)?['name'] as String? ?? '—'),
      ('Role', user.role.replaceAll('_', ' ')),
    ];

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        children: [
          // Identity Header Section
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.primaryBtn,
                  ),
                  child: UserAvatar(
                    name: user.name,
                    imageUrl: _profile?['avatar_url'] as String?,
                    size: 72,
                  ),
                ),
                const SizedBox(height: 14),
                Text(user.name,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  '${_profile?['job_title'] ?? user.role.replaceAll('_', ' ')} · ${_profile?['department'] ?? ''}',
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: AppColors.glass12),
          const SizedBox(height: 12),
          // Detail Rows
          ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.$1,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.onGlassMuted)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(item.$2,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                    ]),
              )),
        ],
      ),
    );
  }
}
