import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _goals = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        api.getMyReviews(),
        api.getMyGoals(),
      ]);

      if (!mounted) return;
      setState(() {
        _reviews = results[0].cast<Map<String, dynamic>>();
        _goals = results[1].cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiFailure.fromError(e).userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Performance'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary600))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.danger500),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 24),
                      AppButton(label: 'Retry', onPressed: _load, fullWidth: false),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  children: [
                    const SectionHeader(title: 'My Reviews'),
                    const SizedBox(height: 12),
                    if (_reviews.isEmpty)
                      const EmptyStateWidget(
                        icon: Icons.trending_up,
                        title: 'No reviews yet',
                        description: 'Your performance reviews will appear here once submitted by your manager.',
                      )
                    else
                      ..._reviews.map((r) {
                        final month = r['period_month'] as int? ?? 1;
                        final year = r['period_year'] as int? ?? DateTime.now().year;
                        final score = r['overall_score'];
                        final stars = r['manager_rating'] as int? ?? 0;
                        final submitted = r['submitted_at'] != null;
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(DateFormat('MMMM yyyy').format(DateTime(year, month)),
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                      if (submitted && score != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: (double.tryParse(score.toString()) ?? 0) >= 80
                                                ? AppColors.success100
                                                : AppColors.warning100,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text('$score/100',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800,
                                                  color: (double.tryParse(score.toString()) ?? 0) >= 80
                                                      ? AppColors.success700
                                                      : AppColors.warning800)),
                                        ),
                                    ]),
                                if (submitted) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                      children: List.generate(
                                          5,
                                          (j) => Icon(j < stars ? Icons.star_rounded : Icons.star_border_rounded,
                                              size: 18, color: AppColors.warning500))),
                                  if (r['notes'] != null) ...[
                                    const SizedBox(height: 6),
                                    Text(r['notes'] as String,
                                        style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.55)),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ],
                                ] else
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('Review pending',
                                        style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4))),
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
                        description: 'Goals assigned by your manager will appear here.',
                      )
                    else
                      ..._goals.map((g) {
                        final completion = (g['completion'] as num?)?.toInt() ?? 0;
                        final targetDate = g['target_date'] as String?;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Expanded(
                                    child: Text(g['title'] as String? ?? '—',
                                        style: const TextStyle(
                                            fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ),
                                  Text('${g['weight']}%',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white.withValues(alpha: 0.5))),
                                ]),
                                if (g['description'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(g['description'] as String,
                                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                                const SizedBox(height: 10),
                                Row(children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: completion / 100,
                                        minHeight: 6,
                                        backgroundColor: Colors.white.withValues(alpha: 0.12),
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
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                                ]),
                                if (targetDate != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Due ${DateFormat('MMM d, yyyy').format(DateTime.parse(targetDate))}',
                                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
                                  ),
                                ],
                              ])),
                        );
                      }),
                  ],
                ),
    );
  }
}
