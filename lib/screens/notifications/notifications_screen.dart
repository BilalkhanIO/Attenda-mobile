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
  bool _loading    = true;
  bool _loadingMore= false;
  int  _page       = 1;
  int  _total      = 0;
  static const _limit = 20;

  static const _icons = {
    'leave_request':     '📋',
    'leave_approved':    '✅',
    'leave_rejected':    '❌',
    'remote_request':    '🏠',
    'remote_approved':   '✅',
    'remote_rejected':   '❌',
    'remote_no_reply':   '⚠️',
    'attendance_late':   '⏰',
    'attendance_absent': '🚫',
    'goal_assigned':     '🎯',
    'review_submitted':  '📊',
    'payslip_ready':     '💰',
    'shift_reminder':    '🔔',
    'late_notice':       '⏳',
    'late_notice_ack':   '👍',
    'late_pattern':      '📈',
    // The server type is 'attendance_late_escalation'.
    'attendance_late_escalation': '🚨',
    'correction_request':  '✏️',
    'correction_approved': '✅',
    'correction_rejected': '❌',
    'expense_request':     '🧾',
    'expense_approved':    '✅',
    'expense_rejected':    '❌',
    'expense_reimbursed':  '💸',
    'document_added':      '📄',
    'document_expiring':   '⚠️',
    'onboarding_assigned': '📝',
    'onboarding_complete': '🎉',
    'kudos_received':      '👏',
    'announcement':        '📣',
    'account_locked':      '🔒',
  };

  /// Deep-link target for a notification type, or null when no screen
  /// exists for it (unknown types keep the mark-read-only behavior).
  static String? _routeFor(String? type) {
    if (type == null) return null;
    if (type == 'announcement') return '/profile/announcements';
    if (type == 'kudos_received') return '/profile/kudos';
    if (type == 'payslip_ready') return '/profile/payslips';
    if (type.startsWith('expense_')) return '/profile/expenses';
    if (type.startsWith('document_')) return '/profile/documents';
    if (type.startsWith('onboarding_')) return '/profile/onboarding';
    if (type.startsWith('leave_')) return '/leave';
    if (type.startsWith('correction_')) return '/attendance';
    return null;
  }

  @override
  void initState() { super.initState(); _load(reset: true); }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() { _loading = true; _page = 1; });
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
        _total       = data['total'] as int;
        _unreadCount = data['unread_count'] as int;
        if (reset) {
          _items = newItems;
          _page  = 1;
        } else {
          _items.addAll(newItems);
        }
        _page++;
        _loading     = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await api.markNotificationRead(id);
      setState(() {
        final idx = _items.indexWhere((n) => n['id'] == id);
        if (idx >= 0 && _items[idx]['read_at'] == null) {
          _items[idx] = {..._items[idx], 'read_at': DateTime.now().toIso8601String()};
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
        _items = _items.map((n) => n['read_at'] == null ? {...n, 'read_at': now} : n).toList();
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
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
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
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
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
                          child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
                        );
                      }
                      final route =
                          _routeFor(_items[index]['type'] as String?);
                      return _NotifTile(
                        notif: _items[index],
                        icon: _icons[_items[index]['type']] ?? '🔔',
                        timeAgo: _timeAgo(_items[index]['created_at'] as String?),
                        onMarkRead: () => _markRead(_items[index]['id'] as String),
                        onOpen:
                            route != null ? () => context.push(route) : null,
                        onDelete: () => _delete(
                          _items[index]['id'] as String,
                          _items[index]['read_at'] == null,
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
  final String icon;
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
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger500),
      ),
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassCard(
          tint: isUnread ? primary : null,
          onTap: isUnread || onOpen != null
              ? () {
                  if (isUnread) onMarkRead();
                  onOpen?.call();
                }
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isUnread
                      ? primary.withValues(alpha: 0.10)
                      : AppColors.gray100,
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
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
                        fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
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
                          width: 6, height: 6,
                          decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
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
