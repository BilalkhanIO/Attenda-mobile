import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

/// My documents: the HR document vault entries that belong to me (contracts,
/// IDs, visas, certificates). Tapping a document fetches a short-lived
/// presigned link and opens it externally. Reached from the Professional
/// section of the profile screen.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  String? _error;
  String? _openingId;

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
      final list = await api.getMyDocuments();
      if (!mounted) return;
      setState(() {
        _docs = list.cast<Map<String, dynamic>>();
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

  Future<void> _open(Map<String, dynamic> doc) async {
    final id = doc['id'] as String?;
    if (id == null || _openingId != null) return;
    setState(() => _openingId = id);
    try {
      final res = await api.getDocumentDownload(id);
      final url = res['download_url'] as String?;
      if (url == null) return;
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t open the document')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(e).userMessage)),
        );
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final currentUserId = context.watch<AuthProvider>().user?.id;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('My Documents'),
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
                : _docs.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          EmptyStateWidget(
                            icon: Icons.folder_outlined,
                            title: 'No documents',
                            description:
                                'Documents your HR team shares will appear here.',
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: _docs.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: DocumentCard(
                            doc: _docs[i],
                            currentUserId: currentUserId,
                            opening: _openingId == _docs[i]['id'],
                            onTap: () => _open(_docs[i]),
                          ),
                        ),
                      ),
      ),
    );
  }
}

/// Formats a byte count as "512 KB" / "1.5 MB"; tolerates string values.
String formatFileSize(dynamic bytes) {
  final value = bytes is num ? bytes : num.tryParse('$bytes') ?? 0;
  if (value <= 0) return '—';
  final kb = value / 1024;
  if (kb < 1024) return '${kb.ceil()} KB';
  return '${NumberFormat('#,##0.#').format(kb / 1024)} MB';
}

/// "contract" → "Contract", "work_permit" → "Work permit".
String formatDocumentCategory(String? category) {
  if (category == null || category.isEmpty) return '—';
  final cleaned = category.replaceAll('_', ' ');
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

/// One of my documents: title, category chip, file size, an expiry line
/// (warning-tinted within 30 days, danger once past), and the uploader when
/// it wasn't me.
class DocumentCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final String? currentUserId;
  final bool opening;
  final VoidCallback? onTap;

  const DocumentCard({
    super.key,
    required this.doc,
    this.currentUserId,
    this.opening = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final title = doc['title'] as String? ?? doc['file_name'] as String? ?? '—';
    final uploader =
        doc['uploader'] is Map ? doc['uploader'] as Map : const {};
    final uploaderName = uploader['name'] as String?;
    final uploadedByOther = uploader['id'] != null &&
        currentUserId != null &&
        uploader['id'] != currentUserId;

    DateTime? expiresAt;
    final rawExpiry = doc['expires_at'];
    if (rawExpiry is String) expiresAt = DateTime.tryParse(rawExpiry);

    String? expiryLabel;
    Color expiryColor = AppColors.gray500;
    IconData expiryIcon = Icons.event_outlined;
    if (expiresAt != null) {
      final dateLabel = DateFormat('d MMM yyyy').format(expiresAt.toLocal());
      final now = DateTime.now();
      if (expiresAt.isBefore(now)) {
        expiryLabel = 'Expired $dateLabel';
        expiryColor = AppColors.danger800;
        expiryIcon = Icons.warning_amber_rounded;
      } else if (expiresAt.difference(now).inDays < 30) {
        expiryLabel = 'Expires $dateLabel';
        expiryColor = AppColors.warning800;
        expiryIcon = Icons.warning_amber_rounded;
      } else {
        expiryLabel = 'Expires $dateLabel';
      }
    }

    return GlassCard(
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(Icons.description_outlined, color: primary, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: AppTextStyles.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(children: [
              GlassBadge(
                  text: formatDocumentCategory(doc['category'] as String?),
                  color: AppColors.gray500),
              const SizedBox(width: 8),
              Text(formatFileSize(doc['file_size']),
                  style: AppTextStyles.caption),
            ]),
            if (expiryLabel != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(expiryIcon, size: 12, color: expiryColor),
                const SizedBox(width: 4),
                Text(expiryLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: expiryColor)),
              ]),
            ],
            if (uploadedByOther &&
                uploaderName != null &&
                uploaderName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Added by $uploaderName', style: AppTextStyles.caption),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        opening
            ? SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: primary))
            : Icon(Icons.download_outlined, size: 18, color: primary),
      ]),
    );
  }
}
