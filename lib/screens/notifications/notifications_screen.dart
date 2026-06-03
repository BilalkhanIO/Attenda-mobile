import 'dart:ui';
import 'package:flutter/material.dart';
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
    'late_escalation':   '🚨',
  };

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
      setState(() { _loading = false; _loadingMore = false; });
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
                  style: const TextStyle(fontSize: 11, color: AppColors.primary600, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(fontSize: 12, color: AppColors.primary600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary600))
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 56, color: Colors.white.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      Text('No notifications yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primary600,
                  backgroundColor: AppColors.bgDark3,
                  onRefresh: () => _load(reset: true),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: _items.length + (_total > _items.length ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        _load();
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator(color: AppColors.primary600)),
                        );
                      }
                      return _NotifTile(
                        notif: _items[index],
                        icon: _icons[_items[index]['type']] ?? '🔔',
                        timeAgo: _timeAgo(_items[index]['created_at'] as String?),
                        onMarkRead: () => _markRead(_items[index]['id'] as String),
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
  final VoidCallback onDelete;

  const _NotifTile({
    required this.notif,
    required this.icon,
    required this.timeAgo,
    required this.onMarkRead,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = notif['read_at'] == null;

    return Dismissible(
      key: Key(notif['id'] as String),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.danger500.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.danger500.withValues(alpha: 0.4)),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger500),
      ),
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassCard(
          tint: isUnread ? AppColors.primary600 : null,
          onTap: isUnread ? onMarkRead : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: isUnread
                          ? AppColors.primary600.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: isUnread
                          ? Border.all(color: AppColors.primary600.withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notif['title'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notif['body'] as String? ?? '',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55), height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text(timeAgo, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.35))),
                      if (isUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(color: AppColors.primary600, shape: BoxShape.circle),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              if (isUnread)
                GestureDetector(
                  onTap: onMarkRead,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8, top: 2),
                    child: Icon(Icons.done_rounded, size: 16, color: AppColors.primary600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
