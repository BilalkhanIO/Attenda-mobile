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
  List<Map<String, dynamic>> _payslips  = [];
  List<Map<String, dynamic>> _reviews   = [];
  List<Map<String, dynamic>> _goals     = [];
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
      backgroundColor: AppColors.gray50,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.dark950,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.dark950, AppColors.dark800], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(height: 32),
                      UserAvatar(name: user.name, imageUrl: _profile?['avatar_url'] as String?, size: 64),
                      const SizedBox(height: 12),
                      Text(user.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text('${_profile?['job_title'] ?? user.role} · ${_profile?['department'] ?? ''}',
                          style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    ]),
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabCtrl,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: AppColors.primary600,
              tabs: const [Tab(text: 'Overview'), Tab(text: 'Payslips'), Tab(text: 'Performance')],
            ),
          ),
        ],
        body: TabBarView(controller: _tabCtrl, children: [
          // Overview
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              if (_profile != null) ...[
                _infoCard([
                  ('Email',       _profile!['email']   as String? ?? '—'),
                  ('Phone',       _profile!['phone']   as String? ?? '—'),
                  ('Department',  _profile!['department'] as String? ?? '—'),
                  ('Manager',     (_profile!['manager'] as Map?)?['name'] as String? ?? '—'),
                  ('Role',        user.role.replaceAll('_', ' ')),
                ]),
              ] else if (_loading)
                const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              // Logout
              AppButton(
                label: 'Sign Out',
                outline: true,
                color: AppColors.danger500,
                icon: Icons.logout,
                onPressed: () async {
                  final ok = await showConfirmDialog(context, title: 'Sign Out', message: 'Are you sure you want to sign out?', isDanger: true, confirmLabel: 'Sign Out');
                  if (ok == true && mounted) {
                    await context.read<AuthProvider>().logout();
                  }
                },
              ),
            ]),
          ),

          // Payslips
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _payslips.isEmpty
                  ? const EmptyStateWidget(icon: Icons.receipt_long, title: 'No payslips', description: 'Your payslips will appear here once payroll is processed.')
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _payslips.length,
                      itemBuilder: (_, i) {
                        final p     = _payslips[i];
                        final month = p['period_month'] as int? ?? 1;
                        final year  = p['period_year']  as int? ?? 2026;
                        final gross = p['gross_pay'];
                        final ready = p['status'] == 'processed';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(color: ready ? AppColors.success100 : AppColors.gray100, borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.receipt_long, color: ready ? AppColors.success700 : AppColors.gray500, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(DateFormat('MMMM yyyy').format(DateTime(year, month)),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              Text(ready ? 'Ready to download' : 'Processing',
                                  style: TextStyle(fontSize: 12, color: ready ? AppColors.success700 : AppColors.gray500)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              if (gross != null)
                                Text('\$${gross}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dark950)),
                              if (ready)
                                GestureDetector(
                                  onTap: () async {
                                    try {
                                      final res = await api.downloadPayslip(p['id'] as String);
                                      final url = res['url'] as String?;
                                      if (url != null) {
                                        final uri = Uri.parse(url);
                                        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
                                    }
                                  },
                                  child: const Icon(Icons.download_outlined, size: 18, color: AppColors.primary600),
                                ),
                            ]),
                          ])),
                        );
                      },
                    ),

          // Performance
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.error_outline, size: 40, color: AppColors.danger500),
                      const SizedBox(height: 12),
                      const Text('Failed to load performance data', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      AppButton(label: 'Retry', onPressed: _load),
                    ]))
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // ── Reviews ──────────────────────────────
                        const Text('My Reviews', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dark950)),
                        const SizedBox(height: 12),
                        if (_reviews.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: EmptyStateWidget(icon: Icons.trending_up, title: 'No reviews yet', description: 'Your performance reviews will appear here once submitted by your manager.'),
                          )
                        else
                          ..._reviews.map((r) {
                            final month     = r['period_month'] as int? ?? 1;
                            final year      = r['period_year']  as int? ?? 2026;
                            final score     = r['overall_score'];
                            final stars     = r['manager_rating'] as int? ?? 0;
                            final submitted = r['submitted_at'] != null;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Text(DateFormat('MMMM yyyy').format(DateTime(year, month)),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                  if (submitted && score != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (double.tryParse(score.toString()) ?? 0) >= 80 ? AppColors.success100 : AppColors.warning100,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text('${score}/100',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                                              color: (double.tryParse(score.toString()) ?? 0) >= 80 ? AppColors.success700 : AppColors.warning800)),
                                    ),
                                ]),
                                if (submitted) ...[
                                  const SizedBox(height: 8),
                                  Row(children: List.generate(5, (j) => Icon(j < stars ? Icons.star_rounded : Icons.star_border_rounded, size: 18, color: AppColors.warning500))),
                                  if (r['notes'] != null) ...[
                                    const SizedBox(height: 6),
                                    Text(r['notes'] as String, style: const TextStyle(fontSize: 13, color: AppColors.gray500), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                ] else
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text('Review pending', style: TextStyle(fontSize: 13, color: AppColors.gray500)),
                                  ),
                              ])),
                            );
                          }),

                        // ── Goals ────────────────────────────────
                        const SizedBox(height: 8),
                        const Text('My Goals', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dark950)),
                        const SizedBox(height: 12),
                        if (_goals.isEmpty)
                          const EmptyStateWidget(icon: Icons.flag_outlined, title: 'No goals set', description: 'Goals assigned by your manager will appear here.')
                        else
                          ..._goals.map((g) {
                            final completion = (g['completion'] as num?)?.toInt() ?? 0;
                            final targetDate = g['target_date'] as String?;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Expanded(
                                    child: Text(g['title'] as String? ?? '—',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark950)),
                                  ),
                                  Text('${g['weight']}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.gray500)),
                                ]),
                                if (g['description'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(g['description'] as String, style: const TextStyle(fontSize: 12, color: AppColors.gray500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                                const SizedBox(height: 10),
                                Row(children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: completion / 100,
                                        minHeight: 6,
                                        backgroundColor: AppColors.gray100,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          completion >= 100 ? AppColors.success700 : completion >= 50 ? AppColors.primary600 : AppColors.warning800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('$completion%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark950)),
                                ]),
                                if (targetDate != null) ...[
                                  const SizedBox(height: 6),
                                  Text('Due ${DateFormat('MMM d, yyyy').format(DateTime.parse(targetDate))}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.gray500)),
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

  Widget _infoCard(List<(String, String)> items) => AppCard(
    child: Column(
      children: items.map((item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(item.$1, style: const TextStyle(fontSize: 14, color: AppColors.gray500)),
          Text(item.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark950)),
        ]),
      )).toList(),
    ),
  );
}
