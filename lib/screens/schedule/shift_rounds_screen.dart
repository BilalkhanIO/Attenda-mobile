import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class ShiftRoundsScreen extends StatefulWidget {
  const ShiftRoundsScreen({super.key, required this.assignmentId});
  final String assignmentId;

  @override
  State<ShiftRoundsScreen> createState() => _ShiftRoundsScreenState();
}

class _ShiftRoundsScreenState extends State<ShiftRoundsScreen> {
  List<Map<String, dynamic>> _checkpoints = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await api.getAssignmentCheckpoints(widget.assignmentId);
      if (!mounted) return;
      setState(() {
        _checkpoints = result.cast<Map<String, dynamic>>();
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = ApiFailure.fromError(error).userMessage;
        _loading = false;
      });
    }
  }

  Future<void> _scan() async {
    final didScan = await context.push<bool>(
      '/schedule/checkpoint-scan?assignmentId=${Uri.encodeComponent(widget.assignmentId)}',
    );
    if (didScan == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final required =
        _checkpoints.where((item) => item['required'] == true).length;
    final completed = _checkpoints
        .where((item) =>
            item['required'] == true && (item['scan_count'] as num? ?? 0) > 0)
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Safety round')),
      body: RefreshIndicator(
        color: primary,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 100),
                    EmptyStateWidget(
                        icon: Icons.error_outline_rounded,
                        title: 'Could not load checkpoints',
                        description: _error!,
                        action: AppButton(
                            label: 'Retry', onPressed: _load, fullWidth: false))
                  ])
                : _checkpoints.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.qr_code_2_rounded,
                        title: 'No checkpoints',
                        description:
                            'There are no active safety checkpoints for this shift.')
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          GlassCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(Icons.shield_outlined, color: primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Text(
                                            '$completed of $required required points checked',
                                            style: AppTextStyles.title)),
                                  ]),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                          value: required == 0
                                              ? 1
                                              : completed / required,
                                          minHeight: 7,
                                          backgroundColor:
                                              primary.withValues(alpha: 0.12),
                                          color: primary)),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                      width: double.infinity,
                                      child: AppButton(
                                          label: 'Scan checkpoint QR',
                                          icon: Icons.qr_code_scanner_rounded,
                                          onPressed: _scan)),
                                ]),
                          ),
                          const SizedBox(height: 16),
                          for (var i = 0; i < _checkpoints.length; i++)
                            _CheckpointTile(
                                index: i + 1, checkpoint: _checkpoints[i]),
                          const SizedBox(height: 12),
                          const Text(
                              'Scan the QR code physically placed at each location. Every visit is timestamped on your shift record.',
                              style: AppTextStyles.caption),
                        ],
                      ),
      ),
    );
  }
}

class _CheckpointTile extends StatelessWidget {
  const _CheckpointTile({required this.index, required this.checkpoint});
  final int index;
  final Map<String, dynamic> checkpoint;

  @override
  Widget build(BuildContext context) {
    final count = (checkpoint['scan_count'] as num? ?? 0).toInt();
    final scannedAt = checkpoint['last_scanned_at'] as String?;
    final scanned = count > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: scanned
                      ? AppColors.success500.withValues(alpha: 0.14)
                      : AppColors.gray200,
                  borderRadius: BorderRadius.circular(11)),
              child: scanned
                  ? const Icon(Icons.check_rounded,
                      color: AppColors.success500, size: 19)
                  : Text('$index', style: AppTextStyles.bodyStrong)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                      child: Text(checkpoint['name'] as String? ?? 'Checkpoint',
                          style: AppTextStyles.title)),
                  if (checkpoint['required'] == true)
                    const Text('REQUIRED',
                        style: TextStyle(
                            color: AppColors.warning500,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8))
                ]),
                if ((checkpoint['instructions'] as String?)?.isNotEmpty ==
                    true) ...[
                  const SizedBox(height: 5),
                  Text(checkpoint['instructions'] as String,
                      style: AppTextStyles.body),
                ],
                const SizedBox(height: 7),
                Text(
                    scannedAt != null
                        ? 'Last checked ${DateFormat('h:mm a').format(DateTime.parse(scannedAt).toLocal())} · $count scan${count == 1 ? '' : 's'}'
                        : 'Not checked yet',
                    style: AppTextStyles.caption),
              ])),
        ]),
      ),
    );
  }
}
