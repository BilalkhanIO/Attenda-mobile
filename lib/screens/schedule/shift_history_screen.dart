import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen({super.key});
  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  List<Map<String, dynamic>> _events = [];
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
      final events = await api.getShiftScheduleHistory();
      if (mounted)
        setState(() {
          _events = events.cast<Map<String, dynamic>>();
          _loading = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = ApiFailure.fromError(error).userMessage;
          _loading = false;
        });
    }
  }

  String _label(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Schedule history')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: EmptyStateWidget(
                      icon: Icons.error_outline,
                      title: 'Could not load history',
                      description: _error!,
                      action: AppButton(
                          label: 'Retry', onPressed: _load, fullWidth: false)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _events.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          EmptyStateWidget(
                              icon: Icons.history_rounded,
                              title: 'No schedule activity',
                              description:
                                  'Assignment and publishing activity will appear here.')
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                          itemCount: _events.length,
                          itemBuilder: (context, index) {
                            final event = _events[index];
                            final actor =
                                (event['actor'] as Map?)?['name'] as String? ??
                                    'System';
                            final details = (event['details'] as Map?)
                                    ?.cast<String, dynamic>() ??
                                const <String, dynamic>{};
                            final detail = details.entries
                                .where((entry) =>
                                    entry.value == null ||
                                    entry.value is String ||
                                    entry.value is num ||
                                    entry.value is bool)
                                .map((entry) =>
                                    '${_label(entry.key)}: ${entry.value ?? '—'}')
                                .join(' · ');
                            final created = DateTime.tryParse(
                                event['created_at'] as String? ?? '');
                            return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassCard(
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      const Icon(Icons.circle,
                                          size: 10,
                                          color: AppColors.primary600),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(
                                                '$actor · ${_label(event['event_type'] as String? ?? 'updated')}',
                                                style:
                                                    AppTextStyles.bodyStrong),
                                            if (detail.isNotEmpty)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Text(detail,
                                                      style:
                                                          AppTextStyles.body)),
                                            if (created != null)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Text(
                                                      DateFormat(
                                                              'MMM d, yyyy · h:mm a')
                                                          .format(created
                                                              .toLocal()),
                                                      style:
                                                          const TextStyle(
                                                              color: AppColors
                                                                  .gray500,
                                                              fontSize: 11)))
                                          ]))
                                    ])));
                          })));
}
