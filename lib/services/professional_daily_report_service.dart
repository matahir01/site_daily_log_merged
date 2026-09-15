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
import '../models/equipment_dipping_log.dart';
import '../models/expense.dart';
import '../models/material_stock_log.dart';
import '../models/site.dart';
import '../models/worker.dart';
import '../utils/currency_formatter.dart';

class ProfessionalDailyReportService {
  static final _navy = PdfColor.fromHex('#17365D');
  static final _blue = PdfColor.fromHex('#2B6CB0');
  static final _pale = PdfColor.fromHex('#EDF5FC');
  static final _border = PdfColors.blueGrey200;

  static Future<File> generate({
    required Site site,
    required DailyLog log,
    required DailySiteReportMeta? meta,
    required List<Attendance> attendance,
    required List<Worker> workers,
    required List<MaterialStockLog> materials,
    required List<EquipmentDippingLog> equipment,
    required List<ConcretePour> concretePours,
    required List<Expense> expenses,
    required CashFloat? cashFloat,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
    final totalExpenses = expenses.fold<double>(0, (s, e) => s + e.amount);
    final presentIds = attendance.where((a) => a.status == AttendanceStatus.present || a.status == AttendanceStatus.halfDay).map((a) => a.workerId).toSet();
    final workerMap = {for (final w in workers) w.id: w};

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
      header: (_) => _header(site, log, meta),
      footer: (c) => pw.Container(alignment: pw.Alignment.centerRight, child: pw.Text('SWAS GRADE LIMITED  •  Confidential  •  Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
      build: (_) => [
        _section('1. WORK ACTIVITIES & PROGRESS'),
        _infoGrid([
          ['Weather', log.weather ?? 'Not recorded'], ['Shift', meta?.shift ?? 'Day'],
          ['Crew Count', '${log.crewCount ?? presentIds.length}'], ['Report No.', meta?.reportNo ?? 'SDL-${log.id.substring(0, 8)}'],
        ]),
        _textCard('Work executed', log.workCompleted),
        if (meta?.progressQuantity != null || meta?.percentComplete != null)
          _infoGrid([
            ['Measured quantity', meta?.progressQuantity == null ? '-' : '${meta!.progressQuantity!.toStringAsFixed(2)} ${meta.progressUnit ?? ''}'],
            ['Overall progress', meta?.percentComplete == null ? '-' : '${meta!.percentComplete!.toStringAsFixed(1)}%'],
          ]),
        _gap(), _section('2. LABOUR / MANPOWER'),
        if (attendance.isEmpty) _empty('No attendance records linked to this daily log.') else _table(
          ['Name', 'Role', 'Status'],
          attendance.map((a) => [workerMap[a.workerId]?.name ?? 'Unknown', workerMap[a.workerId]?.role ?? '-', a.status.label]).toList(),
          widths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1.5), 2: const pw.FlexColumnWidth(1)},
        ),
        _gap(), _section('3. MATERIAL STOCK / CONSUMPTION'),
        if (materials.isEmpty) _empty('No material stock records.') else _table(
          ['Item', 'Unit', 'Opening', 'Received', 'Issued', 'Closing'],
          materials.map((m) => [m.itemName, m.unit, _n(m.openingBalance), _n(m.received), _n(m.issued), _n(m.closingBalance)]).toList(),
        ),
        _gap(), _section('4. FUEL, LUBRICANT & EQUIPMENT UTILISATION'),
        if (equipment.isEmpty) _empty('No equipment records.') else _table(
          ['Equipment', 'Open dip', 'Diesel L', 'Oil L', 'Close dip'],
          equipment.map((e) => [e.equipmentName, e.openingDipCm?.toStringAsFixed(1) ?? '-', _n(e.dieselIssuedLitres), _n(e.engineOilIssuedLitres), e.closingDipCm?.toStringAsFixed(1) ?? '-']).toList(),
        ),
        _gap(), _section('5. QUALITY CONTROL / INSPECTIONS'),
        _textCard('Inspection / quality notes', meta?.qualityInspections),
        if (concretePours.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _table(['Element', 'Grade', 'Volume m³', 'Slump mm', 'Cubes', 'Ticket'], concretePours.map((c) => [c.elementName, c.concreteGrade, c.volumeM3.toStringAsFixed(2), c.slumpMm?.toStringAsFixed(0) ?? '-', '${c.cubesCast}', c.batchTicketNo ?? '-']).toList()),
        ],
        _gap(), _section('6. HEALTH, SAFETY & ENVIRONMENT'),
        _textCard('HSE observations / toolbox / incidents', meta?.hseObservations),
        _gap(), _section('7. SITE EXPENSES & FLOAT RECONCILIATION'),
        if (expenses.isEmpty) _empty('No expenses recorded for this date.') else ...[
          _table(['S/N', 'Description', 'Category', 'Unit', 'Amount'], expenses.map((e) => ['${e.serialNo ?? '-'}', e.displayDescription, e.category.label, e.unit ?? '-', CurrencyFormatter.format(e.amount)]).toList(), widths: {0: const pw.FixedColumnWidth(28), 1: const pw.FlexColumnWidth(2.7), 2: const pw.FlexColumnWidth(1.4), 3: const pw.FixedColumnWidth(42), 4: const pw.FlexColumnWidth(1.3)}),
          _total('TOTAL EXPENSES', totalExpenses),
        ],
        if (cashFloat != null) ...[
          pw.SizedBox(height: 8),
          _infoGrid([
            ['Opening balance', CurrencyFormatter.format(cashFloat.openingBalance)], ['Float received', CurrencyFormatter.format(cashFloat.floatReceived)],
            ['Expected closing', CurrencyFormatter.format(cashFloat.expectedClosingBalance)], ['Reported closing', CurrencyFormatter.format(cashFloat.reportedClosingBalance)],
            ['Variance', CurrencyFormatter.format(cashFloat.variance)], ['Status', cashFloat.status.label],
          ]),
        ],
        _gap(), _section('8. DELAYS, ISSUES, INSTRUCTIONS & NEXT-DAY PLAN'),
        _textCard('Delays / issues', log.issues),
        pw.SizedBox(height: 6), _textCard('Site instructions / decisions', meta?.siteInstructions),
        pw.SizedBox(height: 6), _textCard('Next-day plan', meta?.nextDayPlan),
        _gap(), _section('9. PHOTO / DOCUMENT REFERENCES'),
        _textCard('Drawing / RFI / document references', meta?.documentReferences),
        pw.SizedBox(height: 8),
        if (log.photoPaths.isEmpty) _empty('No site photographs captured.') else pw.Wrap(spacing: 8, runSpacing: 8, children: log.photoPaths.map((path) {
          final f = File(path); if (!f.existsSync()) return pw.SizedBox();
          return pw.Container(width: 155, height: 115, decoration: pw.BoxDecoration(border: pw.Border.all(color: _border)), child: pw.Image(pw.MemoryImage(f.readAsBytesSync()), fit: pw.BoxFit.cover));
        }).toList()),
        _gap(), _section('10. SIGN-OFF'),
        pw.SizedBox(height: 20),
        pw.Row(children: [_signature('Prepared by', 'Site / Design Engineer'), pw.SizedBox(width: 20), _signature('Reviewed by', 'Project / Site Manager'), pw.SizedBox(width: 20), _signature('Approved / Noted by', 'Authorised Officer')]),
      ],
    ));

    final dir = await getApplicationDocumentsDirectory();
    final reports = Directory(p.join(dir.path, 'reports')); await reports.create(recursive: true);
    final safe = site.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File(p.join(reports.path, '${safe}_Daily_Report_${DateFormat('yyyyMMdd').format(log.date)}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  static String _n(double v) => v.toStringAsFixed(1);
  static pw.Widget _gap() => pw.SizedBox(height: 16);
  static pw.Widget _section(String t) => pw.Container(width: double.infinity, padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8), color: _navy, child: pw.Text(t, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)));
  static pw.Widget _empty(String t) => pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: _border)), child: pw.Text(t, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)));
  static pw.Widget _textCard(String label, String? value) => pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(border: pw.Border.all(color: _border)), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _blue, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 4), pw.Text((value == null || value.trim().isEmpty) ? 'Not recorded' : value, style: const pw.TextStyle(fontSize: 9))]));
  static pw.Widget _infoGrid(List<List<String>> rows) => pw.Table(border: pw.TableBorder.all(color: _border, width: .5), children: rows.map((r) => pw.TableRow(children: [for (final x in r) pw.Container(padding: const pw.EdgeInsets.all(7), color: r.indexOf(x).isEven ? _pale : PdfColors.white, child: pw.Text(x, style: const pw.TextStyle(fontSize: 8.5)))])).toList());
  static pw.Widget _table(List<String> headers, List<List<String>> rows, {Map<int, pw.TableColumnWidth>? widths}) => pw.TableHelper.fromTextArray(headers: headers, data: rows, columnWidths: widths, headerDecoration: pw.BoxDecoration(color: _blue), headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8), cellStyle: const pw.TextStyle(fontSize: 7.5), cellPadding: const pw.EdgeInsets.all(5), border: pw.TableBorder.all(color: _border, width: .5), oddRowDecoration: pw.BoxDecoration(color: _pale));
  static pw.Widget _total(String label, double amount) => pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(8), color: _navy, child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(label, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold)), pw.Text(CurrencyFormatter.format(amount), style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold))]));
  static pw.Widget _signature(String a, String b) => pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(a, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 28), pw.Container(height: .7, color: PdfColors.black), pw.SizedBox(height: 3), pw.Text(b, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)), pw.Text('Name / Signature / Date', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600))]));
  static pw.Widget _header(Site site, DailyLog log, DailySiteReportMeta? meta) => pw.Container(margin: const pw.EdgeInsets.only(bottom: 12), child: pw.Column(children: [pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(12), color: _navy, child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('SWAS GRADE LIMITED', style: pw.TextStyle(color: PdfColors.white, fontSize: 15, fontWeight: pw.FontWeight.bold)), pw.Text('DAILY SITE PROGRESS REPORT', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10))]), pw.Text('CONFIDENTIAL', style: const pw.TextStyle(color: PdfColors.white, fontSize: 8))])), pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(border: pw.Border.all(color: _border)), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Project / Site: ${site.name}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)), pw.Text('Date: ${DateFormat.yMMMd().format(log.date)}', style: const pw.TextStyle(fontSize: 9)), pw.Text('Ref: ${meta?.reportNo ?? 'SDL-${log.id.substring(0, 8)}'}', style: const pw.TextStyle(fontSize: 9))]))]));
}
