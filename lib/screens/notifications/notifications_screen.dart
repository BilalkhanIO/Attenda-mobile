import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  int _unreadCount = 0;
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _total = 0;
  static const _limit = 20;

  static const _icons = <String, IconData>{
    'leave_request': Icons.event_note_outlined,
    'leave_approved': Icons.event_available_outlined,
    'leave_rejected': Icons.event_busy_outlined,
    'remote_request': Icons.home_work_outlined,
    'remote_approved': Icons.home_work_rounded,
    'remote_rejected': Icons.home_work_outlined,
    'remote_no_reply': Icons.notifications_paused_outlined,
    'attendance_late': Icons.schedule_rounded,
    'attendance_absent': Icons.person_off_outlined,
    'goal_assigned': Icons.flag_outlined,
    'review_submitted': Icons.rate_review_outlined,
    'payslip_ready': Icons.receipt_long_outlined,
    'shift_reminder': Icons.calendar_month_outlined,
    'late_notice': Icons.alarm_outlined,
    'late_notice_ack': Icons.task_alt_rounded,
    'late_pattern': Icons.trending_up_rounded,
    'attendance_late_escalation': Icons.warning_amber_rounded,
    'correction_request': Icons.edit_calendar_outlined,
    'correction_approved': Icons.event_available_outlined,
    'correction_rejected': Icons.event_busy_outlined,
    'expense_request': Icons.receipt_long_outlined,
    'expense_approved': Icons.payments_outlined,
    'expense_rejected': Icons.money_off_csred_outlined,
    'expense_reimbursed': Icons.account_balance_wallet_outlined,
    'document_added': Icons.description_outlined,
    'document_expiring': Icons.warning_amber_rounded,
    'onboarding_assigned': Icons.checklist_rounded,
    'onboarding_complete': Icons.verified_outlined,
    'kudos_received': Icons.workspace_premium_outlined,
    'announcement': Icons.campaign_outlined,
    'account_locked': Icons.lock_outline_rounded,
    'project_member_added': Icons.group_add_outlined,
    'project_task_assigned': Icons.assignment_ind_outlined,
    'project_task_comment': Icons.forum_outlined,
    'project_task_updated': Icons.sync_alt_rounded,
    'project_task_deadline': Icons.alarm_on_outlined,
    'emergency_shift_offer': Icons.add_alert_outlined,
    'emergency_shift_claimed': Icons.event_available_outlined,
    'shift_checkpoint_alert': Icons.qr_code_scanner_rounded,
  };

  /// Prefer the record action supplied by the backend, then fall back to the
  /// notification type. Routes only target screens that exist in mobile.
  static String? _routeFor(Map<String, dynamic> notification) {
    final type = notification['type'] as String? ?? '';
    final action = notification['action_type'] as String?;
    final actionId = notification['action_id'] as String?;

    if (action == 'project' && actionId != null) {
      return '/projects/${Uri.encodeComponent(actionId)}';
    }
    if (action == 'project_task' && actionId != null) {
      return '/projects?task_id=${Uri.encodeComponent(actionId)}';
    }

    if (action == 'remote_session' && actionId != null) {
      return '/home/remote/detail?id=${Uri.encodeComponent(actionId)}';
    }
    if (action == 'leave_request' ||
        action == 'expense_claim' && type == 'expense_request' ||
        action == 'overtime_request' ||
        action == 'shift_swap' && type.endsWith('_request') ||
        action == 'attendance_correction' && type == 'correction_request') {
      return '/profile/approvals';
    }
    if (action == 'attendance' || action == 'attendance_correction') {
      return '/attendance';
    }
    if (action == 'employee_document') return '/profile/documents';
    if (action == 'performance_goal' || action == 'performance_review') {
      return '/profile/performance';
    }
    if (action == 'expense_claim') return '/profile/expenses';
    if (action == 'shift_swap') return '/schedule';
    if (action == 'emergency_shift_offer') return '/schedule/open-shifts';
    if (action == 'shift_checkpoint') {
      return actionId == null
          ? '/schedule'
          : '/schedule/rounds?assignmentId=${Uri.encodeComponent(actionId)}';
    }

    if (type == 'announcement') return '/profile/announcements';
    if (type == 'kudos_received') return '/profile/kudos';
    if (type == 'payslip_ready') return '/profile/payslips';
    if (type.startsWith('expense_')) return '/profile/expenses';
    if (type.startsWith('document_')) return '/profile/documents';
    if (type.startsWith('onboarding_')) return '/profile/onboarding';
    if (type.startsWith('leave_')) return '/leave';
    if (type.startsWith('correction_') ||
        type.startsWith('attendance_') ||
        type.startsWith('late_')) return '/attendance';
    if (type.startsWith('shift_swap_') || type == 'shift_reminder') {
      return '/schedule';
    }
    if (type == 'emergency_shift_offer' || type == 'emergency_shift_claimed') {
      return '/schedule/open-shifts';
    }
    if (type == 'goal_assigned' || type == 'review_submitted') {
      return '/profile/performance';
    }
    if (type.startsWith('remote_')) return '/home/remote';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _page = 1;
      });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = reset ? 1 : _page;
      final data = await api.getNotifications(page: page, limit: _limit);
      final newItems = List<Map<String, dynamic>>.from(data['items'] as List);
      if (!mounted) return;
      setState(() {
        _total = data['total'] as int;
        _unreadCount = data['unread_count'] as int;
        if (reset) {
          _items = newItems;
          _page = 1;
        } else {
          _items.addAll(newItems);
        }
        _page++;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await api.markNotificationRead(id);
      setState(() {
        final idx = _items.indexWhere((n) => n['id'] == id);
        if (idx >= 0 && _items[idx]['read_at'] == null) {
          _items[idx] = {
            ..._items[idx],
            'read_at': DateTime.now().toIso8601String()
          };
          _unreadCount = (_unreadCount - 1).clamp(0, 9999);
        }
      });
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await api.markAllNotificationsRead();
      setState(() {
        final now = DateTime.now().toIso8601String();
        _items = _items
            .map((n) => n['read_at'] == null ? {...n, 'read_at': now} : n)
            .toList();
        _unreadCount = 0;
      });
    } catch (_) {}
  }

  Future<void> _delete(String id, bool wasUnread) async {
    try {
      await api.deleteNotification(id);
      setState(() {
        _items.removeWhere((n) => n['id'] == id);
        _total = (_total - 1).clamp(0, 9999);
        if (wasUnread) _unreadCount = (_unreadCount - 1).clamp(0, 9999);
      });
    } catch (_) {}
  }

  String _timeAgo(String? isoStr) {
    if (isoStr == null) return '';
    final diff = DateTime.now().difference(DateTime.parse(isoStr));
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications'),
            if (_unreadCount > 0)
              Text('$_unreadCount unread',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary)),
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary))
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_none_rounded,
                          size: 56, color: AppColors.gray300),
                      const SizedBox(height: 12),
                      const Text('No notifications yet',
                          style: AppTextStyles.body),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: () => _load(reset: true),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: _items.length + (_total > _items.length ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        // Defer: _load() calls setState, which is illegal
                        // synchronously inside a build/itemBuilder pass.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _load();
                        });
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                        );
                      }
                      final item = _items[index];
                      final route = _routeFor(item);
                      return _NotifTile(
                        notif: item,
                        icon: _icons[item['type']] ??
                            Icons.notifications_outlined,
                        timeAgo: _timeAgo(item['created_at'] as String?),
                        onMarkRead: () => _markRead(item['id'] as String),
                        onOpen: route != null
                            ? () async {
                                if (item['read_at'] == null) {
                                  await _markRead(item['id'] as String);
                                }
                                if (context.mounted) context.push(route);
                              }
                            : null,
                        onDelete: () => _delete(
                          item['id'] as String,
                          item['read_at'] == null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> notif;
  final IconData icon;
  final String timeAgo;
  final VoidCallback onMarkRead;

  /// Deep-link to the notification's screen; null when no target exists,
  /// in which case tapping only marks the notification read.
  final VoidCallback? onOpen;
  final VoidCallback onDelete;

  const _NotifTile({
    required this.notif,
    required this.icon,
    required this.timeAgo,
    required this.onMarkRead,
    this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = notif['read_at'] == null;

    final primary = Theme.of(context).colorScheme.primary;

    return Dismissible(
      key: Key(notif['id'] as String),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.danger500.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppColors.danger500),
      ),
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassCard(
          tint: isUnread ? primary : null,
          onTap: onOpen ?? (isUnread ? onMarkRead : null),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isUnread
                      ? primary.withValues(alpha: 0.10)
                      : AppColors.gray100,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notif['title'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isUnread ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notif['body'] as String? ?? '',
                      style: AppTextStyles.body.copyWith(height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text(timeAgo, style: AppTextStyles.caption),
                      if (isUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: primary, shape: BoxShape.circle),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              if (isUnread)
                GestureDetector(
                  onTap: onMarkRead,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Icon(Icons.done_rounded, size: 16, color: primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
