import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import 'give_kudos_sheet.dart';

/// Kudos: my received/given counts, the org-wide recognition feed and a
/// "Give Kudos" bottom sheet. Reached from the Professional section of
/// the profile screen. Deliberately available to every org member.
class KudosScreen extends StatefulWidget {
  const KudosScreen({super.key});
  @override
  State<KudosScreen> createState() => _KudosScreenState();
}

class _KudosScreenState extends State<KudosScreen> {
  List<Map<String, dynamic>> _feed = [];
  Map<String, dynamic> _mine = const {};
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
      final results =
          await Future.wait([api.getKudosFeed(), api.getMyKudos()]);
      if (!mounted) return;
      setState(() {
        _feed = (results[0] as List).cast<Map<String, dynamic>>();
        _mine = results[1] as Map<String, dynamic>;
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

  /// Recipient candidates: the org member list when the caller may list
  /// employees; otherwise (plain employees get a 403 on GET /users) the
  /// people already visible in the kudos feed.
  Future<List<Map<String, dynamic>>> _loadColleagues() async {
    final myId = context.read<AuthProvider>().user?.id;
    try {
      final list = await api.getOrgMembers();
      return list
          .cast<Map<String, dynamic>>()
          .where((u) => u['id'] != myId && u['is_active'] != false)
          .toList(growable: false);
    } catch (_) {
      return kudosFeedParticipants(_feed, excludeUserId: myId);
    }
  }

  Future<void> _giveKudos() async {
    final colleagues = await _loadColleagues();
    if (!mounted) return;
    final sent = await showGiveKudosSheet(context, colleagues: colleagues);
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kudos sent')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final received = _mine['received'] as int? ?? 0;
    final given = _mine['given'] as int? ?? 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Kudos'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _giveKudos,
          ),
        ],
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
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Row(children: [
                        Expanded(
                          child: KpiChip(
                            label: 'Received',
                            value: '$received',
                            color: primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: KpiChip(
                            label: 'Given',
                            value: '$given',
                            color: AppColors.info500,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      const SectionHeader(title: 'Latest'),
                      const SizedBox(height: 12),
                      if (_feed.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: EmptyStateWidget(
                            icon: Icons.volunteer_activism_outlined,
                            title: 'No kudos yet',
                            description:
                                'Be the first to recognise a colleague.',
                            action: AppButton(
                              label: 'Give Kudos',
                              onPressed: _giveKudos,
                              fullWidth: false,
                            ),
                          ),
                        )
                      else
                        for (final kudos in _feed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: KudosCard(kudos: kudos),
                          ),
                    ],
                  ),
      ),
    );
  }
}

/// "just now" / "5m ago" / "3h ago" / "2d ago" — same scale as the
/// notifications and announcements screens.
String kudosTimeAgo(String? isoStr) {
  if (isoStr == null) return '';
  final parsed = DateTime.tryParse(isoStr);
  if (parsed == null) return '';
  final diff = DateTime.now().difference(parsed);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Unique givers/recipients seen in [feed], sorted by name — the recipient
/// fallback for callers who can't list employees. [excludeUserId] drops the
/// signed-in user (no self-kudos).
List<Map<String, dynamic>> kudosFeedParticipants(
  List<Map<String, dynamic>> feed, {
  String? excludeUserId,
}) {
  final byId = <String, Map<String, dynamic>>{};
  for (final kudos in feed) {
    for (final side in ['giver', 'recipient']) {
      final user = kudos[side];
      if (user is Map && user['id'] is String) {
        final id = user['id'] as String;
        if (id != excludeUserId) byId[id] = user.cast<String, dynamic>();
      }
    }
  }
  return byId.values.toList(growable: false)
    ..sort((a, b) => (a['name'] as String? ?? '')
        .toLowerCase()
        .compareTo((b['name'] as String? ?? '').toLowerCase()));
}

/// One kudos: giver avatar, "giver → recipient", relative time, the emoji
/// and the message.
class KudosCard extends StatelessWidget {
  final Map<String, dynamic> kudos;
  const KudosCard({super.key, required this.kudos});

  @override
  Widget build(BuildContext context) {
    final giver = kudos['giver'] is Map ? kudos['giver'] as Map : const {};
    final recipient =
        kudos['recipient'] is Map ? kudos['recipient'] as Map : const {};
    final giverName = giver['name'] as String? ?? 'Unknown';
    final recipientName = recipient['name'] as String? ?? 'Unknown';
    final department = giver['department'] as String?;
    final emoji = kudos['emoji'] as String?;
    final message = kudos['message'] as String? ?? '';
    final timeAgo = kudosTimeAgo(kudos['created_at'] as String?);

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UserAvatar(
            name: giverName,
            imageUrl: giver['avatar_url'] as String?,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 5,
                    children: [
                      Text(giverName, style: AppTextStyles.bodyStrong),
                      const Icon(Icons.arrow_forward,
                          size: 12, color: AppColors.gray400),
                      Text(recipientName, style: AppTextStyles.bodyStrong),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (department != null && department.isNotEmpty) ...[
                      Flexible(
                        child: Text(department,
                            style: AppTextStyles.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Text('·', style: AppTextStyles.caption),
                      const SizedBox(width: 6),
                    ],
                    Text(timeAgo, style: AppTextStyles.caption),
                  ]),
                ]),
          ),
          if (emoji != null && emoji.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(emoji, style: const TextStyle(fontSize: 20)),
          ],
        ]),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(message, style: AppTextStyles.body.copyWith(height: 1.4)),
        ],
      ]),
    );
  }
}
