import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../models/daily_site_report_meta.dart';
import '../models/site.dart';
import '../models/attendance.dart';
import '../models/material_stock_log.dart';
import '../models/equipment_dipping_log.dart';
import '../models/concrete_pour.dart';
import '../models/cash_float.dart';
import '../models/expense.dart';
import '../models/worker.dart';
import '../utils/currency_formatter.dart';
import '../services/daily_report_meta_repository.dart';
import '../services/professional_daily_report_service.dart';

class DailyLogDetailScreen extends StatefulWidget {
  final DailyLog log;
  final Site site;
  const DailyLogDetailScreen({super.key, required this.log, required this.site});
  @override State<DailyLogDetailScreen> createState() => _DailyLogDetailScreenState();
}

class _DailyLogDetailScreenState extends State<DailyLogDetailScreen> {
  final _db = DatabaseHelper.instance;
  List<Attendance> _attendance = [];
  List<Worker> _workers = [];
  List<MaterialStockLog> _materials = [];
  List<EquipmentDippingLog> _equipment = [];
  List<ConcretePour> _concretePours = [];
  List<Expense> _expenses = [];
  CashFloat? _cashFloat;
  DailySiteReportMeta? _meta;
  bool _isLoading = true;
  bool _generatingPdf = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final dateIso = widget.log.date.toIso8601String().split('T').first;
    final results = await Future.wait([
      _db.getAttendanceForLog(widget.log.id),
      _db.getMaterialStockLogsForLog(widget.log.id),
      _db.getEquipmentDippingLogsForLog(widget.log.id),
      _db.getConcretePoursForLog(widget.log.id),
      _db.getWorkersForSite(widget.site.id, activeOnly: false),
      _db.getExpensesForSiteAndDate(widget.site.id, dateIso),
      _db.getCashFloatBySiteAndDate(widget.site.id, dateIso),
      DailyReportMetaRepository.getForLog(widget.log.id),
    ]);
    if (!mounted) return;
    setState(() {
      _attendance = results[0] as List<Attendance>;
      _materials = results[1] as List<MaterialStockLog>;
      _equipment = results[2] as List<EquipmentDippingLog>;
      _concretePours = results[3] as List<ConcretePour>;
      _workers = results[4] as List<Worker>;
      _expenses = results[5] as List<Expense>;
      _cashFloat = results[6] as CashFloat?;
      _meta = results[7] as DailySiteReportMeta?;
      _isLoading = false;
    });
  }

  Future<void> _generatePdf() async {
    setState(() => _generatingPdf = true);
    try {
      final file = await ProfessionalDailyReportService.generate(
        site: widget.site, log: widget.log, meta: _meta,
        attendance: _attendance, workers: _workers, materials: _materials,
        equipment: _equipment, concretePours: _concretePours,
        expenses: _expenses, cashFloat: _cashFloat,
      );
      if (mounted) await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'SWAS Grade Daily Site Progress Report — ${widget.site.name}'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate report: $e')));
    } finally { if (mounted) setState(() => _generatingPdf = false); }
  }

  Worker? _worker(String id) => _workers.where((w) => w.id == id).firstOrNull;
  Widget _section(String title) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 8), child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue.shade900)));
  Widget _row(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))), Expanded(child: Text(value))]));
  Widget _empty(String text) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(text)));

  @override Widget build(BuildContext context) {
    final date = DateFormat.yMMMd().format(widget.log.date);
    return Scaffold(
      appBar: AppBar(title: Text('$date — ${widget.site.name}', overflow: TextOverflow.ellipsis), actions: [IconButton(tooltip: 'Generate professional PDF', onPressed: _generatingPdf ? null : _generatePdf, icon: _generatingPdf ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf))]),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          _row('Report No.', _meta?.reportNo ?? 'SDL-${widget.log.id.substring(0, 8)}'),
          _row('Weather', widget.log.weather ?? 'Not recorded'), _row('Shift', _meta?.shift ?? 'Day'),
          _row('Crew', '${widget.log.crewCount ?? _attendance.length}'),
          if (_meta?.progressQuantity != null) _row('Quantity', '${_meta!.progressQuantity!.toStringAsFixed(2)} ${_meta?.progressUnit ?? ''}'),
          if (_meta?.percentComplete != null) _row('Progress', '${_meta!.percentComplete!.toStringAsFixed(1)}%'),
        ])),
        _section('Work Activities & Progress'), _empty(widget.log.workCompleted ?? 'No work activities recorded.'),
        if (widget.log.photoPaths.isNotEmpty) ...[_section('Site Photos'), SizedBox(height: 105, child: ListView(scrollDirection: Axis.horizontal, children: widget.log.photoPaths.map((path) => Padding(padding: const EdgeInsets.only(right: 8), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(path), width: 105, height: 105, fit: BoxFit.cover)))).toList()))],
        _section('Labour / Manpower'),
        if (_attendance.isEmpty) _empty('No attendance records.') else ..._attendance.map((a) { final w = _worker(a.workerId); return Card(child: ListTile(leading: const Icon(Icons.person_outline), title: Text(w?.name ?? 'Unknown'), subtitle: Text(w?.role ?? '-'), trailing: Chip(label: Text(a.status.label)))); }),
        _section('Material Stock / Consumption'),
        if (_materials.isEmpty) _empty('No material records.') else ..._materials.map((m) => Card(child: ListTile(title: Text(m.itemName), subtitle: Text('Opening ${m.openingBalance.toStringAsFixed(1)} • Received ${m.received.toStringAsFixed(1)} • Issued ${m.issued.toStringAsFixed(1)}'), trailing: Text('${m.closingBalance.toStringAsFixed(1)} ${m.unit}', style: const TextStyle(fontWeight: FontWeight.bold))))),
        _section('Fuel, Lubricant & Equipment'),
        if (_equipment.isEmpty) _empty('No equipment records.') else ..._equipment.map((e) => Card(child: ListTile(title: Text(e.equipmentName), subtitle: Text('Dip: ${e.openingDipCm?.toStringAsFixed(1) ?? '-'} → ${e.closingDipCm?.toStringAsFixed(1) ?? '-'} cm'), trailing: Text('${e.dieselIssuedLitres.toStringAsFixed(1)} L diesel')))),
        _section('Quality Control / Inspections'), _empty(_meta?.qualityInspections ?? 'No inspection notes recorded.'),
        if (_concretePours.isNotEmpty) ..._concretePours.map((c) => Card(child: ListTile(title: Text('${c.elementName} • ${c.concreteGrade}'), subtitle: Text('Volume ${c.volumeM3.toStringAsFixed(2)} m³ • Slump ${c.slumpMm?.toStringAsFixed(0) ?? '-'} mm'), trailing: Text('${c.cubesCast} cubes')))),
        _section('Health, Safety & Environment'), _empty(_meta?.hseObservations ?? 'No HSE observations recorded.'),
        _section('Expenses & Float'),
        if (_expenses.isEmpty) _empty('No expenses recorded.') else ..._expenses.map((e) => Card(child: ListTile(title: Text(e.displayDescription), subtitle: Text(e.category.label), trailing: Text(CurrencyFormatter.format(e.amount), style: const TextStyle(fontWeight: FontWeight.bold))))),
        if (_cashFloat != null) Card(color: Colors.blue.shade50, child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [_row('Opening', CurrencyFormatter.format(_cashFloat!.openingBalance)), _row('Float received', CurrencyFormatter.format(_cashFloat!.floatReceived)), _row('Closing', CurrencyFormatter.format(_cashFloat!.reportedClosingBalance)), _row('Variance', CurrencyFormatter.format(_cashFloat!.variance))]))),
        _section('Delays / Issues'), _empty(widget.log.issues ?? 'None recorded.'),
        _section('Site Instructions'), _empty(_meta?.siteInstructions ?? 'None recorded.'),
        _section('Next-Day Plan'), _empty(_meta?.nextDayPlan ?? 'Not recorded.'),
        _section('Document References'), _empty(_meta?.documentReferences ?? 'No drawing / RFI / document references recorded.'),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: _generatingPdf ? null : _generatePdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('Generate Professional Daily Report')),
        const SizedBox(height: 30),
      ]),
    );
  }
}
