import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  List<Map<String, dynamic>> _payslips = [];
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
      final results = await api.getMyPayslips();
      if (!mounted) return;
      setState(() {
        _payslips = results.cast<Map<String, dynamic>>();
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
        title: const Text('Payslips'),
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
              : _payslips.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.receipt_long,
                      title: 'No payslips',
                      description: 'Your payslips will appear here once payroll is processed.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      itemCount: _payslips.length,
                      itemBuilder: (context, i) {
                        final p = _payslips[i];
                        final month = p['period_month'] as int? ?? 1;
                        final year = p['period_year'] as int? ?? DateTime.now().year;
                        final gross = p['gross_pay'];
                        final ready = p['status'] == 'processed';
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            tint: ready ? AppColors.success500 : null,
                            child: Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: ready
                                      ? AppColors.success500.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: ready
                                          ? AppColors.success500.withValues(alpha: 0.4)
                                          : Colors.white.withValues(alpha: 0.15)),
                                ),
                                child: Icon(Icons.receipt_long,
                                    color: ready ? AppColors.success500 : Colors.white.withValues(alpha: 0.4),
                                    size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                    Text(DateFormat('MMMM yyyy').format(DateTime(year, month)),
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                    Text(ready ? 'Ready to download' : 'Processing',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: ready ? AppColors.success500 : Colors.white.withValues(alpha: 0.4))),
                                  ])),
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (gross != null)
                                      Text('\$$gross',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white)),
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
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                  content: Text(ApiFailure.fromError(e).userMessage)));
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
    );
  }
}
