import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../models/site.dart';
import '../models/attendance.dart';
import '../models/material_stock_log.dart';
import '../models/equipment_dipping_log.dart';
import '../models/expense.dart';
import '../models/worker.dart';
import '../utils/currency_formatter.dart';
import '../services/pdf_report_service.dart';

/// Read-only daily log detail with attendance, materials, equipment,
/// expenses, and a one-tap PDF export.
class DailyLogDetailScreen extends StatefulWidget {
  final DailyLog log;
  final Site site;

  const DailyLogDetailScreen({
    super.key,
    required this.log,
    required this.site,
  });

  @override
  State<DailyLogDetailScreen> createState() => _DailyLogDetailScreenState();
}

class _DailyLogDetailScreenState extends State<DailyLogDetailScreen> {
  final _db = DatabaseHelper.instance;
  List<Attendance> _attendance = [];
  List<Worker> _workers = [];
  List<MaterialStockLog> _materials = [];
  List<EquipmentDippingLog> _equipment = [];
  List<Expense> _expenses = [];
  bool _isLoading = true;
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final attData = await _db.getAttendanceForLog(widget.log.id);
    final matData = await _db.getMaterialStockLogsForLog(widget.log.id);
    final eqData = await _db.getEquipmentDippingLogsForLog(widget.log.id);
    final workerData = await _db.getWorkersForSite(widget.site.id, activeOnly: false);
    final dateIso = widget.log.date.toIso8601String().split('T').first;
    final expData = await _db.getExpensesForSiteAndDate(widget.site.id, dateIso);

    setState(() {
      _attendance = attData;
      _materials = matData;
      _equipment = eqData;
      _workers = workerData;
      _expenses = expData;
      _isLoading = false;
    });
  }

  Future<void> _generatePdf() async {
    setState(() => _generatingPdf = true);
    try {
      final file = await PdfReportService.generateDailyLogReport(
        site: widget.site,
        log: widget.log,
        attendance: _attendance,
        workers: _workers,
        materials: _materials,
        equipment: _equipment,
        expenses: _expenses,
      );
      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'Site Daily Report — ${widget.site.name}',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  String _workerName(String workerId) {
    final w = _workers.where((x) => x.id == workerId).firstOrNull;
    return w?.name ?? 'Unknown';
  }

  String _workerRole(String workerId) {
    final w = _workers.where((x) => x.id == workerId).firstOrNull;
    return w?.role ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    final dateStr = dateFmt.format(widget.log.date);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$dateStr — ${widget.site.name}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: _generatingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
            onPressed: _generatingPdf ? null : _generatePdf,
            tooltip: 'Export PDF',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader('Log Details'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.log.weather != null)
                            _detailRow('Weather', widget.log.weather!),
                          if (widget.log.crewCount != null)
                            _detailRow('Crew Count', '${widget.log.crewCount}'),
                          if (widget.log.workCompleted != null &&
                              widget.log.workCompleted!.isNotEmpty)
                            _detailRow(
                              'Work Completed',
                              widget.log.workCompleted!,
                            ),
                          if (widget.log.issues != null &&
                              widget.log.issues!.isNotEmpty)
                            _detailRow('Issues', widget.log.issues!),
                          if (widget.log.latitude != null)
                            _detailRow(
                              'GPS',
                              '${widget.log.latitude!.toStringAsFixed(6)}, ${widget.log.longitude!.toStringAsFixed(6)}',
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.log.photoPaths.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionHeader('Photos'),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.log.photoPaths.length,
                        itemBuilder: (ctx, i) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(widget.log.photoPaths[i]),
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _SectionHeader('Crew Attendance'),
                  if (_attendance.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No attendance records'),
                      ),
                    )
                  else
                    ..._attendance.map((a) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(_workerName(a.workerId)),
                            subtitle: Text(_workerRole(a.workerId)),
                            trailing: Chip(
                              label: Text(a.status.label),
                              backgroundColor: a.status == AttendanceStatus.present
                                  ? Colors.green.shade100
                                  : a.status == AttendanceStatus.halfDay
                                      ? Colors.orange.shade100
                                      : Colors.red.shade100,
                            ),
                          ),
                        )),
                  const SizedBox(height: 24),
                  _SectionHeader('Material Stock Reconciliation'),
                  if (_materials.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No material records'),
                      ),
                    )
                  else
                    _buildDataTable(
                      columns: ['Item', 'Open', 'Recv', 'Issue', 'Close'],
                      rows: _materials.map((m) => [
                        '${m.itemName} (${m.unit})',
                        m.openingBalance.toStringAsFixed(1),
                        m.received.toStringAsFixed(1),
                        m.issued.toStringAsFixed(1),
                        m.closingBalance.toStringAsFixed(1),
                      ]).toList(),
                    ),
                  const SizedBox(height: 24),
                  _SectionHeader('Equipment Dipping & Fuel'),
                  if (_equipment.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No equipment records'),
                      ),
                    )
                  else
                    _buildDataTable(
                      columns: [
                        'Equipment',
                        'Open(cm)',
                        'Close(cm)',
                        'Diesel(L)',
                        'Oil(L)',
                      ],
                      rows: _equipment.map((e) => [
                        e.equipmentName,
                        e.openingDipCm?.toStringAsFixed(1) ?? '-',
                        e.closingDipCm?.toStringAsFixed(1) ?? '-',
                        e.dieselIssuedLitres.toStringAsFixed(1),
                        e.engineOilIssuedLitres.toStringAsFixed(1),
                      ]).toList(),
                    ),
                  const SizedBox(height: 24),
                  _SectionHeader('Itemized Expenses'),
                  if (_expenses.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No expenses recorded'),
                      ),
                    )
                  else
                    Column(
                      children: [
                        ..._expenses.map((e) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${e.serialNo ?? 0}'),
                                ),
                                title: Text(e.displayDescription),
                                subtitle: Text(e.category.label),
                                trailing: Text(
                                  CurrencyFormatter.format(e.amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade900,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                CurrencyFormatter.format(
                                  _expenses.fold(0.0, (s, e) => s + e.amount),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _SectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade900,
            ),
      ),
    );
  }

  Widget _buildDataTable({
    required List<String> columns,
    required List<List<String>> rows,
  }) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
          columns: columns
              .map((c) => DataColumn(
                    label: Text(
                      c,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ))
              .toList(),
          rows: rows.map((r) {
            return DataRow(
              cells: r.map((cell) => DataCell(Text(cell))).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}
