import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import 'project_helpers.dart';

class ProjectTaskScreen extends StatefulWidget {
  final String projectId;
  final String taskId;
  const ProjectTaskScreen(
      {super.key, required this.projectId, required this.taskId});
  @override
  State<ProjectTaskScreen> createState() => _ProjectTaskScreenState();
}

class _ProjectTaskScreenState extends State<ProjectTaskScreen> {
  Map<String, dynamic>? _project;
  Map<String, dynamic>? _task;
  final _comment = TextEditingController();
  final Set<String> _mentionedMemberIds = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = (await api.getProjects()).cast<Map<String, dynamic>>();
      final project = projects.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id'] == widget.projectId,
          orElse: () => null);
      final tasks = (project?['tasks'] as List? ?? const []).whereType<Map>();
      final task = tasks.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id'] == widget.taskId,
          orElse: () => null);
      if (!mounted) return;
      setState(() {
        _project = project;
        _task = task;
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

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _update(Map<String, dynamic> changes) async {
    setState(() => _busy = true);
    try {
      await api.updateProjectTask(widget.taskId, changes);
      await _load();
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await api.addProjectTaskComment(widget.taskId, body,
          mentionIds: _mentionedMemberIds.toList());
      _comment.clear();
      _mentionedMemberIds.clear();
      await _load();
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mentionMember() async {
    final members = (_project?['members'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
      final user = item['user'] as Map?;
      final id = user?['id']?.toString();
      return id != null &&
          id != context.read<AuthProvider>().user?.id &&
          !_mentionedMemberIds.contains(id);
    }).toList();
    if (members.isEmpty) {
      _message('There are no other project members to mention.');
      return;
    }
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Mention a project member')),
            for (final member in members)
              ListTile(
                leading: UserAvatar(
                    name: (member['user'] as Map?)?['name']?.toString() ?? '?',
                    size: 36),
                title: Text(
                    (member['user'] as Map?)?['name']?.toString() ?? 'Member'),
                subtitle: Text(
                    (member['user'] as Map?)?['department']?.toString() ??
                        member['role']?.toString() ??
                        'Project member'),
                onTap: () => Navigator.pop(context, member),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final user = selected['user'] as Map?;
    final id = user?['id']?.toString();
    final name = user?['name']?.toString();
    if (id == null || name == null) return;
    setState(() {
      _mentionedMemberIds.add(id);
      final current = _comment.text.trimRight();
      _comment.text = '${current.isEmpty ? '' : '$current '}@$name ';
      _comment.selection =
          TextSelection.collapsed(offset: _comment.text.length);
    });
  }

  Future<void> _addSubtask() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Add subtask'),
          content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Subtask title')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Add')),
          ],
        );
      },
    );
    if (title == null || title.isEmpty) return;
    setState(() => _busy = true);
    try {
      await api.createProjectTask(widget.projectId, {
        'title': title,
        'parent_task_id': widget.taskId,
        'priority': 'medium',
      });
      await _load();
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUpload() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Attach a project file',
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'png',
          'jpg',
          'jpeg',
          'webp',
          'gif',
          'txt',
          'doc',
          'docx',
          'zip'
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mime = _mimeType(file.extension);
      setState(() => _busy = true);
      final upload = await api.getProjectAttachmentUploadUrl(widget.projectId, {
        'file_name': file.name,
        'mime_type': mime,
        'file_size': bytes.length,
        'task_id': widget.taskId,
      });
      if (upload['storage'] == 'local') {
        await api.uploadProjectAttachmentLocal(
          projectId: widget.projectId,
          fileName: file.name,
          mimeType: mime,
          bytes: bytes,
          taskId: widget.taskId,
        );
      } else {
        await api.uploadProjectAttachmentSigned(
          uploadUrl: upload['upload_url'] as String,
          mimeType: mime,
          bytes: bytes,
        );
        await api.registerProjectAttachment(widget.projectId, {
          'file_key': upload['file_key'],
          'file_name': file.name,
          'mime_type': mime,
          'file_size': bytes.length,
          'task_id': widget.taskId,
        });
      }
      await _load();
      if (mounted) _message('File attached');
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mimeType(String? extension) => switch (extension?.toLowerCase()) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'txt' => 'text/plain',
        'doc' => 'application/msword',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'zip' => 'application/zip',
        _ => 'application/octet-stream',
      };

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    try {
      final info =
          await api.getProjectAttachmentDownload(attachment['id'].toString());
      if (info['local_download'] == true) {
        final bytes = await api
            .downloadLocalProjectAttachment(attachment['id'].toString());
        final directory = await getTemporaryDirectory();
        final safeName = (info['file_name']?.toString() ?? 'attachment')
            .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final file = File('${directory.path}/$safeName');
        await file.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(file.path);
      } else {
        final url = Uri.tryParse(info['download_url']?.toString() ?? '');
        if (url == null ||
            !await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw Exception('Unable to open this file');
        }
      }
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    }
  }

  Future<void> _editDetails() async {
    final task = _task;
    if (task == null) return;
    final members = (_project?['members'] as List? ?? const [])
        .whereType<Map>()
        .map((member) => Map<String, dynamic>.from(member['user'] as Map))
        .toList();
    final projectTasks = (_project?['tasks'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['id'] != widget.taskId)
        .toList();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditTaskDialog(
          task: task, members: members, projectTasks: projectTasks),
    );
    if (result != null) await _update(result);
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final project = _project;
    final user = context.watch<AuthProvider>().user;
    final canManage =
        context.watch<AuthProvider>().hasPermission('projects.tasks.manage');
    final assignedToMe = task?['assignee_id']?.toString() == user?.id;
    final isMember =
        ((project?['members'] as List? ?? const []).whereType<Map>()).any(
            (member) =>
                (member['user'] as Map?)?['id']?.toString() == user?.id);
    final canUpdate = canManage || assignedToMe;
    final canComment = canManage || assignedToMe || isMember;
    final statuses = List<String>.from(project?['status_options'] as List? ??
        ['todo', 'in_progress', 'blocked', 'done']);
    final attachments = (task?['attachments'] as List? ?? const [])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList();
    final subtasks = (task?['subtasks'] as List? ?? const [])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList();
    final comments = (task?['comments'] as List? ?? const [])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList();
    final dependencies =
        (task?['dependencies'] as List? ?? const []).whereType<Map>().toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(project?['name']?.toString() ?? 'Task'),
        actions: [
          if (context
                  .watch<AuthProvider>()
                  .hasPermission('analytics.ai_chat') &&
              task != null)
            IconButton(
              tooltip: 'Ask AI about this task',
              onPressed: () {
                final prompt =
                    'Review this task. Check its current project/task details, identify blockers, and suggest the next useful action.';
                context.push('/home/ai', extra: {
                  'prompt': prompt,
                  'context_title':
                      'Task · ${task['title']} · ${project?['name']}',
                  'context': jsonEncode({
                    'project': {
                      'id': widget.projectId,
                      'name': project?['name'],
                    },
                    'task': {
                      'id': task['id'],
                      'title': task['title'],
                    },
                  }),
                });
              },
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
          if (canManage && task != null)
            IconButton(
                tooltip: 'Edit task details',
                onPressed: _editDetails,
                icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : task == null || project == null
              ? Center(
                  child: EmptyStateWidget(
                  icon: Icons.task_outlined,
                  title: 'Task not found',
                  description: _error ??
                      'This task may have been removed or you may not have access.',
                  action: AppButton(
                      label: 'Back to project',
                      fullWidth: false,
                      onPressed: () =>
                          context.go('/projects/${widget.projectId}')),
                ))
              : RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      GlassCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              projectBadge(
                                  task['priority']?.toString() ?? 'medium',
                                  projectPriorityColor(
                                      task['priority']?.toString() ??
                                          'medium')),
                              if (task['is_milestone'] == true)
                                const GlassBadge(
                                    text: 'Milestone',
                                    color: AppColors.info500,
                                    icon: Icons.flag_outlined),
                            ]),
                            const SizedBox(height: 10),
                            Text(task['title']?.toString() ?? 'Untitled task',
                                style: AppTextStyles.headline),
                            const SizedBox(height: 6),
                            Text(
                                (task['description'] as String?)
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? task['description'] as String
                                    : 'No description yet.',
                                style: AppTextStyles.body),
                            const SizedBox(height: 12),
                            Row(children: [
                              const Icon(Icons.person_outline_rounded,
                                  size: 17, color: AppColors.gray500),
                              const SizedBox(width: 5),
                              Expanded(
                                  child: Text(
                                      (task['assignee'] as Map?)?['name']
                                              ?.toString() ??
                                          'Unassigned',
                                      style: AppTextStyles.caption)),
                              const Icon(Icons.event_outlined,
                                  size: 16, color: AppColors.gray500),
                              const SizedBox(width: 4),
                              Text(projectDate(task['due_date']),
                                  style: AppTextStyles.caption),
                            ]),
                            const SizedBox(height: 10),
                            if (canUpdate)
                              DropdownButtonFormField<String>(
                                initialValue: statuses.contains(task['status'])
                                    ? task['status'] as String
                                    : statuses.first,
                                decoration: const InputDecoration(
                                    labelText: 'Task status', isDense: true),
                                items: statuses
                                    .map((value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(projectLabel(value))))
                                    .toList(),
                                onChanged: _busy
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          _update({'status': value});
                                        }
                                      },
                              )
                            else
                              projectBadge(
                                  task['status']?.toString() ?? 'todo',
                                  projectStatusColor(
                                      task['status']?.toString() ?? 'todo')),
                          ])),
                      const SizedBox(height: 12),
                      _section(
                        title: 'Subtasks (${subtasks.length})',
                        trailing: canManage
                            ? IconButton(
                                tooltip: 'Add subtask',
                                onPressed: _busy ? null : _addSubtask,
                                icon: const Icon(Icons.add))
                            : null,
                        child: subtasks.isEmpty
                            ? const Text('No subtasks yet.',
                                style: AppTextStyles.caption)
                            : Column(children: [
                                for (final subtask in subtasks)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                        subtask['status'] == 'done'
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: subtask['status'] == 'done'
                                            ? AppColors.success500
                                            : AppColors.gray400),
                                    title: Text(
                                        subtask['title']?.toString() ??
                                            'Subtask',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                        '${projectLabel(subtask['status']?.toString() ?? 'todo')} · ${(subtask['assignee'] as Map?)?['name'] ?? 'Unassigned'}'),
                                    onTap: () => context.push(
                                        '/projects/${widget.projectId}/tasks/${subtask['id']}'),
                                  )
                              ]),
                      ),
                      const SizedBox(height: 12),
                      _section(
                        title: 'Discussion (${comments.length})',
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (comments.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.only(bottom: 10),
                                    child: Text(
                                        'No updates yet. Keep decisions and progress with this task.',
                                        style: AppTextStyles.caption)),
                              for (final comment in comments)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        UserAvatar(
                                            name: (comment['user']
                                                        as Map?)?['name']
                                                    ?.toString() ??
                                                '?',
                                            size: 32),
                                        const SizedBox(width: 9),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Row(children: [
                                                Expanded(
                                                    child: Text(
                                                        (comment['user']
                                                                        as Map?)?[
                                                                    'name']
                                                                ?.toString() ??
                                                            'Team member',
                                                        style: AppTextStyles
                                                            .bodyStrong)),
                                                Text(
                                                    projectDate(
                                                        comment['created_at']),
                                                    style:
                                                        AppTextStyles.caption)
                                              ]),
                                              const SizedBox(height: 3),
                                              SelectableText(
                                                  comment['body']?.toString() ??
                                                      '',
                                                  style: AppTextStyles.body),
                                            ])),
                                      ]),
                                ),
                              if (canComment) ...[
                                const Divider(height: 20),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _busy ? null : _mentionMember,
                                    icon: const Icon(
                                        Icons.alternate_email_rounded,
                                        size: 18),
                                    label: const Text('Mention a teammate'),
                                  ),
                                ),
                                if (_mentionedMemberIds.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'Mentioned: ${((_project?['members'] as List? ?? const []).whereType<Map>()).where((item) => _mentionedMemberIds.contains((item['user'] as Map?)?['id']?.toString())).map((item) => (item['user'] as Map?)?['name']?.toString() ?? '').where((name) => name.isNotEmpty).join(', ')}',
                                      style: AppTextStyles.caption,
                                    ),
                                  ),
                                TextField(
                                  controller: _comment,
                                  minLines: 2,
                                  maxLines: 5,
                                  enabled: !_busy,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                      hintText: 'Add an update or decision…',
                                      alignLabelWithHint: true),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                        onPressed: _busy ||
                                                _comment.text.trim().isEmpty
                                            ? null
                                            : _sendComment,
                                        icon: const Icon(Icons.send_rounded,
                                            size: 17),
                                        label: const Text('Comment'))),
                              ],
                            ]),
                      ),
                      const SizedBox(height: 12),
                      _section(
                        title: 'Files (${attachments.length})',
                        trailing: canComment
                            ? IconButton(
                                tooltip: 'Attach file or image',
                                onPressed: _busy ? null : _pickAndUpload,
                                icon: const Icon(Icons.attach_file_rounded))
                            : null,
                        child: attachments.isEmpty
                            ? const Text(
                                'No files attached. Add a document or image to keep project materials with the task.',
                                style: AppTextStyles.caption)
                            : Column(children: [
                                for (final file in attachments)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                        (file['mime_type']?.toString() ?? '')
                                                .startsWith('image/')
                                            ? Icons.image_outlined
                                            : Icons.description_outlined,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    title: Text(
                                        file['file_name']?.toString() ?? 'File',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                        '${_formatSize(file['file_size'])} · ${(file['uploader'] as Map?)?['name'] ?? 'Team member'}'),
                                    trailing: const Icon(
                                        Icons.open_in_new_rounded,
                                        size: 18),
                                    onTap: () => _openAttachment(file),
                                  )
                              ]),
                      ),
                      const SizedBox(height: 12),
                      _section(
                        title: 'Dependencies (${dependencies.length})',
                        child: dependencies.isEmpty
                            ? const Text('No blocked-by tasks.',
                                style: AppTextStyles.caption)
                            : Column(children: [
                                for (final dependency in dependencies)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.link_rounded),
                                    title: Text((dependency['depends_on']
                                                as Map?)?['title']
                                            ?.toString() ??
                                        'Task'),
                                    subtitle: Text(projectLabel(
                                        (dependency['depends_on']
                                                    as Map?)?['status']
                                                ?.toString() ??
                                            'todo')),
                                    onTap: () => context.push(
                                        '/projects/${widget.projectId}/tasks/${(dependency['depends_on'] as Map?)?['id']}'),
                                  )
                              ]),
                      ),
                      const SizedBox(height: 12),
                      _section(
                          title: 'Details',
                          child: Column(children: [
                            GlassDetailRow(
                                label: 'Project',
                                value: project['name']?.toString() ?? '—'),
                            GlassDetailRow(
                                label: 'Start date',
                                value: projectDate(task['start_date'])),
                            GlassDetailRow(
                                label: 'Due date',
                                value: projectDate(task['due_date'])),
                            GlassDetailRow(
                                label: 'Created',
                                value: projectDate(task['created_at'])),
                          ])),
                    ],
                  ),
                ),
      floatingActionButton: _busy
          ? const FloatingActionButton(
              onPressed: null,
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : null,
    );
  }

  Widget _section(
          {required String title, required Widget child, Widget? trailing}) =>
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: AppTextStyles.title)),
            if (trailing != null) trailing
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );

  String _formatSize(dynamic value) {
    final bytes = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _EditTaskDialog extends StatefulWidget {
  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> projectTasks;
  const _EditTaskDialog(
      {required this.task, required this.members, required this.projectTasks});
  @override
  State<_EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<_EditTaskDialog> {
  late final _title =
      TextEditingController(text: widget.task['title']?.toString() ?? '');
  late final _description =
      TextEditingController(text: widget.task['description']?.toString() ?? '');
  late String _priority = widget.task['priority']?.toString() ?? 'medium';
  String? _assigneeId;
  DateTime? _start;
  DateTime? _due;
  late final Set<String> _dependencyIds;

  @override
  void initState() {
    super.initState();
    _assigneeId = widget.task['assignee_id']?.toString();
    _start = DateTime.tryParse(widget.task['start_date']?.toString() ?? '');
    _due = DateTime.tryParse(widget.task['due_date']?.toString() ?? '');
    _dependencyIds = ((widget.task['dependencies'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => (item['depends_on'] as Map?)?['id']?.toString())
            .whereType<String>())
        .toSet();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit task'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _title,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 8),
          TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const ['low', 'medium', 'high', 'urgent']
                  .map((value) => DropdownMenuItem(
                      value: value, child: Text(projectLabel(value))))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _priority = value ?? 'medium')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
              initialValue: _assigneeId,
              decoration: const InputDecoration(labelText: 'Assignee'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('Unassigned')),
                ...widget.members.map((person) => DropdownMenuItem<String?>(
                    value: person['id']?.toString(),
                    child: Text(person['name']?.toString() ?? 'Member')))
              ],
              onChanged: (value) => setState(() => _assigneeId = value)),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: () async {
                      final d = await pickProjectDate(context, _start);
                      if (d != null) setState(() => _start = d);
                    },
                    child: Text(
                        _start == null ? 'Start date' : projectDate(_start)))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton(
                    onPressed: () async {
                      final d = await pickProjectDate(context, _due);
                      if (d != null) setState(() => _due = d);
                    },
                    child:
                        Text(_due == null ? 'Due date' : projectDate(_due)))),
          ]),
          if (widget.projectTasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
                alignment: Alignment.centerLeft,
                child: Text('Blocked by', style: AppTextStyles.captionStrong)),
            const SizedBox(height: 5),
            for (final item in widget.projectTasks)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _dependencyIds.contains(item['id']?.toString()),
                title: Text(item['title']?.toString() ?? 'Task',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle:
                    Text(projectLabel(item['status']?.toString() ?? 'todo')),
                onChanged: (selected) => setState(() {
                  final id = item['id']?.toString();
                  if (id == null) return;
                  if (selected == true) {
                    _dependencyIds.add(id);
                  } else {
                    _dependencyIds.remove(id);
                  }
                }),
              ),
          ],
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _title.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, {
                        'title': _title.text.trim(),
                        'description': _description.text.trim(),
                        'priority': _priority,
                        'assignee_id': _assigneeId,
                        'start_date': apiDate(_start),
                        'due_date': apiDate(_due),
                        'depends_on_ids': _dependencyIds.toList(),
                      }),
              child: const Text('Save'))
        ],
      );
}
