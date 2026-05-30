import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

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

  static const _icons = {
    'leave_request':    '📋',
    'leave_approved':   '✅',
    'leave_rejected':   '❌',
    'remote_request':   '🏠',
    'remote_approved':  '✅',
    'remote_rejected':  '❌',
    'remote_no_reply':  '⚠️',
    'attendance_late':  '⏰',
    'attendance_absent':'🚫',
    'goal_assigned':    '🎯',
    'review_submitted': '📊',
    'payslip_ready':    '💰',
    'shift_reminder':   '🔔',
  };

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

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
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
            if (_unreadCount > 0)
              Text('$_unreadCount unread', style: TextStyle(fontSize: 11, color: AppColors.primary600, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read', style: TextStyle(fontSize: 12, color: AppColors.primary600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_none_rounded, size: 56, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 12),
                      const Text('No notifications yet', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: ListView.builder(
                    itemCount: _items.length + (_total > _items.length ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        _load();
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
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
        color: const Color(0xFFEF4444),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: isUnread ? onMarkRead : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isUnread ? const Color(0xFFFFF1F1) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isUnread ? const Color(0xFFFDB0B1) : AppColors.gray100),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: isUnread ? const Color(0xFFFDE8E8) : AppColors.gray100,
                    borderRadius: BorderRadius.circular(20),
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
                          fontSize: 14,
                          fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        notif['body'] as String? ?? '',
                        style: TextStyle(fontSize: 12, color: AppColors.gray500, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(timeAgo, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                          if (isUnread) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(color: AppColors.primary600, shape: BoxShape.circle),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (isUnread)
                  GestureDetector(
                    onTap: onMarkRead,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Icon(Icons.done_rounded, size: 16, color: AppColors.primary600),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
