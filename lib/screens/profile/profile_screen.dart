import 'dart:ui';
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

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late final _tabCtrl = TabController(length: 3, vsync: this);
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _payslips = [];
  List<Map<String, dynamic>> _reviews  = [];
  List<Map<String, dynamic>> _goals    = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final [p, ps, rv, gl] = await Future.wait([
        api.getMe(), api.getMyPayslips(), api.getMyReviews(), api.getMyGoals(),
      ]);
      setState(() {
        _profile  = p  as Map<String, dynamic>;
        _payslips = (ps as List).cast<Map<String, dynamic>>();
        _reviews  = (rv as List).cast<Map<String, dynamic>>();
        _goals    = (gl as List).cast<Map<String, dynamic>>();
        _loading  = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 210,
            pinned: true,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          // Avatar with glass ring
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppGradients.primaryBtn,
                            ),
                            child: UserAvatar(
                              name: user.name,
                              imageUrl: _profile?['avatar_url'] as String?,
                              size: 68,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(user.name,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                          Text(
                            '${_profile?['job_title'] ?? user.role.replaceAll('_', ' ')} · ${_profile?['department'] ?? ''}',
                            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabCtrl,
              tabs: const [Tab(text: 'Overview'), Tab(text: 'Payslips'), Tab(text: 'Performance')],
            ),
          ),
        ],
        body: TabBarView(controller: _tabCtrl, children: [
          // Overview
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            child: Column(children: [
              if (_loading)
                const Center(child: CircularProgressIndicator(color: AppColors.primary600))
              else if (_profile != null)
                _infoCard([
                  ('Email',      _profile!['email']       as String? ?? '—'),
                  ('Phone',      _profile!['phone']       as String? ?? '—'),
                  ('Department', _profile!['department']  as String? ?? '—'),
                  ('Manager',    (_profile!['manager'] as Map?)?['name'] as String? ?? '—'),
                  ('Role',       user.role.replaceAll('_', ' ')),
                ]),
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
                  if (ok == true && mounted) {
                    await context.read<AuthProvider>().logout();
                  }
                },
              ),
            ]),
          ),

          // Payslips
          _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary600))
              : _payslips.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.receipt_long,
                      title: 'No payslips',
                      description: 'Your payslips will appear here once payroll is processed.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      itemCount: _payslips.length,
                      itemBuilder: (_, i) {
                        final p     = _payslips[i];
                        final month = p['period_month'] as int? ?? 1;
                        final year  = p['period_year']  as int? ?? DateTime.now().year;
                        final gross = p['gross_pay'];
                        final ready = p['status'] == 'processed';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            tint: ready ? AppColors.success500 : null,
                            child: Row(children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: ready ? AppColors.success500.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: ready ? AppColors.success500.withOpacity(0.4) : Colors.white.withOpacity(0.15)),
                                ),
                                child: Icon(Icons.receipt_long,
                                    color: ready ? AppColors.success500 : Colors.white.withOpacity(0.4), size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(DateFormat('MMMM yyyy').format(DateTime(year, month)),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                                Text(ready ? 'Ready to download' : 'Processing',
                                    style: TextStyle(fontSize: 12,
                                        color: ready ? AppColors.success500 : Colors.white.withOpacity(0.4))),
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                if (gross != null)
                                  Text('\$$gross',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                                if (ready)
                                  GestureDetector(
                                    onTap: () async {
                                      try {
                                        final res = await api.downloadPayslip(p['id'] as String);
                                        final url = res['url'] as String?;
                                        if (url != null) {
                                          final uri = Uri.parse(url);
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                                          }
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Download failed: $e')));
                                        }
                                      }
                                    },
                                    child: const Icon(Icons.download_outlined, size: 18, color: AppColors.primary600),
                                  ),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),

          // Performance
          _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary600))
              : _error != null
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.error_outline, size: 40, color: AppColors.danger500),
                      const SizedBox(height: 12),
                      const Text('Failed to load performance data', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                      const SizedBox(height: 8),
                      AppButton(label: 'Retry', onPressed: _load),
                    ]))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      children: [
                        const SectionHeader(title: 'My Reviews'),
                        const SizedBox(height: 12),
                        if (_reviews.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: EmptyStateWidget(
                              icon: Icons.trending_up,
                              title: 'No reviews yet',
                              description: 'Your performance reviews will appear here once submitted by your manager.',
                            ),
                          )
                        else
                          ..._reviews.map((r) {
                            final month     = r['period_month'] as int? ?? 1;
                            final year      = r['period_year']  as int? ?? DateTime.now().year;
                            final score     = r['overall_score'];
                            final stars     = r['manager_rating'] as int? ?? 0;
                            final submitted = r['submitted_at'] != null;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Text(DateFormat('MMMM yyyy').format(DateTime(year, month)),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                                  if (submitted && score != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (double.tryParse(score.toString()) ?? 0) >= 80
                                            ? AppColors.success100
                                            : AppColors.warning100,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text('$score/100', style: TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.w800,
                                          color: (double.tryParse(score.toString()) ?? 0) >= 80
                                              ? AppColors.success700
                                              : AppColors.warning800)),
                                    ),
                                ]),
                                if (submitted) ...[
                                  const SizedBox(height: 8),
                                  Row(children: List.generate(5, (j) => Icon(
                                      j < stars ? Icons.star_rounded : Icons.star_border_rounded,
                                      size: 18,
                                      color: AppColors.warning500))),
                                  if (r['notes'] != null) ...[
                                    const SizedBox(height: 6),
                                    Text(r['notes'] as String,
                                        style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.55)),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ],
                                ] else
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('Review pending',
                                        style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4))),
                                  ),
                              ])),
                            );
                          }),

                        const SizedBox(height: 8),
                        const SectionHeader(title: 'My Goals'),
                        const SizedBox(height: 12),
                        if (_goals.isEmpty)
                          const EmptyStateWidget(
                            icon: Icons.flag_outlined,
                            title: 'No goals set',
                            description: 'Goals assigned by your manager will appear here.',
                          )
                        else
                          ..._goals.map((g) {
                            final completion = (g['completion'] as num?)?.toInt() ?? 0;
                            final targetDate = g['target_date'] as String?;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Expanded(
                                    child: Text(g['title'] as String? ?? '—',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ),
                                  Text('${g['weight']}%',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
                                ]),
                                if (g['description'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(g['description'] as String,
                                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                                const SizedBox(height: 10),
                                Row(children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: completion / 100,
                                        minHeight: 6,
                                        backgroundColor: Colors.white.withOpacity(0.12),
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          completion >= 100
                                              ? AppColors.success500
                                              : completion >= 50
                                                  ? AppColors.primary600
                                                  : AppColors.warning500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('$completion%',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                                ]),
                                if (targetDate != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Due ${DateFormat('MMM d, yyyy').format(DateTime.parse(targetDate))}',
                                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
                                  ),
                                ],
                              ])),
                            );
                          }),
                      ],
                    ),
        ]),
      ),
    );
  }

  Widget _infoCard(List<(String, String)> items) => GlassCard(
    child: Column(
      children: items.map((item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(item.$1, style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.55))),
          Text(item.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
        ]),
      )).toList(),
    ),
  );
}
