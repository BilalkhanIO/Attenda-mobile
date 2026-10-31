import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import 'project_helpers.dart';

class ProjectsScreen extends StatefulWidget {
  final String? taskId;
  const ProjectsScreen({super.key, this.taskId});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;
  String? _error;
  bool _deepLinkHandled = false;

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
      final projects = await api.getProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects.cast<Map<String, dynamic>>();
        _loading = false;
      });
      if (widget.taskId != null && !_deepLinkHandled) {
        _deepLinkHandled = true;
        for (final project in _projects) {
          final tasks =
              (project['tasks'] as List? ?? const []).whereType<Map>();
          if (tasks.any((task) => task['id']?.toString() == widget.taskId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                context.go('/projects/${project['id']}/tasks/${widget.taskId}');
              }
            });
            break;
          }
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = ApiFailure.fromError(error).userMessage;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ProjectFormDialog(),
    );
    if (data == null || !mounted) return;
    try {
      final project = await api.createProject(data);
      await _load();
      if (mounted) context.push('/projects/${project['id']}');
    } catch (error) {
      if (mounted) _showError(ApiFailure.fromError(error).userMessage);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final canCreate =
        context.watch<AuthProvider>().hasPermission('projects.manage');
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const AppPageTitle(
          title: 'Projects',
          subtitle: 'Shared plans, tasks, and deadlines',
        ),
        actions: [
          if (canCreate)
            IconButton(
              tooltip: 'Create project',
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 260),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      EmptyStateWidget(
                        icon: Icons.error_outline,
                        title: 'Couldn’t load projects',
                        description: _error!,
                        action: AppButton(
                          label: 'Try again',
                          onPressed: _load,
                          fullWidth: false,
                        ),
                      ),
                    ],
                  )
                : _projects.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 80),
                          EmptyStateWidget(
                            icon: Icons.work_outline_rounded,
                            title: 'No projects yet',
                            description: canCreate
                                ? 'Create a project to organize shared work and deadlines.'
                                : 'Projects you own, join, or have tasks in will show here.',
                            action: canCreate
                                ? AppButton(
                                    label: 'Create project',
                                    icon: Icons.add_rounded,
                                    onPressed: _create,
                                    fullWidth: false,
                                  )
                                : null,
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                        itemCount: _projects.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => _ProjectCard(
                          project: _projects[index],
                          onTap: () => context
                              .push('/projects/${_projects[index]['id']}'),
                        ),
                      ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Map<String, dynamic> project;
  final VoidCallback onTap;
  const _ProjectCard({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tasks =
        (project['tasks'] as List? ?? const []).whereType<Map>().toList();
    final done = tasks.where((task) => task['status'] == 'done').length;
    final progress = tasks.isEmpty ? 0.0 : done / tasks.length;
    final members = (project['members'] as List? ?? const []).length;
    final due = projectDate(project['due_date']);
    final color =
        projectStatusColor(project['status']?.toString() ?? 'planning');

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              project['name']?.toString() ?? 'Untitled project',
              style: AppTextStyles.title.copyWith(fontSize: 16),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          projectBadge(project['status']?.toString() ?? 'planning', color),
        ]),
        if ((project['description'] as String?)?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(project['description'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body),
        ],
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: AppColors.gray100,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('$done/${tasks.length} tasks complete',
              style: AppTextStyles.caption),
          const Spacer(),
          const Icon(Icons.groups_2_outlined,
              size: 15, color: AppColors.gray500),
          const SizedBox(width: 4),
          Text('$members', style: AppTextStyles.caption),
          const SizedBox(width: 12),
          const Icon(Icons.event_outlined, size: 15, color: AppColors.gray500),
          const SizedBox(width: 4),
          Text(due, style: AppTextStyles.caption),
        ]),
      ]),
    );
  }
}

class _ProjectFormDialog extends StatefulWidget {
  const _ProjectFormDialog();
  @override
  State<_ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends State<_ProjectFormDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _priority = 'medium';
  DateTime? _start;
  DateTime? _due;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create project'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Project name *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const ['low', 'medium', 'high', 'urgent']
                  .map((value) => DropdownMenuItem(
                      value: value, child: Text(projectLabel(value))))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _priority = value ?? 'medium'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final date = await pickProjectDate(context, _start);
                    if (date != null) setState(() => _start = date);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label:
                      Text(_start == null ? 'Start date' : projectDate(_start)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final date = await pickProjectDate(context, _due);
                    if (date != null) setState(() => _due = date);
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(_due == null ? 'Due date' : projectDate(_due)),
                ),
              ),
            ]),
          ]),
        ),
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
                      if (_start != null) 'start_date': apiDate(_start),
                      if (_due != null) 'due_date': apiDate(_due),
                    }),
            child: const Text('Create'),
          ),
        ],
      );
}
