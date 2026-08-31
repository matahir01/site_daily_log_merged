import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/google_drive_service.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/project.dart';
import 'project_dashboard_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  final _db = DatabaseHelper.instance;
  List<Project> _projects = [];
  final _nameController = TextEditingController();
  final _clientController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _db.getProjects();
    setState(() => _projects = data);
  }

  Future<void> _addProject() async {
    if (_nameController.text.trim().isEmpty) return;
    final project = Project(
      id: const Uuid().v4(),
      name: _nameController.text.trim(),
      client: _clientController.text.trim().isEmpty ? null : _clientController.text.trim(),
      createdAt: DateTime.now(),
    );
    await _db.insertProject(project);
    _nameController.clear();
    _clientController.clear();
    _load();
  }

  Future<void> _deleteProject(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: const Text('All sites, logs, and expenses under this project will be deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteProject(id);
      _load();
    }
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Project Name'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _clientController,
              decoration: const InputDecoration(labelText: 'Client (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addProject();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GoogleDriveBackupScreen()),
            ),
          ),
        ],
      ),
      body: _projects.isEmpty
          ? const Center(child: Text('No projects yet. Tap + to create one.'))
          : ListView.builder(
              itemCount: _projects.length,
              itemBuilder: (ctx, i) {
                final p = _projects[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: p.client != null ? Text(p.client!) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteProject(p.id),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProjectDashboardScreen(project: p),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class GoogleDriveBackupScreen extends StatefulWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  State<GoogleDriveBackupScreen> createState() => _GoogleDriveBackupScreenState();
}

class _GoogleDriveBackupScreenState extends State<GoogleDriveBackupScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _backup() async {
    setState(() { _busy = true; _status = 'Signing in...'; });
    try {
      final file = await GoogleDriveService.uploadBackup();
      setState(() => _status = 'Backup uploaded: ${file.name}');
    } catch (e) {
      setState(() => _status = 'Backup failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() { _busy = true; _status = 'Fetching backups...'; });
    try {
      final backups = await GoogleDriveService.listBackups();
      if (backups.isEmpty) {
        setState(() => _status = 'No backups found on Google Drive.');
        return;
      }
      final chosen = await showDialog<drive.File>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Choose Backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: backups.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(backups[i].name ?? 'Unnamed'),
                subtitle: Text(backups[i].createdTime?.toLocal().toString() ?? ''),
                onTap: () => Navigator.pop(ctx, backups[i]),
              ),
            ),
          ),
        ),
      );
      if (chosen != null) {
        setState(() => _status = 'Restoring...');
        await GoogleDriveService.restoreFromBackup(chosen);
        setState(() => _status = 'Restored successfully. Restart app to see changes.');
      }
    } catch (e) {
      setState(() => _status = 'Restore failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive Backup')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Back up your entire database to Google Drive, or restore a previous backup.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _backup,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.backup),
              label: const Text('Back Up Now'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore),
              label: const Text('Restore from Backup'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 24),
              Text(_status!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
