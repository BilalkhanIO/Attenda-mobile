import 'package:flutter/material.dart';
import '../../../utils/theme.dart';
import '../../../widgets/common.dart';

/// Compact "Who's out today" list: one row per teammate on approved leave or
/// working remotely. Callers hide the whole section when both lists are empty.
class WhosOutCard extends StatelessWidget {
  /// Rows from /org/whos-out `on_leave`:
  /// `{leave_type, is_half_day, user: {name, avatar_url}}`.
  final List<Map<String, dynamic>> onLeave;

  /// Rows from /org/whos-out `remote`: `{user: {name, avatar_url}}`.
  final List<Map<String, dynamic>> remote;

  const WhosOutCard({super.key, this.onLeave = const [], this.remote = const []});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      ...onLeave.map((e) => _row(
            context,
            user: e['user'],
            label: _leaveLabel(e),
            color: Theme.of(context).colorScheme.primary,
          )),
      ...remote.map((e) => _row(
            context,
            user: e['user'],
            label: 'Remote',
            color: AppColors.info500,
          )),
    ];

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(children: rows),
    );
  }

  String _leaveLabel(Map<String, dynamic> e) {
    final type =
        (e['leave_type'] as String? ?? 'leave').replaceAll('_', ' ');
    final isHalf = e['is_half_day'] as bool? ?? false;
    return isHalf ? '$type · ½ day' : type;
  }

  Widget _row(BuildContext context,
      {required dynamic user, required String label, required Color color}) {
    final u = user is Map ? user.cast<String, dynamic>() : <String, dynamic>{};
    final name = u['name'] as String? ?? 'Teammate';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        UserAvatar(name: name, imageUrl: u['avatar_url'] as String?, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(name,
              style: AppTextStyles.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        GlassBadge(text: label, color: color),
      ]),
    );
  }
}
