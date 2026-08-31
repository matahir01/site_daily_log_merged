import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';
import '../services/pdf_report_service.dart';
import '../services/excel_export_service.dart';
import 'site_detail_screen.dart';

class ProjectDashboardScreen extends StatefulWidget {
  final Project project;
  const ProjectDashboardScreen({super.key, required this.project});

  @override
  State<ProjectDashboardScreen> createState() => _ProjectDashboardScreenState();
}

class _ProjectDashboardScreenState extends State<ProjectDashboardScreen> {
  final _db = DatabaseHelper.instance;
  List<Site> _sites = [];
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  bool _generatingPdf = false;
  bool _generatingExcel = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _db.getSitesForProject(widget.project.id);
    setState(() => _sites = data);
  }

  Future<void> _exportProjectPdf() async {
    if (_sites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one site before exporting a project report')),
      );
      return;
    }
    setState(() => _generatingPdf = true);
    try {
      final logsBySite = <String, List<DailyLog>>{};
      final expensesBySite = <String, List<Expense>>{};
      for (final site in _sites) {
        logsBySite[site.id] = await _db.getLogsForSite(site.id);
        expensesBySite[site.id] = await _db.getExpensesForSite(site.id);
      }
      final file = await PdfReportService.generateProjectReport(
        project: widget.project,
        sites: _sites,
        logsBySite: logsBySite,
        expensesBySite: expensesBySite,
      );
      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: '${widget.project.name} project report'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _exportProjectExcel() async {
    if (_sites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one site before exporting a project workbook')),
      );
      return;
    }
    setState(() => _generatingExcel = true);
    try {
      final logsBySite = <String, List<DailyLog>>{};
      final materialsBySite = <String, List<MaterialItem>>{};
      final expensesBySite = <String, List<Expense>>{};
      for (final site in _sites) {
        logsBySite[site.id] = await _db.getLogsForSite(site.id);
        materialsBySite[site.id] = await _db.getMaterialsForSite(site.id);
        expensesBySite[site.id] = await _db.getExpensesForSite(site.id);
      }
      final file = await ExcelExportService.generateProjectWorkbook(
        project: widget.project,
        sites: _sites,
        logsBySite: logsBySite,
        materialsBySite: materialsBySite,
        expensesBySite: expensesBySite,
      );
      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: '${widget.project.name} project export'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate Excel file: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingExcel = false);
    }
  }

  Future<void> _addSite() async {
    if (_nameController.text.trim().isEmpty) return;
    final site = Site(
      id: const Uuid().v4(),
      projectId: widget.project.id,
      name: _nameController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      createdAt: DateTime.now(),
    );
    await _db.insertSite(site);
    _nameController.clear();
    _addressController.clear();
    _load();
  }

  Future<void> _deleteSite(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Site?'),
        content: const Text('All logs and expenses for this site will be deleted. This cannot be undone.'),
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
      await _db.deleteSite(id);
      _load();
    }
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Site'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Site Name'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addSite();
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
        title: Text(widget.project.name),
        actions: [
          IconButton(
            icon: _generatingPdf
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf),
            tooltip: 'Export project report',
            onPressed: _generatingPdf ? null : _exportProjectPdf,
          ),
          IconButton(
            icon: _generatingExcel
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_chart),
            tooltip: 'Export project report (.xlsx)',
            onPressed: _generatingExcel ? null : _exportProjectExcel,
          ),
          if (widget.project.client != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(widget.project.client!, style: const TextStyle(fontSize: 14))),
            ),
        ],
      ),
      body: _sites.isEmpty
          ? const Center(child: Text('No sites yet. Tap + to add a site.'))
         : ListView.builder(
              itemCount: _sites.length,
              itemBuilder: (ctx, i) {
                final s = _sites[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: s.address != null ? Text(s.address!) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteSite(s.id),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SiteDetailScreen(site: s, project: widget.project),
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
