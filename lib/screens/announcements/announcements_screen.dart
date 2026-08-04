import 'package:flutter/material.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

/// Company announcements targeted at me (org-wide + my department).
/// Unread items show a bold title and a dot; tapping an item expands the
/// full body and fires the read receipt fire-and-forget, flipping the
/// local read state immediately. Reached from the Professional section
/// of the profile screen.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final Set<String> _expandedIds = {};

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
      final list = await api.getAnnouncements();
      if (!mounted) return;
      setState(() {
        _items = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiFailure.fromError(e).userMessage;
        _loading = false;
      });
    }
  }

  void _toggle(int index) {
    final item = _items[index];
    final id = item['id'] as String?;
    if (id == null) return;

    final nowExpanded = !_expandedIds.contains(id);
    setState(() {
      if (nowExpanded) {
        _expandedIds.add(id);
      } else {
        _expandedIds.remove(id);
      }
      if (nowExpanded && item['my_read_at'] == null) {
        _items[index] = {
          ...item,
          'my_read_at': DateTime.now().toIso8601String(),
        };
      }
    });

    if (nowExpanded && item['my_read_at'] == null) {
      // Fire-and-forget: the receipt is idempotent server-side, so a lost
      // request simply retries on a later open.
      api.markAnnouncementRead(id).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Announcements'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: primary,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: primary))
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      EmptyStateWidget(
                        icon: Icons.error_outline,
                        title: 'Couldn\'t load',
                        description: _error!,
                        action: AppButton(
                            label: 'Retry', onPressed: _load, fullWidth: false),
                      ),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          EmptyStateWidget(
                            icon: Icons.campaign_outlined,
                            title: 'No announcements',
                            description:
                                'Company announcements will appear here.',
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AnnouncementCard(
                            announcement: _items[i],
                            expanded: _expandedIds
                                .contains(_items[i]['id'] as String? ?? ''),
                            onTap: () => _toggle(i),
                          ),
                        ),
                      ),
      ),
    );
  }
}

/// "just now" / "5m ago" / "3h ago" / "2d ago" — same scale as the
/// notifications screen.
String announcementTimeAgo(String? isoStr) {
  if (isoStr == null) return '';
  final parsed = DateTime.tryParse(isoStr);
  if (parsed == null) return '';
  final diff = DateTime.now().difference(parsed);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// One announcement: author avatar + name, relative publish time, unread
/// dot/bold title while my_read_at is null, and the body — two collapsed
/// preview lines, or the full text when [expanded].
class AnnouncementCard extends StatelessWidget {
  static const unreadDotKey = Key('announcementUnreadDot');

  final Map<String, dynamic> announcement;
  final bool expanded;
  final VoidCallback? onTap;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    this.expanded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isUnread = announcement['my_read_at'] == null;
    final author =
        announcement['author'] is Map ? announcement['author'] as Map : const {};
    final authorName = author['name'] as String? ?? 'Unknown';
    final body = announcement['body'] as String? ?? '';
    final timeAgo =
        announcementTimeAgo(announcement['published_at'] as String?);

    return GlassCard(
      tint: isUnread ? primary : null,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UserAvatar(
            name: authorName,
            imageUrl: author['avatar_url'] as String?,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    announcement['title'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isUnread ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    Flexible(
                      child: Text(authorName,
                          style: AppTextStyles.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (timeAgo.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('·', style: AppTextStyles.caption),
                      const SizedBox(width: 6),
                      Text(timeAgo, style: AppTextStyles.caption),
                    ],
                  ]),
                ]),
          ),
          if (isUnread) ...[
            const SizedBox(width: 8),
            Container(
              key: unreadDotKey,
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
            ),
          ],
        ]),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            body,
            style: AppTextStyles.body.copyWith(height: 1.4),
            maxLines: expanded ? null : 2,
            overflow: expanded ? null : TextOverflow.ellipsis,
          ),
        ],
      ]),
    );
  }
}
