import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class RemoteDetailScreen extends StatefulWidget {
  final String sessionId;
  const RemoteDetailScreen({super.key, required this.sessionId});
  @override
  State<RemoteDetailScreen> createState() => _RemoteDetailScreenState();
}

class _RemoteDetailScreenState extends State<RemoteDetailScreen> {
  Map<String, dynamic>? _session;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final session = await api.getRemoteSessionLogs(widget.sessionId);
      if (mounted) setState(() { _session = session; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('My Remote Day')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary600))
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline, size: 40, color: AppColors.danger500),
                  const SizedBox(height: 12),
                  Text('Failed to load activity', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                  const SizedBox(height: 12),
                  AppButton(label: 'Retry', onPressed: _load),
                ]))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final logs      = (_session?['checkin_logs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final aiSummary = _session?['ai_summary'] as String?;
    final date      = _session?['attendance']?['date'] as String?;
    final duration  = (_session?['duration_type'] as String?)?.replaceAll('_', ' ') ?? '';
    final status    = _session?['status'] as String? ?? 'pending';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Session summary
        GlassCard(
          child: Row(children: [
            const Icon(Icons.home_rounded, color: AppColors.purple500, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                date != null ? DateFormat('EEEE, d MMMM yyyy').format(DateTime.parse(date)) : 'Today',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              Text(duration, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.55))),
            ])),
            _statusChip(status),
          ]),
        ),
        const SizedBox(height: 16),

        // AI Day Summary
        if (aiSummary != null) ...[
          GlassCard(
            tint: AppColors.purple500,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.auto_awesome, size: 14, color: AppColors.purple100),
                SizedBox(width: 6),
                Text('AI Day Summary',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.purple100)),
              ]),
              const SizedBox(height: 6),
              Text(aiSummary, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85))),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        const SectionHeader(title: 'Check-in Activity'),
        const SizedBox(height: 12),

        if (logs.isEmpty)
          const EmptyStateWidget(
            icon: Icons.chat_bubble_outline,
            title: 'No nudges yet',
            description: 'WhatsApp nudges are sent at shift start, midday, and end of day.',
          )
        else
          ...logs.map((log) => _buildNudgeCard(log)),
      ]),
    );
  }

  Widget _buildNudgeCard(Map<String, dynamic> log) {
    final nudgeType   = log['nudge_type'] as String? ?? '';
    final replyText   = log['reply_text'] as String?;
    final taskSummary = log['task_summary'] as String?;
    final blockers    = log['blockers'] as String?;
    final sentiment   = log['sentiment'] as String?;
    final sentAt      = log['nudge_sent_at'] as String?;
    final repliedAt   = log['reply_at'] as String?;
    final noReply     = log['no_reply_alerted'] as bool? ?? false;

    final label = nudgeType == 'morning' ? '🌅 Morning Check-in'
        : nudgeType == 'midday' ? '☀️ Midday Check-in'
        : '🌙 End of Day';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            if (sentAt != null)
              Text(DateFormat('HH:mm').format(DateTime.parse(sentAt).toLocal()),
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45))),
          ]),
          const SizedBox(height: 8),

          if (replyText != null) ...[
            // Reply bubble
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Your reply',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.5))),
                      if (repliedAt != null)
                        Text(DateFormat('HH:mm').format(DateTime.parse(repliedAt).toLocal()),
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
                    ]),
                    const SizedBox(height: 4),
                    Text(replyText, style: const TextStyle(fontSize: 13, color: Colors.white)),
                  ]),
                ),
              ),
            ),

            // AI interpretation
            if (taskSummary != null || sentiment != null || blockers != null) ...[
              const SizedBox(height: 8),
              GlassCard(
                tint: AppColors.purple500,
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.auto_awesome, size: 12, color: AppColors.purple100),
                    SizedBox(width: 4),
                    Text('AI Interpretation',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.purple100)),
                  ]),
                  const SizedBox(height: 6),
                  if (taskSummary != null)
                    Text('Working on: $taskSummary',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                  if (blockers != null) ...[
                    const SizedBox(height: 3),
                    Text('Blockers: $blockers',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                  ],
                  if (sentiment != null) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      Text('Mood: ', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
                      Text('${_sentimentEmoji(sentiment)} $sentiment',
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                    ]),
                  ],
                ]),
              ),
            ],
          ] else if (noReply) ...[
            const Row(children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.danger500),
              SizedBox(width: 6),
              Text('No reply — manager was notified',
                  style: TextStyle(fontSize: 12, color: AppColors.danger500)),
            ]),
          ] else ...[
            Text('Waiting for your WhatsApp reply…',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4), fontStyle: FontStyle.italic)),
          ],
        ]),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'approved': color = AppColors.success500; label = 'Approved'; break;
      case 'rejected': color = AppColors.danger500;  label = 'Rejected'; break;
      default:         color = AppColors.warning500; label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  String _sentimentEmoji(String s) => s == 'positive' ? '😊' : s == 'negative' ? '😟' : '😐';
}
