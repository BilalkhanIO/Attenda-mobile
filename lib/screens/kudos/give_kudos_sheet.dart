import 'package:flutter/material.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

/// Signature for sending kudos — injectable in widget tests.
typedef KudosSubmit = Future<void> Function(
  String toUserId,
  String message,
  String? emoji,
);

/// Emoji quick picks offered above the message field.
const kKudosEmojiQuickPicks = ['👏', '🎉', '🙌', '💡', '❤️'];

/// Friendly copy for the 20-per-day server cap (429 RATE_LIMITED).
const kKudosLimitMessage =
    'Daily kudos limit reached — try again tomorrow.';

/// Opens the give-kudos sheet. Resolves to `true` when kudos were sent.
/// [colleagues] is the recipient list resolved by the caller (org member
/// list, or feed participants when the caller can't list employees).
Future<bool?> showGiveKudosSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> colleagues,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true, // Show above the Bottom Navigation Bar
    isScrollControlled: true, // Keyboard pushes the sheet up
    backgroundColor: Colors.transparent,
    builder: (_) => GiveKudosSheet(colleagues: colleagues),
  );
}

/// Bottom sheet to give kudos: searchable recipient picker, emoji quick
/// picks and a 3–500 character message. Mirrors the API bounds so most
/// errors surface inline; the daily-cap 429 gets friendly copy.
class GiveKudosSheet extends StatefulWidget {
  /// Candidate recipients: `{id, name, avatar_url?, department?}` rows.
  final List<Map<String, dynamic>> colleagues;

  /// Overrides the API call in tests; defaults to [ApiService.giveKudos].
  final KudosSubmit? onSubmit;

  const GiveKudosSheet({super.key, required this.colleagues, this.onSubmit});

  @override
  State<GiveKudosSheet> createState() => _GiveKudosSheetState();
}

class _GiveKudosSheetState extends State<GiveKudosSheet> {
  final _searchCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String? _selectedId;
  String? _emoji;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return widget.colleagues;
    return widget.colleagues
        .where((u) =>
            (u['name'] as String? ?? '').toLowerCase().contains(term))
        .toList(growable: false);
  }

  /// Mirrors the API bounds: a recipient and a 3–500 char message.
  String? _validate() {
    if (_selectedId == null) return 'Choose a recipient.';
    final message = _messageCtrl.text.trim();
    if (message.length < 3) {
      return 'Message must be at least 3 characters.';
    }
    if (message.length > 500) {
      return 'Message must be 500 characters or less.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final submit = widget.onSubmit ??
          (String toUserId, String message, String? emoji) => api.giveKudos(
                toUserId: toUserId,
                message: message,
                emoji: emoji,
              );
      await submit(_selectedId!, _messageCtrl.text.trim(), _emoji);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final failure = ApiFailure.fromError(e);
      setState(() {
        _error = failure is RateLimitedFailure
            ? kKudosLimitMessage
            : failure.userMessage;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final filtered = _filtered;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: GlassCard(
            borderRadius: AppRadius.card,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppColors.gray300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Give Kudos', style: AppTextStyles.title),
                const SizedBox(height: 6),
                const Text(
                  'Recognise a colleague — it lands on the org feed.',
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: 20),

                // ── Recipient (search + pick) ─────────────────
                const Text('To', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search colleagues',
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: AppColors.gray400),
                  ),
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No colleagues found.',
                        style: AppTextStyles.body),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) =>
                          _colleagueRow(filtered[i], primary),
                    ),
                  ),
                const SizedBox(height: 16),

                // ── Emoji quick picks ─────────────────────────
                const Text('Emoji (optional)',
                    style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in kKudosEmojiQuickPicks)
                      GestureDetector(
                        onTap: () => setState(
                            () => _emoji = _emoji == e ? null : e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: _emoji == e
                                ? primary.withValues(alpha: 0.10)
                                : AppColors.gray100,
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Message (3–500 chars) ─────────────────────
                const Text('Message', style: AppTextStyles.captionStrong),
                const SizedBox(height: 6),
                TextField(
                  controller: _messageCtrl,
                  maxLines: 3,
                  maxLength: 500,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'What did they do well?',
                    counterText: '',
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.danger500)),
                ],
                const SizedBox(height: 16),
                AppButton(
                  label: 'Send Kudos',
                  icon: Icons.volunteer_activism_outlined,
                  loading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colleagueRow(Map<String, dynamic> user, Color primary) {
    final id = user['id'] as String? ?? '';
    final name = user['name'] as String? ?? 'Unknown';
    final department = user['department'] as String?;
    final selected = id == _selectedId;

    return InkWell(
      onTap: () => setState(() => _selectedId = id),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(children: [
          UserAvatar(
              name: name, imageUrl: user['avatar_url'] as String?, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: AppTextStyles.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (department != null && department.isNotEmpty)
                    Text(department, style: AppTextStyles.caption),
                ]),
          ),
          if (selected) Icon(Icons.check_circle, size: 18, color: primary),
        ]),
      ),
    );
  }
}
