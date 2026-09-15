import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/attendance.dart';
import '../models/cash_float.dart';
import '../models/concrete_pour.dart';
import '../models/daily_log.dart';
import '../models/daily_site_report_meta.dart';
import '../models/diesel_activity_issuance.dart';
import '../models/equipment_dipping_log.dart';
import '../models/expense.dart';
import '../models/material_stock_log.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/worker.dart';
import '../utils/currency_formatter.dart';

/// Generates the formal Daily Site Progress Report from the app's existing
/// records. Report-specific metadata is optional; operational data comes
/// from the same attendance/material/equipment/concrete/expense records used
/// elsewhere in the app, so users never re-enter the same site data twice.
class ProfessionalDailyReportService {
  static final PdfColor _navy = PdfColor.fromHex('#153A5B');
  static final PdfColor _blue = PdfColor.fromHex('#2B6CB0');
  static final PdfColor _paleBlue = PdfColor.fromHex('#EAF2F8');
  static final PdfColor _border = PdfColors.blueGrey300;
  static pw.ThemeData? _cachedTheme;

  static Future<pw.ThemeData> _theme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _cachedTheme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
    return _cachedTheme!;
  }

  static Future<File> generate({
    required Site site,
    Project? project,
    required DailyLog log,
    DailySiteReportMeta? meta,
    required List<Attendance> attendance,
    required List<Worker> workers,
    required List<MaterialStockLog> materials,
    required List<EquipmentDippingLog> equipment,
    required List<Expense> expenses,
    List<DieselActivityIssuance> dieselActivity = const [],
    List<ConcretePour> concretePours = const [],
    CashFloat? cashFloat,
    String companyName = 'SWAS GRADE LIMITED',
  }) async {
    final doc = pw.Document(theme: await _theme());
    final date = DateFormat('dd MMMM yyyy').format(log.date);
    final day = DateFormat('EEEE').format(log.date);
    final shortId = log.id.length > 6 ? log.id.substring(0, 6) : log.id;
    final reportNo = _text(meta?.reportNo).isEmpty
        ? 'DPR-${DateFormat('yyyyMMdd').format(log.date)}-${shortId.toUpperCase()}'
        : _text(meta?.reportNo);
    final totalExpenses = expenses.fold<double>(0, (sum, e) => sum + e.amount);
    final workerById = {for (final worker in workers) worker.id: worker};

    final activeAttendance = attendance
        .where((a) => a.status != AttendanceStatus.absent)
        .toList();
    final roleCounts = <String, int>{};
    for (final a in activeAttendance) {
      final role = workerById[a.workerId]?.role ?? 'Unclassified';
      roleCounts[role] = (roleCounts[role] ?? 0) + 1;
    }

    final manpowerRows = roleCounts.entries
        .map((e) => [e.key, e.value.toString()])
        .toList();
    if (manpowerRows.isEmpty && log.crewCount != null) {
      manpowerRows.add(['Reported crew count', '${log.crewCount}']);
    }

    final expenseRows = expenses.map((e) {
      final unitPrice = e.unitPrice ?? e.amount;
      final quantity = unitPrice == 0 ? null : e.amount / unitPrice;
      return [
        e.serialNo?.toString() ?? '',
        e.displayDescription.isEmpty ? e.category.label : e.displayDescription,
        quantity == null ? '-' : _number(quantity),
        e.unit ?? '-',
        CurrencyFormatter.format(unitPrice),
        CurrencyFormatter.format(e.amount),
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 30),
        header: (context) => _header(companyName, reportNo),
        footer: (context) => _footer(context),
        build: (context) => [
          pw.SizedBox(height: 6),
          _title('DAILY SITE PROGRESS REPORT'),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              'Progress, Resources, Quality, Safety & Expense Reconciliation',
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 12),
          _infoGrid([
            ['Project', project?.name ?? 'N/A'],
            ['Client', project?.client ?? 'N/A'],
            ['Site', site.name],
            ['Location', site.address ?? 'N/A'],
            ['Report No.', reportNo],
            ['Date', date],
            ['Day', day],
            ['Weather', log.weather ?? 'Not recorded'],
            ['Shift', _text(meta?.shift).isEmpty ? 'Day' : _text(meta?.shift)],
            ['Prepared by', _fallback(meta?.preparedBy, 'Not recorded')],
            ['Position', _fallback(meta?.preparedByPosition, 'Site/Design Engineer')],
            ['GPS', log.latitude == null
                ? 'Not recorded'
                : '${log.latitude!.toStringAsFixed(6)}, ${log.longitude!.toStringAsFixed(6)}'],
          ]),
          pw.SizedBox(height: 14),

          _section('1. WORK ACTIVITIES & PROGRESS'),
          _textBlock(
            _text(log.workCompleted).isEmpty
                ? 'No work activities recorded.'
                : _text(log.workCompleted),
          ),
          pw.SizedBox(height: 6),
          _infoGrid([
            ['Measured quantity', _progressQuantity(meta)],
            ['Progress', meta?.percentComplete == null
                ? 'Not recorded'
                : '${meta!.percentComplete!.toStringAsFixed(1)}%'],
          ], columns: 2),
          pw.SizedBox(height: 12),

          _section('2. LABOUR / MANPOWER'),
          if (manpowerRows.isEmpty)
            _empty('No manpower record for this daily log.')
          else
            _table(['Trade / Role', 'No. on Site'], manpowerRows, widths: const [4, 1]),
          if (attendance.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            _infoGrid([
              ['Present', attendance.where((a) => a.status == AttendanceStatus.present).length.toString()],
              ['Half-day', attendance.where((a) => a.status == AttendanceStatus.halfDay).length.toString()],
              ['Absent', attendance.where((a) => a.status == AttendanceStatus.absent).length.toString()],
              ['Total rostered', attendance.length.toString()],
            ], columns: 4),
          ],
          pw.SizedBox(height: 12),

          _section('3. MATERIAL STOCK / CONSUMPTION'),
          if (materials.isEmpty)
            _empty('No material stock records.')
          else
            _table(
              ['Material', 'Unit', 'Opening', 'Received', 'Issued', 'Closing'],
              materials.map((m) => [
                m.itemName,
                m.unit,
                _number(m.openingBalance),
                _number(m.received),
                _number(m.issued),
                _number(m.closingBalance),
              ]).toList(),
              widths: const [3, 1, 1.2, 1.2, 1.2, 1.2],
            ),
          pw.SizedBox(height: 12),

          _section('4. FUEL, LUBRICANT & EQUIPMENT UTILISATION'),
          if (equipment.isEmpty)
            _empty('No equipment dipping or utilisation records.')
          else
            _table(
              ['Equipment', 'Open Dip', 'Diesel L', 'Oil L', 'Close Dip', 'Hours'],
              equipment.map((e) => [
                e.equipmentName,
                e.openingDipCm?.toStringAsFixed(1) ?? '-',
                e.dieselIssuedLitres.toStringAsFixed(1),
                e.engineOilIssuedLitres.toStringAsFixed(1),
                e.closingDipCm?.toStringAsFixed(1) ?? '-',
                e.operatingHours?.toStringAsFixed(1) ?? '-',
              ]).toList(),
              widths: const [3, 1.1, 1, 1, 1.1, 1],
            ),
          if (dieselActivity.isNotEmpty) ...[
            pw.SizedBox(height: 7),
            pw.Text('Diesel issued directly to activities', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            _table(
              ['Activity / Machine', 'Litres'],
              dieselActivity.map((d) => [d.activityName, d.litresIssued.toStringAsFixed(1)]).toList(),
              widths: const [4, 1],
            ),
          ],
          pw.SizedBox(height: 12),

          _section('5. QUALITY CONTROL / INSPECTIONS'),
          if (_text(meta?.qualityInspections).isNotEmpty)
            _textBlock(_text(meta?.qualityInspections)),
          if (concretePours.isEmpty && _text(meta?.qualityInspections).isEmpty)
            _empty('No quality-control or inspection record.'),
          if (concretePours.isNotEmpty) ...[
            if (_text(meta?.qualityInspections).isNotEmpty) pw.SizedBox(height: 7),
            _table(
              ['Element', 'Grade', 'Vol. m³', 'Slump mm', 'Cubes', 'Ticket'],
              concretePours.map((c) => [
                c.elementName,
                c.concreteGrade,
                c.volumeM3.toStringAsFixed(2),
                c.slumpMm?.toStringAsFixed(0) ?? '-',
                c.cubesCast.toString(),
                c.batchTicketNo ?? '-',
              ]).toList(),
              widths: const [2.4, 1, 1, 1, 0.8, 1.3],
            ),
          ],
          pw.SizedBox(height: 12),

          _section('6. HEALTH, SAFETY & ENVIRONMENT'),
          _textBlock(
            _text(meta?.hseObservations).isEmpty
                ? 'No HSE observation recorded.'
                : _text(meta?.hseObservations),
          ),
          pw.SizedBox(height: 12),

          _section('7. SITE EXPENSES & FLOAT RECONCILIATION'),
          if (expenseRows.isEmpty)
            _empty('No expenses recorded for this date.')
          else ...[
            _table(
              ['S/N', 'Description', 'Qty', 'Unit', 'Unit Rate', 'Amount'],
              expenseRows,
              widths: const [0.6, 3, 0.8, 0.9, 1.3, 1.4],
            ),
            pw.SizedBox(height: 6),
            _moneyBar('TOTAL EXPENSES', totalExpenses),
          ],
          if (cashFloat != null) ...[
            pw.SizedBox(height: 7),
            _infoGrid([
              ['Previous / opening balance', CurrencyFormatter.format(cashFloat.openingBalance)],
              ['Float received', CurrencyFormatter.format(cashFloat.floatReceived)],
              ['Expected closing balance', CurrencyFormatter.format(cashFloat.expectedClosingBalance)],
              ['Reported closing balance', CurrencyFormatter.format(cashFloat.reportedClosingBalance)],
              ['Variance', CurrencyFormatter.format(cashFloat.variance)],
              ['Status', cashFloat.status.label],
            ], columns: 2),
            if (_text(cashFloat.notes).isNotEmpty) ...[
              pw.SizedBox(height: 5),
              _textBlock(_text(cashFloat.notes)),
            ],
          ],
          pw.SizedBox(height: 12),

          _section('8. DELAYS, ISSUES, INSTRUCTIONS & NEXT-DAY PLAN'),
          _labelledText('Issues / Delays', _fallback(log.issues, 'None recorded.')),
          _labelledText('Site Instructions', _fallback(meta?.siteInstructions, 'None recorded.')),
          _labelledText('Next-Day Plan', _fallback(meta?.nextDayPlan, 'Not recorded.')),
          pw.SizedBox(height: 12),

          _section('9. PHOTO / DOCUMENT REFERENCES'),
          if (_text(meta?.documentReferences).isNotEmpty)
            _labelledText('Document References', _text(meta?.documentReferences)),
          if (log.photoPaths.isEmpty)
            _empty('No site photographs attached.')
          else ...[
            pw.SizedBox(height: 5),
            _photoGrid(log.photoPaths),
          ],
          pw.SizedBox(height: 12),

          _section('10. SIGN-OFF'),
          _signOff(meta),
          pw.SizedBox(height: 6),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final reportDir = Directory(p.join(dir.path, 'reports'));
    await reportDir.create(recursive: true);
    final safeSite = site.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File(
      p.join(
        reportDir.path,
        '${safeSite}_Daily_Site_Report_${DateFormat('yyyy-MM-dd').format(log.date)}.pdf',
      ),
    );
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  static String _text(String? value) => value?.trim() ?? '';

  static String _fallback(String? value, String fallback) {
    final text = _text(value);
    return text.isEmpty ? fallback : text;
  }

  static String _progressQuantity(DailySiteReportMeta? meta) {
    final quantity = _text(meta?.progressQuantity);
    final unit = _text(meta?.progressUnit);
    if (quantity.isEmpty) return 'Not recorded';
    return unit.isEmpty ? quantity : '$quantity $unit';
  }

  static String _number(double value) {
    if ((value - value.roundToDouble()).abs() < 0.0001) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  static pw.Widget _header(String companyName, String reportNo) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 7),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 1.4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
              pw.Text(
                'Construction Site Management',
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.Text(
            reportNo,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy),
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.blueGrey200, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Civil Site Manager • Generated from field records', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  static pw.Widget _title(String text) => pw.Center(
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
            letterSpacing: 0.4,
          ),
        ),
      );

  static pw.Widget _section(String title) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        margin: const pw.EdgeInsets.only(bottom: 6),
        decoration: pw.BoxDecoration(
          color: _navy,
          borderRadius: pw.BorderRadius.circular(2),
        ),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 9.5,
          ),
        ),
      );

  static pw.Widget _empty(String message) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: _border, width: 0.5),
        ),
        child: pw.Text(message, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
      );

  static pw.Widget _textBlock(String text) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _border, width: 0.5),
        ),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 2)),
      );

  static pw.Widget _labelledText(String label, String text) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 5),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _border, width: 0.5)),
        child: pw.RichText(
          text: pw.TextSpan(
            style: const pw.TextStyle(fontSize: 8.5),
            children: [
              pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _navy)),
              pw.TextSpan(text: text),
            ],
          ),
        ),
      );

  static pw.Widget _infoGrid(List<List<String>> items, {int columns = 2}) {
    final rows = <pw.TableRow>[];
    for (var i = 0; i < items.length; i += columns) {
      final cells = <pw.Widget>[];
      for (var j = 0; j < columns; j++) {
        if (i + j < items.length) {
          final item = items[i + j];
          cells.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(item[0], style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _navy)),
                  pw.SizedBox(height: 2),
                  pw.Text(item[1], style: const pw.TextStyle(fontSize: 8.2)),
                ],
              ),
            ),
          );
        } else {
          cells.add(pw.SizedBox());
        }
      }
      rows.add(pw.TableRow(children: cells));
    }
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.45),
      children: rows,
    );
  }

  static pw.Widget _table(
    List<String> headers,
    List<List<String>> rows, {
    List<double>? widths,
  }) {
    final columnWidths = <int, pw.TableColumnWidth>{};
    if (widths != null) {
      for (var i = 0; i < widths.length; i++) {
        columnWidths[i] = pw.FlexColumnWidth(widths[i]);
      }
    }
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.45),
      columnWidths: columnWidths,
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _paleBlue),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(h, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _navy)),
                  ))
              .toList(),
        ),
        ...rows.map(
          (row) => pw.TableRow(
            children: row
                .map((cell) => pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(cell, style: const pw.TextStyle(fontSize: 7.5)),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  static pw.Widget _moneyBar(String label, double amount) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        color: _navy,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Text(CurrencyFormatter.format(amount), style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  static pw.Widget _photoGrid(List<String> paths) {
    final widgets = <pw.Widget>[];
    for (var i = 0; i < paths.length; i++) {
      final file = File(paths[i]);
      if (!file.existsSync()) continue;
      widgets.add(
        pw.Container(
          width: 160,
          padding: const pw.EdgeInsets.all(3),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _border, width: 0.5)),
          child: pw.Column(
            children: [
              pw.Image(
                pw.MemoryImage(file.readAsBytesSync()),
                width: 152,
                height: 105,
                fit: pw.BoxFit.cover,
              ),
              pw.SizedBox(height: 2),
              pw.Text('Photo ${i + 1}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            ],
          ),
        ),
      );
    }
    if (widgets.isEmpty) return _empty('Photo files are no longer available on this device.');
    return pw.Wrap(spacing: 8, runSpacing: 8, children: widgets);
  }

  static pw.Widget _signOff(DailySiteReportMeta? meta) {
    final signers = [
      ['Prepared by', _fallback(meta?.preparedBy, '________________________'), _fallback(meta?.preparedByPosition, 'Site/Design Engineer')],
      ['Reviewed by', _fallback(meta?.reviewedBy, '________________________'), 'Project / Site Manager'],
      ['Approved / Noted by', _fallback(meta?.approvedBy, '________________________'), 'Authorised Representative'],
    ];
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: signers.map((s) {
        return pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 5),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _border, width: 0.5)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(s[0], style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _navy)),
                pw.SizedBox(height: 16),
                pw.Text(s[1], style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 3),
                pw.Text(s[2], style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                pw.SizedBox(height: 10),
                pw.Text('Signature / Date: ____________________', style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
