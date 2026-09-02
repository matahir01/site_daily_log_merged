import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/cash_float.dart';
import '../models/concrete_pour.dart';
import '../models/daily_log.dart';
import '../models/diesel_activity_issuance.dart';
import '../models/equipment_dipping_log.dart';
import '../models/expense.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../utils/currency_formatter.dart';

/// Which file type(s) [BatchExportService] should produce for a batch run.
enum BatchExportFormat { pdf, excel, both }

/// Aggregates every Phase 1/2 record type for one site within a date
/// range, already resolved from the database and ready for either the
/// PDF or Excel builder to consume — keeps the two builders in lock-step
/// with a single source of truth per site/range combination.
class _SiteBatchData {
  final Site site;
  final List<DailyLog> logs;
  final List<ConcretePour> concretePours;
  final Map<String, DateTime> concretePourDates; // pour.id -> log date
  final List<EquipmentDippingLog> dippingLogs;
  final Map<String, DateTime> dippingLogDates; // log.id -> log date
  final List<DieselActivityIssuance> dieselActivity;
  final Map<String, DateTime> dieselActivityDates;
  final List<Expense> expenses;
  final List<CashFloat> cashFloats;

  _SiteBatchData({
    required this.site,
    required this.logs,
    required this.concretePours,
    required this.concretePourDates,
    required this.dippingLogs,
    required this.dippingLogDates,
    required this.dieselActivity,
    required this.dieselActivityDates,
    required this.expenses,
    required this.cashFloats,
  });

  double get totalConcreteVolume =>
      concretePours.fold<double>(0.0, (s, c) => s + c.volumeM3);
  double get totalDieselMachines =>
      dippingLogs.fold<double>(0.0, (s, e) => s + e.dieselIssuedLitres);
  double get totalDieselActivities =>
      dieselActivity.fold<double>(0.0, (s, d) => s + d.litresIssued);
  double get totalExpenses => expenses.fold<double>(0.0, (s, e) => s + e.amount);
}

/// Generates and aggregates multi-day or monthly site summary reports —
/// combining daily logs, concrete pours, dipping logs, diesel issuance,
/// and the expense ledger for one or more sites over a custom date range —
/// into a single PDF and/or Excel package.
class BatchExportService {
  static bool _inRange(DateTime d, DateTime start, DateTime end) {
    final day = DateTime(d.year, d.month, d.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !day.isBefore(s) && !day.isAfter(e);
  }

  /// Pulls and range-filters every record type for one site. Daily logs
  /// and expenses are already filtered at the query level; concrete
  /// pours, dipping logs, and diesel activity come back tagged with
  /// their parent daily log's date and are filtered here.
  static Future<_SiteBatchData> _loadSiteData(
    Site site,
    DateTime start,
    DateTime end,
  ) async {
    final db = DatabaseHelper.instance;

    final logs = await db.getLogsForSiteInRange(site.id, start, end);
    final expenses = await db.getExpensesForSiteInRange(site.id, start, end);
    final cashFloats = await db.getCashFloatsForSiteInRange(site.id, start, end);

    final allPourRows = await db.getConcretePoursForSite(site.id);
    final pours = <ConcretePour>[];
    final pourDates = <String, DateTime>{};
    for (final row in allPourRows) {
      final date = DateTime.parse(row['log_date'] as String);
      if (!_inRange(date, start, end)) continue;
      final pour = ConcretePour.fromMap(row);
      pours.add(pour);
      pourDates[pour.id] = date;
    }

    final allDippingRows = await db.getEquipmentDippingLogsForSite(site.id);
    final dippingLogs = <EquipmentDippingLog>[];
    final dippingDates = <String, DateTime>{};
    for (final row in allDippingRows) {
      final date = DateTime.parse(row['log_date'] as String);
      if (!_inRange(date, start, end)) continue;
      final log = EquipmentDippingLog.fromMap(row);
      dippingLogs.add(log);
      dippingDates[log.id] = date;
    }

    final allDieselRows = await db.getDieselActivityForSite(site.id);
    final dieselActivity = <DieselActivityIssuance>[];
    final dieselDates = <String, DateTime>{};
    for (final row in allDieselRows) {
      final date = DateTime.parse(row['log_date'] as String);
      if (!_inRange(date, start, end)) continue;
      final d = DieselActivityIssuance.fromMap(row);
      dieselActivity.add(d);
      dieselDates[d.id] = date;
    }

    return _SiteBatchData(
      site: site,
      logs: logs,
      concretePours: pours,
      concretePourDates: pourDates,
      dippingLogs: dippingLogs,
      dippingLogDates: dippingDates,
      dieselActivity: dieselActivity,
      dieselActivityDates: dieselDates,
      expenses: expenses,
      cashFloats: cashFloats,
    );
  }

  // ---------------------------------------------------------------------
  // Public entry points
  // ---------------------------------------------------------------------

  /// Builds a batch report for a single site over [startDate]..[endDate].
  /// Returns 1 or 2 files depending on [format].
  static Future<List<File>> generateSiteBatchReport({
    required Project project,
    required Site site,
    required DateTime startDate,
    required DateTime endDate,
    BatchExportFormat format = BatchExportFormat.both,
  }) async {
    final data = await _loadSiteData(site, startDate, endDate);
    final label = '${site.name}_batch';
    return _buildFiles(
      project: project,
      sitesData: [data],
      startDate: startDate,
      endDate: endDate,
      format: format,
      baseName: label,
      reportTitle: site.name,
    );
  }

  /// Builds one combined batch report across every site in [sites] —
  /// suitable for a monthly, multi-site project rollup.
  static Future<List<File>> generateProjectBatchReport({
    required Project project,
    required List<Site> sites,
    required DateTime startDate,
    required DateTime endDate,
    BatchExportFormat format = BatchExportFormat.both,
  }) async {
    final sitesData = <_SiteBatchData>[];
    for (final site in sites) {
      sitesData.add(await _loadSiteData(site, startDate, endDate));
    }
    return _buildFiles(
      project: project,
      sitesData: sitesData,
      startDate: startDate,
      endDate: endDate,
      format: format,
      baseName: '${project.name}_batch',
      reportTitle: project.name,
    );
  }

  /// Convenience wrapper: generates a site batch report and immediately
  /// opens the native share sheet with the resulting file(s), mirroring
  /// the existing single-report export flow used elsewhere in the app.
  static Future<void> generateAndShareSiteBatchReport({
    required BuildContext context,
    required Project project,
    required Site site,
    required DateTime startDate,
    required DateTime endDate,
    BatchExportFormat format = BatchExportFormat.both,
  }) async {
    final files = await generateSiteBatchReport(
      project: project,
      site: site,
      startDate: startDate,
      endDate: endDate,
      format: format,
    );
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: files.map((f) => XFile(f.path)).toList(),
        text: '${site.name} batch report '
            '(${DateFormat.yMMMd().format(startDate)} – ${DateFormat.yMMMd().format(endDate)})',
      ),
    );
  }

  /// Convenience wrapper for the project-wide batch report + share.
  static Future<void> generateAndShareProjectBatchReport({
    required BuildContext context,
    required Project project,
    required List<Site> sites,
    required DateTime startDate,
    required DateTime endDate,
    BatchExportFormat format = BatchExportFormat.both,
  }) async {
    final files = await generateProjectBatchReport(
      project: project,
      sites: sites,
      startDate: startDate,
      endDate: endDate,
      format: format,
    );
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: files.map((f) => XFile(f.path)).toList(),
        text: '${project.name} batch report '
            '(${DateFormat.yMMMd().format(startDate)} – ${DateFormat.yMMMd().format(endDate)})',
      ),
    );
  }

  static Future<List<File>> _buildFiles({
    required Project project,
    required List<_SiteBatchData> sitesData,
    required DateTime startDate,
    required DateTime endDate,
    required BatchExportFormat format,
    required String baseName,
    required String reportTitle,
  }) async {
    final files = <File>[];
    if (format == BatchExportFormat.pdf || format == BatchExportFormat.both) {
      files.add(await _buildPdf(
        project: project,
        sitesData: sitesData,
        startDate: startDate,
        endDate: endDate,
        baseName: baseName,
        reportTitle: reportTitle,
      ));
    }
    if (format == BatchExportFormat.excel || format == BatchExportFormat.both) {
      files.add(await _buildExcel(
        project: project,
        sitesData: sitesData,
        startDate: startDate,
        endDate: endDate,
        baseName: baseName,
      ));
    }
    return files;
  }

  // ---------------------------------------------------------------------
  // PDF builder
  // ---------------------------------------------------------------------

  static pw.ThemeData? _cachedTheme;

  static Future<pw.ThemeData> _loadTheme() async {
    final cached = _cachedTheme;
    if (cached != null) return cached;
    final regularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
    _cachedTheme = theme;
    return theme;
  }

  static Future<File> _buildPdf({
    required Project project,
    required List<_SiteBatchData> sitesData,
    required DateTime startDate,
    required DateTime endDate,
    required String baseName,
    required String reportTitle,
  }) async {
    final theme = await _loadTheme();
    final doc = pw.Document(theme: theme);
    final dateFmt = DateFormat.yMMMd();
    final rangeLabel = '${dateFmt.format(startDate)} – ${dateFmt.format(endDate)}';

    final grandExpenses = sitesData.fold<double>(0.0, (s, d) => s + d.totalExpenses);
    final grandConcrete = sitesData.fold<double>(0.0, (s, d) => s + d.totalConcreteVolume);
    final grandDiesel = sitesData.fold<double>(
        0.0, (s, d) => s + d.totalDieselMachines + d.totalDieselActivities);
    final grandLogs = sitesData.fold<int>(0, (s, d) => s + d.logs.length);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            '$reportTitle — Batch Summary Report',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Period: $rangeLabel', style: const pw.TextStyle(fontSize: 13)),
          pw.Text(
            'Generated: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 12),
          _kpiRow([
            _KpiPair('Sites', '${sitesData.length}'),
            _KpiPair('Daily Logs', '$grandLogs'),
            _KpiPair('Total Expenditure', CurrencyFormatter.format(grandExpenses)),
            _KpiPair('Concrete Poured', '${grandConcrete.toStringAsFixed(1)} m³'),
            _KpiPair('Diesel Issued', '${grandDiesel.toStringAsFixed(0)} L'),
          ]),
          pw.SizedBox(height: 16),
          pw.Divider(),
          for (final data in sitesData) ..._sitePdfSections(data, dateFmt),
        ],
      ),
    );

    return _saveDoc(doc, baseName);
  }

  static List<pw.Widget> _sitePdfSections(_SiteBatchData data, DateFormat dateFmt) {
    return [
      pw.SizedBox(height: 12),
      pw.Text(
        data.site.name,
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1A365D')),
      ),
      if (data.site.address != null)
        pw.Text(data.site.address!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 8),

      pw.Text('Daily Logs', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
      pw.SizedBox(height: 4),
      data.logs.isEmpty
          ? pw.Text('No daily logs recorded in this range.')
          : pw.TableHelper.fromTextArray(
              headers: ['Date', 'Weather', 'Crew', 'Work Completed', 'Issues'],
              data: data.logs
                  .map((l) => [
                        dateFmt.format(l.date),
                        l.weather ?? '',
                        l.crewCount?.toString() ?? '',
                        _truncate(l.workCompleted ?? '', 60),
                        _truncate(l.issues ?? '', 40),
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
            ),
      pw.SizedBox(height: 12),

      pw.Text('Concrete Pours / Slump QC', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
      pw.SizedBox(height: 4),
      data.concretePours.isEmpty
          ? pw.Text('No concrete pours recorded in this range.')
          : pw.TableHelper.fromTextArray(
              headers: ['Date', 'Element', 'Grade', 'Vol (m³)', 'Slump (mm)', 'Cubes', 'Ticket #'],
              data: data.concretePours
                  .map((c) => [
                        dateFmt.format(data.concretePourDates[c.id] ?? DateTime.now()),
                        c.elementName,
                        c.concreteGrade,
                        c.volumeM3.toStringAsFixed(2),
                        c.slumpMm?.toStringAsFixed(0) ?? '',
                        '${c.cubesCast}',
                        c.batchTicketNo ?? '',
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
            ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Total volume: ${data.totalConcreteVolume.toStringAsFixed(2)} m³',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      ),
      pw.SizedBox(height: 12),

      pw.Text('Equipment Dipping / Fuel Logs', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
      pw.SizedBox(height: 4),
      data.dippingLogs.isEmpty
          ? pw.Text('No dipping logs recorded in this range.')
          : pw.TableHelper.fromTextArray(
              headers: ['Date', 'Equipment', 'Diesel (L)', 'Oil (L)', 'Op. Hours', 'L/hr'],
              data: data.dippingLogs
                  .map((e) => [
                        dateFmt.format(data.dippingLogDates[e.id] ?? DateTime.now()),
                        e.equipmentName,
                        e.dieselIssuedLitres.toStringAsFixed(1),
                        e.engineOilIssuedLitres.toStringAsFixed(1),
                        e.operatingHours?.toStringAsFixed(1) ?? '',
                        e.fuelBurnRateLitresPerHour?.toStringAsFixed(2) ?? '',
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
            ),
      pw.SizedBox(height: 8),
      pw.Text('Diesel Issued to Non-Dipped Activities', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
      pw.SizedBox(height: 4),
      data.dieselActivity.isEmpty
          ? pw.Text('None recorded in this range.')
          : pw.TableHelper.fromTextArray(
              headers: ['Date', 'Activity', 'Litres Issued'],
              data: data.dieselActivity
                  .map((d) => [
                        dateFmt.format(data.dieselActivityDates[d.id] ?? DateTime.now()),
                        d.activityName,
                        d.litresIssued.toStringAsFixed(1),
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
            ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Total diesel issued: ${(data.totalDieselMachines + data.totalDieselActivities).toStringAsFixed(1)} L',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        ),
      ),
      pw.SizedBox(height: 12),

      pw.Text('Expense Ledger', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
      pw.SizedBox(height: 4),
      data.expenses.isEmpty
          ? pw.Text('No expenses recorded in this range.')
          : pw.TableHelper.fromTextArray(
              headers: ['Date', 'Category', 'Description', 'Amount'],
              data: data.expenses
                  .map((e) => [
                        dateFmt.format(e.date),
                        e.category.label,
                        _truncate(e.displayDescription, 50),
                        CurrencyFormatter.format(e.amount),
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
            ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Total: ${CurrencyFormatter.format(data.totalExpenses)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
      ),
      pw.SizedBox(height: 12),

      pw.Text('Cash Float Reconciliation', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
      pw.SizedBox(height: 4),
      data.cashFloats.isEmpty
          ? pw.Text('No cash float entries recorded in this range.')
          : pw.TableHelper.fromTextArray(
              headers: ['Date', 'Opening', 'Received', 'Expenses', 'Exp. Close', 'Rep. Close', 'Status'],
              data: data.cashFloats
                  .map((c) => [
                        dateFmt.format(c.date),
                        CurrencyFormatter.format(c.openingBalance),
                        CurrencyFormatter.format(c.floatReceived),
                        CurrencyFormatter.format(c.totalExpenses),
                        CurrencyFormatter.format(c.expectedClosingBalance),
                        CurrencyFormatter.format(c.reportedClosingBalance),
                        c.status.label,
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
            ),
      pw.SizedBox(height: 20),
      pw.Divider(),
    ];
  }

  static pw.Widget _kpiRow(List<_KpiPair> kpis) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: kpis
          .map((k) => pw.Expanded(
                child: pw.Container(
                  margin: const pw.EdgeInsets.symmetric(horizontal: 2),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#EBF8FF'),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(k.label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text(k.value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  static String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';

  static Future<File> _saveDoc(pw.Document doc, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(p.join(dir.path, 'reports'));
    await reportsDir.create(recursive: true);
    final safeName = baseName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(reportsDir.path, '${safeName}_$timestamp.pdf'));
    await file.writeAsBytes(await doc.save());
    return file;
  }

  // ---------------------------------------------------------------------
  // Excel builder
  // ---------------------------------------------------------------------

  static Future<File> _buildExcel({
    required Project project,
    required List<_SiteBatchData> sitesData,
    required DateTime startDate,
    required DateTime endDate,
    required String baseName,
  }) async {
    final excel = xls.Excel.createExcel();
    final dateFmt = DateFormat.yMMMd();
    final multiSite = sitesData.length > 1;

    _buildSummarySheet(excel, sitesData, startDate, endDate);
    _buildLogsSheet(excel, sitesData, dateFmt, multiSite);
    _buildConcreteSheet(excel, sitesData, dateFmt, multiSite);
    _buildDippingSheet(excel, sitesData, dateFmt, multiSite);
    _buildExpensesSheet(excel, sitesData, dateFmt, multiSite);
    _buildCashFloatSheet(excel, sitesData, dateFmt, multiSite);

    if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
      excel.delete('Sheet1');
    }

    return _saveExcel(excel, baseName);
  }

  static void _buildSummarySheet(
    xls.Excel excel,
    List<_SiteBatchData> sitesData,
    DateTime start,
    DateTime end,
  ) {
    final sheet = excel['Summary'];
    final fmt = DateFormat.yMMMd();
    sheet.appendRow([xls.TextCellValue('Batch Report Period')]);
    sheet.appendRow([xls.TextCellValue('${fmt.format(start)} - ${fmt.format(end)}')]);
    sheet.appendRow([]);
    _writeHeader(sheet, ['Site', 'Logs', 'Concrete (m³)', 'Diesel (L)', 'Total Expenses']);
    var rowIdx = 4;
    for (final d in sitesData) {
      _writeRow(sheet, rowIdx++, [
        d.site.name,
        d.logs.length,
        d.totalConcreteVolume,
        d.totalDieselMachines + d.totalDieselActivities,
        d.totalExpenses,
      ]);
    }
    _writeRow(
      sheet,
      rowIdx,
      [
        'TOTAL',
        sitesData.fold<int>(0, (s, d) => s + d.logs.length),
        sitesData.fold<double>(0.0, (s, d) => s + d.totalConcreteVolume),
        sitesData.fold<double>(0.0, (s, d) => s + d.totalDieselMachines + d.totalDieselActivities),
        sitesData.fold<double>(0.0, (s, d) => s + d.totalExpenses),
      ],
      isBold: true,
    );
    _autoWidth(sheet, 5);
  }

  static void _buildLogsSheet(
    xls.Excel excel,
    List<_SiteBatchData> sitesData,
    DateFormat dateFmt,
    bool multiSite,
  ) {
    final sheet = excel['Daily Logs'];
    final headers = [
      if (multiSite) 'Site',
      'Date',
      'Weather',
      'Crew Count',
      'Work Completed',
      'Issues / Delays',
    ];
    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());
    for (final d in sitesData) {
      for (final log in d.logs) {
        sheet.appendRow([
          if (multiSite) xls.TextCellValue(d.site.name),
          xls.TextCellValue(dateFmt.format(log.date)),
          xls.TextCellValue(log.weather ?? ''),
          if (log.crewCount != null) xls.IntCellValue(log.crewCount!) else xls.TextCellValue(''),
          xls.TextCellValue(log.workCompleted ?? ''),
          xls.TextCellValue(log.issues ?? ''),
        ]);
      }
    }
    _autoWidth(sheet, headers.length);
  }

  static void _buildConcreteSheet(
    xls.Excel excel,
    List<_SiteBatchData> sitesData,
    DateFormat dateFmt,
    bool multiSite,
  ) {
    final sheet = excel['Concrete Pours'];
    final headers = [
      if (multiSite) 'Site',
      'Date',
      'Element',
      'Grade',
      'Volume (m³)',
      'Slump (mm)',
      'Cubes Cast',
      'Batch Ticket #',
    ];
    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());
    for (final d in sitesData) {
      for (final c in d.concretePours) {
        sheet.appendRow([
          if (multiSite) xls.TextCellValue(d.site.name),
          xls.TextCellValue(dateFmt.format(d.concretePourDates[c.id] ?? DateTime.now())),
          xls.TextCellValue(c.elementName),
          xls.TextCellValue(c.concreteGrade),
          xls.DoubleCellValue(c.volumeM3),
          if (c.slumpMm != null) xls.DoubleCellValue(c.slumpMm!) else xls.TextCellValue(''),
          xls.IntCellValue(c.cubesCast),
          xls.TextCellValue(c.batchTicketNo ?? ''),
        ]);
      }
    }
    _autoWidth(sheet, headers.length);
  }

  static void _buildDippingSheet(
    xls.Excel excel,
    List<_SiteBatchData> sitesData,
    DateFormat dateFmt,
    bool multiSite,
  ) {
    final sheet = excel['Dipping & Diesel'];
    final dippingHeaders = [
      if (multiSite) 'Site',
      'Date',
      'Equipment',
      'Diesel Issued (L)',
      'Engine Oil (L)',
      'Operating Hours',
      'Burn Rate (L/hr)',
    ];
    sheet.appendRow(dippingHeaders.map((h) => xls.TextCellValue(h)).toList());
    for (final d in sitesData) {
      for (final e in d.dippingLogs) {
        sheet.appendRow([
          if (multiSite) xls.TextCellValue(d.site.name),
          xls.TextCellValue(dateFmt.format(d.dippingLogDates[e.id] ?? DateTime.now())),
          xls.TextCellValue(e.equipmentName),
          xls.DoubleCellValue(e.dieselIssuedLitres),
          xls.DoubleCellValue(e.engineOilIssuedLitres),
          if (e.operatingHours != null) xls.DoubleCellValue(e.operatingHours!) else xls.TextCellValue(''),
          if (e.fuelBurnRateLitresPerHour != null)
            xls.DoubleCellValue(e.fuelBurnRateLitresPerHour!)
          else
            xls.TextCellValue(''),
        ]);
      }
    }
    sheet.appendRow([]);
    final activityHeaders = [
      if (multiSite) 'Site',
      'Date',
      'Activity',
      'Litres Issued',
    ];
    sheet.appendRow(activityHeaders.map((h) => xls.TextCellValue(h)).toList());
    for (final d in sitesData) {
      for (final act in d.dieselActivity) {
        sheet.appendRow([
          if (multiSite) xls.TextCellValue(d.site.name),
          xls.TextCellValue(dateFmt.format(d.dieselActivityDates[act.id] ?? DateTime.now())),
          xls.TextCellValue(act.activityName),
          xls.DoubleCellValue(act.litresIssued),
        ]);
      }
    }
    _autoWidth(sheet, dippingHeaders.length);
  }

  static void _buildExpensesSheet(
    xls.Excel excel,
    List<_SiteBatchData> sitesData,
    DateFormat dateFmt,
    bool multiSite,
  ) {
    final sheet = excel['Expenses'];
    final headers = [
      if (multiSite) 'Site',
      'Date',
      'Category',
      'Description',
      'Amount',
    ];
    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());
    double grandTotal = 0;
    for (final d in sitesData) {
      for (final e in d.expenses) {
        grandTotal += e.amount;
        sheet.appendRow([
          if (multiSite) xls.TextCellValue(d.site.name),
          xls.TextCellValue(dateFmt.format(e.date)),
          xls.TextCellValue(e.category.label),
          xls.TextCellValue(e.displayDescription),
          xls.DoubleCellValue(e.amount),
        ]);
      }
    }
    sheet.appendRow([]);
    final totalRow = [
      for (var i = 0; i < headers.length - 2; i++) xls.TextCellValue(''),
      xls.TextCellValue('Total'),
      xls.DoubleCellValue(grandTotal),
    ];
    sheet.appendRow(totalRow);
    _autoWidth(sheet, headers.length);
  }

  static void _buildCashFloatSheet(
    xls.Excel excel,
    List<_SiteBatchData> sitesData,
    DateFormat dateFmt,
    bool multiSite,
  ) {
    final sheet = excel['Cash Floats'];
    final headers = [
      if (multiSite) 'Site',
      'Date',
      'Opening',
      'Float Received',
      'Total Expenses',
      'Expected Close',
      'Reported Close',
      'Variance',
      'Status',
    ];
    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());
    for (final d in sitesData) {
      for (final c in d.cashFloats) {
        sheet.appendRow([
          if (multiSite) xls.TextCellValue(d.site.name),
          xls.TextCellValue(dateFmt.format(c.date)),
          xls.DoubleCellValue(c.openingBalance),
          xls.DoubleCellValue(c.floatReceived),
          xls.DoubleCellValue(c.totalExpenses),
          xls.DoubleCellValue(c.expectedClosingBalance),
          xls.DoubleCellValue(c.reportedClosingBalance),
          xls.DoubleCellValue(c.variance),
          xls.TextCellValue(c.status.label),
        ]);
      }
    }
    _autoWidth(sheet, headers.length);
  }

  static void _writeHeader(xls.Sheet sheet, List<dynamic> headers) {
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xls.TextCellValue(headers[i].toString());
      cell.cellStyle = xls.CellStyle(bold: true);
    }
  }

  static void _writeRow(xls.Sheet sheet, int rowIndex, List<dynamic> values, {bool isBold = false}) {
    for (int i = 0; i < values.length; i++) {
      final cell = sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex));
      final val = values[i];
      if (val is String) {
        cell.value = xls.TextCellValue(val);
      } else if (val is int) {
        cell.value = xls.IntCellValue(val);
      } else if (val is double) {
        cell.value = xls.DoubleCellValue(val);
      }
      if (isBold) {
        cell.cellStyle = xls.CellStyle(bold: true);
      }
    }
  }

  static void _autoWidth(xls.Sheet sheet, int columnCount) {
    for (var i = 0; i < columnCount; i++) {
      sheet.setColumnWidth(i, 22);
    }
  }

  static Future<File> _saveExcel(xls.Excel excel, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(p.join(dir.path, 'reports'));
    await reportsDir.create(recursive: true);
    final safeName = baseName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(reportsDir.path, '${safeName}_$timestamp.xlsx'));
    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Failed to encode the Excel workbook.');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

class _KpiPair {
  final String label;
  final String value;
  _KpiPair(this.label, this.value);
}
