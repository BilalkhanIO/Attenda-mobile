import 'dart:convert';
import 'dart:io';
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

class ProjectDetailScreen extends StatefulWidget {
  final String projectId;
  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _project;
  List<Map<String, dynamic>> _activity = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        api.getProjects(),
        api.getProjectActivity(widget.projectId),
      ]);
      final projects = results[0].cast<Map<String, dynamic>>();
      final matchingProjects =
          projects.where((project) => project['id'] == widget.projectId);
      if (!mounted) return;
      setState(() {
        _project = matchingProjects.isEmpty ? null : matchingProjects.first;
        _activity = results[1].cast<Map<String, dynamic>>();
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

  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _updateProject(Map<String, dynamic> data) async {
    try {
      await api.updateProject(widget.projectId, data);
      await _load();
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    }
  }

  Future<void> _addTask() async {
    final project = _project;
    if (project == null) return;
    final members = (project['members'] as List? ?? const [])
        .whereType<Map>()
        .map((member) => Map<String, dynamic>.from(member['user'] as Map))
        .toList();
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TaskFormDialog(members: members),
    );
    if (data == null) return;
    try {
      await api.createProjectTask(widget.projectId, data);
      await _load();
      if (mounted) _message('Task added to project');
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    }
  }

  Future<void> _addMember() async {
    try {
      final people = (await api.getOrgMembers()).cast<Map<String, dynamic>>();
      if (!mounted) return;
      final currentIds = ((_project?['members'] as List? ?? const [])
              .whereType<Map>()
              .map((member) => (member['user'] as Map?)?['id']?.toString()))
          .toSet();
      final available = people
          .where((person) => !currentIds.contains(person['id']?.toString()))
          .toList();
      if (available.isEmpty) {
        _message(
            'All available organization members are already on this project');
        return;
      }
      final userId = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Add a project member')),
              for (final person in available)
                ListTile(
                  leading: UserAvatar(
                      name: person['name']?.toString() ?? '?', size: 38),
                  title: Text(person['name']?.toString() ?? 'Employee'),
                  subtitle: Text(person['department']?.toString() ??
                      person['email']?.toString() ??
                      ''),
                  trailing: const Icon(Icons.person_add_alt_1_outlined),
                  onTap: () =>
                      Navigator.pop(sheetContext, person['id'].toString()),
                ),
            ],
          ),
        ),
      );
      if (userId == null) return;
      await api.addProjectMember(widget.projectId, userId);
      await _load();
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    }
  }

  Future<void> _editStatuses() async {
    final current = List<String>.from(_project?['status_options'] as List? ??
        ['todo', 'in_progress', 'blocked', 'done']);
    final statuses = await showDialog<List<String>>(
      context: context,
      builder: (_) => _TaskStatusesDialog(initial: current),
    );
    if (statuses != null && statuses.join('|') != current.join('|')) {
      await _updateProject({'status_options': statuses});
    }
  }

  Future<void> _editProject() async {
    final project = _project;
    if (project == null) return;
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ProjectEditDialog(project: project),
    );
    if (data != null) await _updateProject(data);
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

  Future<void> _attachProjectFile() async {
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
      final upload = await api.getProjectAttachmentUploadUrl(widget.projectId, {
        'file_name': file.name,
        'mime_type': mime,
        'file_size': bytes.length,
      });
      if (upload['storage'] == 'local') {
        await api.uploadProjectAttachmentLocal(
          projectId: widget.projectId,
          fileName: file.name,
          mimeType: mime,
          bytes: bytes,
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
        });
      }
      await _load();
      if (mounted) _message('File attached to project');
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    }
  }

  Future<void> _openProjectAttachment(Map<String, dynamic> file) async {
    try {
      final id = file['id'].toString();
      final info = await api.getProjectAttachmentDownload(id);
      if (info['local_download'] == true) {
        final bytes = await api.downloadLocalProjectAttachment(id);
        final directory = await getTemporaryDirectory();
        final name = (info['file_name']?.toString() ?? 'attachment')
            .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final local = File('${directory.path}/$name');
        await local.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(local.path);
      } else {
        final uri = Uri.tryParse(info['download_url']?.toString() ?? '');
        if (uri == null ||
            !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw Exception('Unable to open this file');
        }
      }
    } catch (error) {
      if (mounted) _message(ApiFailure.fromError(error).userMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    final tasks = (project?['tasks'] as List? ?? const [])
        .whereType<Map>()
        .map((task) => Map<String, dynamic>.from(task))
        .toList();
    final statuses = List<String>.from(project?['status_options'] as List? ??
        ['todo', 'in_progress', 'blocked', 'done']);
    final filtered = _statusFilter == 'all'
        ? tasks
        : tasks.where((task) => task['status'] == _statusFilter).toList();
    final done = tasks.where((task) => task['status'] == 'done').length;
    final canManageProject =
        context.watch<AuthProvider>().hasPermission('projects.manage');
    final canManageTasks =
        context.watch<AuthProvider>().hasPermission('projects.tasks.manage');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(project?['name']?.toString() ?? 'Project'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Tasks', icon: Icon(Icons.checklist_rounded, size: 18)),
            Tab(
                text: 'Overview',
                icon: Icon(Icons.info_outline_rounded, size: 18)),
          ],
        ),
        actions: [
          if (project != null &&
              context.watch<AuthProvider>().hasPermission('analytics.ai_chat'))
            IconButton(
              tooltip: 'Ask AI about this project',
              onPressed: () {
                context.push('/home/ai', extra: {
                  'prompt':
                      'Review this project. Verify its live details and tasks, then summarize progress, overdue or blocked work, key risks, and the next useful actions.',
                  'context_title': 'Project · ${project['name']}',
                  'context': jsonEncode({
                    'project': {
                      'id': project['id'],
                      'name': project['name'],
                      'status': project['status'],
                      'due_date': project['due_date'],
                    },
                    'task_count': tasks.length,
                  }),
                });
              },
              icon: const Icon(Icons.auto_awesome_outlined),
            ),
          if (canManageProject && project != null)
            PopupMenuButton<String>(
              tooltip: 'Project actions',
              onSelected: (action) {
                if (action == 'edit') _editProject();
                if (action == 'member') _addMember();
                if (action == 'statuses') _editStatuses();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit project')),
                PopupMenuItem(value: 'member', child: Text('Add member')),
                PopupMenuItem(
                    value: 'statuses', child: Text('Manage task statuses')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || project == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyStateWidget(
                      icon: Icons.error_outline,
                      title: project == null && _error == null
                          ? 'Project not found'
                          : 'Couldn’t load project',
                      description: _error ??
                          'You may no longer have access to this project.',
                      action: AppButton(
                        label: 'Try again',
                        onPressed: _load,
                        fullWidth: false,
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: _load,
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildTasks(project, filtered, tasks, statuses, done,
                          canManageTasks, canManageProject),
                      _buildOverview(project, tasks, done, canManageProject),
                    ],
                  ),
                ),
      floatingActionButton: project != null && canManageTasks
          ? FloatingActionButton.extended(
              onPressed: _addTask,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Add task'),
            )
          : null,
    );
  }

  Widget _buildTasks(
      Map<String, dynamic> project,
      List<Map<String, dynamic>> tasks,
      List<Map<String, dynamic>> allTasks,
      List<String> statuses,
      int done,
      bool canManageTasks,
      bool canManageProject) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
      children: [
        _ProjectProgressCard(
            project: project,
            done: done,
            total: allTasks.length,
            onStatusChanged: canManageProject
                ? (value) => _updateProject({'status': value})
                : null),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _StatusFilterChip(
              label: 'All',
              selected: _statusFilter == 'all',
              onTap: () => setState(() => _statusFilter = 'all'),
            ),
            for (final status in statuses)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _StatusFilterChip(
                  label: projectLabel(status),
                  selected: _statusFilter == status,
                  color: projectStatusColor(status),
                  onTap: () => setState(() => _statusFilter = status),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SectionHeader(
          title: 'Tasks',
          trailing: Text('${tasks.length}', style: AppTextStyles.caption),
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          EmptyStateWidget(
            icon: Icons.task_alt_outlined,
            title:
                allTasks.isEmpty ? 'No tasks yet' : 'No tasks in this status',
            description: allTasks.isEmpty
                ? 'Break this project into clear, assignable steps.'
                : 'Choose another status filter to see more tasks.',
            action: allTasks.isEmpty && canManageTasks
                ? AppButton(
                    label: 'Add task', onPressed: _addTask, fullWidth: false)
                : null,
          )
        else
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _TaskCard(
                task: task,
                onTap: () => context
                    .push('/projects/${widget.projectId}/tasks/${task['id']}'),
              ),
            ),
      ],
    );
  }

  Widget _buildOverview(Map<String, dynamic> project,
      List<Map<String, dynamic>> tasks, int done, bool canManageProject) {
    final owner = project['owner'] as Map?;
    final members = (project['members'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final attachments = (project['attachments'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      children: [
        _ProjectProgressCard(
            project: project,
            done: done,
            total: tasks.length,
            onStatusChanged: canManageProject
                ? (value) => _updateProject({'status': value})
                : null),
        const SizedBox(height: 12),
        GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'Project details'),
            const SizedBox(height: 12),
            Text(
                (project['description'] as String?)?.trim().isNotEmpty == true
                    ? project['description'] as String
                    : 'No description has been added.',
                style: AppTextStyles.body),
            const SizedBox(height: 14),
            GlassDetailRow(
                label: 'Owner', value: owner?['name']?.toString() ?? '—'),
            GlassDetailRow(
                label: 'Priority',
                value:
                    projectLabel(project['priority']?.toString() ?? 'medium')),
            GlassDetailRow(
                label: 'Start date', value: projectDate(project['start_date'])),
            GlassDetailRow(
                label: 'Due date', value: projectDate(project['due_date'])),
          ]),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(
              title: 'Members (${members.length})',
              trailing: canManageProject
                  ? IconButton(
                      tooltip: 'Add member',
                      visualDensity: VisualDensity.compact,
                      onPressed: _addMember,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            for (final member in members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                    name: (member['user'] as Map?)?['name']?.toString() ?? '?',
                    size: 38),
                title: Text(
                    (member['user'] as Map?)?['name']?.toString() ?? 'Member'),
                subtitle:
                    Text(projectLabel(member['role']?.toString() ?? 'member')),
                dense: true,
              ),
          ]),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(
              title: 'Project files (${attachments.length})',
              trailing: canManageProject
                  ? IconButton(
                      tooltip: 'Attach project file',
                      onPressed: _attachProjectFile,
                      icon: const Icon(Icons.attach_file_rounded),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            if (attachments.isEmpty)
              const Text('Files attached to tasks appear in each task.',
                  style: AppTextStyles.caption)
            else
              for (final file in attachments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file_rounded),
                  title: Text(file['file_name']?.toString() ?? 'Attachment',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(projectDate(file['created_at'])),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _openProjectAttachment(file),
                ),
          ]),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'Recent activity'),
            const SizedBox(height: 8),
            if (_activity.isEmpty)
              const Text('Project changes will appear here.',
                  style: AppTextStyles.caption)
            else
              for (final item in _activity.take(10))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded, size: 20),
                  title: Text(_activityLabel(item),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${item['actor_name'] ?? 'Team member'} · ${projectDate(item['created_at'])}'),
                  dense: true,
                ),
          ]),
        ),
      ],
    );
  }

  String _activityLabel(Map<String, dynamic> item) {
    final after = item['after'] is Map ? item['after'] as Map : const {};
    final title = after['title']?.toString() ?? after['name']?.toString();
    return '${projectLabel(item['action']?.toString() ?? 'project update')}${title == null ? '' : ' · $title'}';
  }
}

class _ProjectProgressCard extends StatelessWidget {
  final Map<String, dynamic> project;
  final int done;
  final int total;
  final ValueChanged<String>? onStatusChanged;
  const _ProjectProgressCard(
      {required this.project,
      required this.done,
      required this.total,
      this.onStatusChanged});

  @override
  Widget build(BuildContext context) {
    final status = project['status']?.toString() ?? 'planning';
    final progress = total == 0 ? 0.0 : done / total;
    const projectStatuses = [
      'planning',
      'active',
      'on_hold',
      'completed',
      'cancelled'
    ];
    return GlassCard(
      tint: projectStatusColor(status),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(project['name']?.toString() ?? 'Project',
                  style: AppTextStyles.headline)),
          if (onStatusChanged != null)
            DropdownButton<String>(
              value: projectStatuses.contains(status) ? status : 'planning',
              underline: const SizedBox.shrink(),
              items: projectStatuses
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(projectLabel(value),
                            style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) onStatusChanged!(value);
              },
            )
          else
            projectBadge(status, projectStatusColor(status)),
        ]),
        const SizedBox(height: 14),
        LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            color: AppColors.primary,
            backgroundColor: AppColors.gray100),
        const SizedBox(height: 7),
        Text(
            '$done of $total tasks complete · ${projectDate(project['due_date'])} due',
            style: AppTextStyles.caption),
      ]),
    );
  }
}

class _ProjectEditDialog extends StatefulWidget {
  final Map<String, dynamic> project;
  const _ProjectEditDialog({required this.project});
  @override
  State<_ProjectEditDialog> createState() => _ProjectEditDialogState();
}

class _ProjectEditDialogState extends State<_ProjectEditDialog> {
  late final _name =
      TextEditingController(text: widget.project['name']?.toString() ?? '');
  late final _description = TextEditingController(
      text: widget.project['description']?.toString() ?? '');
  late String _priority = widget.project['priority']?.toString() ?? 'medium';
  DateTime? _start;
  DateTime? _due;
  @override
  void initState() {
    super.initState();
    _start = DateTime.tryParse(widget.project['start_date']?.toString() ?? '');
    _due = DateTime.tryParse(widget.project['due_date']?.toString() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit project'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Project name')),
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
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, {
                        'name': _name.text.trim(),
                        'description': _description.text.trim(),
                        'priority': _priority,
                        'start_date': apiDate(_start),
                        'due_date': apiDate(_due),
                      }),
              child: const Text('Save')),
        ],
      );
}

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _StatusFilterChip(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.color});
  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: (color ?? Theme.of(context).colorScheme.primary)
            .withValues(alpha: .15),
        side: BorderSide(
            color: selected
                ? (color ?? Theme.of(context).colorScheme.primary)
                : AppColors.border),
      );
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onTap;
  const _TaskCard({required this.task, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final status = task['status']?.toString() ?? 'todo';
    final assignee = task['assignee'] as Map?;
    final due = projectDate(task['due_date']);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: projectPriorityColor(
                        task['priority']?.toString() ?? 'medium')
                    .withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(
                task['is_milestone'] == true
                    ? Icons.flag_outlined
                    : Icons.task_alt_outlined,
                size: 20,
                color: projectPriorityColor(
                    task['priority']?.toString() ?? 'medium'))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task['title']?.toString() ?? 'Untitled task',
              style: AppTextStyles.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 7),
          Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                projectBadge(status, projectStatusColor(status)),
                Text(projectLabel(task['priority']?.toString() ?? 'medium'),
                    style: AppTextStyles.caption),
                Text(assignee?['name']?.toString() ?? 'Unassigned',
                    style: AppTextStyles.caption),
                Text(due, style: AppTextStyles.caption),
              ]),
        ])),
        const SizedBox(width: 6),
        const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
      ]),
    );
  }
}

class _TaskFormDialog extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  const _TaskFormDialog({required this.members});
  @override
  State<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<_TaskFormDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _priority = 'medium';
  String? _assigneeId;
  DateTime? _start;
  DateTime? _due;
  bool _milestone = false;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add task'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _title,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Task title *')),
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
            onChanged: (value) => setState(() => _priority = value ?? 'medium'),
          ),
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
            onChanged: (value) => setState(() => _assigneeId = value),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _milestone,
              title: const Text('Mark as milestone'),
              onChanged: (value) =>
                  setState(() => _milestone = value ?? false)),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await pickProjectDate(context, _start);
                      if (d != null) setState(() => _start = d);
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label:
                        Text(_start == null ? 'Start' : projectDate(_start)))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await pickProjectDate(context, _due);
                      if (d != null) setState(() => _due = d);
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label:
                        Text(_due == null ? 'Due date' : projectDate(_due)))),
          ]),
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
                        'is_milestone': _milestone,
                        if (_start != null) 'start_date': apiDate(_start),
                        if (_due != null) 'due_date': apiDate(_due),
                      }),
              child: const Text('Add task')),
        ],
      );
}

class _TaskStatusesDialog extends StatefulWidget {
  final List<String> initial;
  const _TaskStatusesDialog({required this.initial});
  @override
  State<_TaskStatusesDialog> createState() => _TaskStatusesDialogState();
}

class _TaskStatusesDialogState extends State<_TaskStatusesDialog> {
  late final List<String> _statuses = [...widget.initial];
  final _newStatus = TextEditingController();
  @override
  void dispose() {
    _newStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Task statuses'),
        content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Statuses already used by tasks can’t be removed.',
                  style: AppTextStyles.caption),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final status in _statuses)
                  InputChip(
                      label: Text(projectLabel(status)),
                      onDeleted: _statuses.length > 2 && status != 'todo'
                          ? () => setState(() => _statuses.remove(status))
                          : null)
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _newStatus,
                        decoration: const InputDecoration(
                            labelText: 'Add status',
                            hintText: 'e.g. waiting_review'))),
                IconButton(
                    tooltip: 'Add status',
                    onPressed: () {
                      final value = _newStatus.text
                          .trim()
                          .toLowerCase()
                          .replaceAll(RegExp(r'\s+'), '_');
                      if (RegExp(r'^[a-z][a-z0-9_]{1,29}$').hasMatch(value) &&
                          !_statuses.contains(value) &&
                          _statuses.length < 12) {
                        setState(() {
                          _statuses.add(value);
                          _newStatus.clear();
                        });
                      }
                    },
                    icon: const Icon(Icons.add_circle_outline))
              ]),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _statuses),
              child: const Text('Save'))
        ],
      );
}
