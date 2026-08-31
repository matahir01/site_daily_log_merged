import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/attendance.dart';
import '../models/material_stock_log.dart';
import '../models/equipment_dipping_log.dart';
import '../models/worker.dart';
import '../utils/currency_formatter.dart';

/// On-device PDF report generation for sites, projects, and individual
/// daily logs.
class PdfReportService {
  static String _categoryLabel(ExpenseCategory c) {
    return c.label;
  }

  static Future<File> generateSiteReport({
    required Project project,
    required Site site,
    required List<DailyLog> logs,
    required List<Expense> expenses,
  }) async {
    final doc = pw.Document();
    final dateFmt = DateFormat.yMMMd();
    final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header(project.name, site.name, site.address),
          pw.SizedBox(height: 20),
          pw.Text(
            'Daily Logs',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Divider(),
          if (logs.isEmpty) pw.Text('No daily logs recorded.'),
          ...logs.map((log) => _logBlock(log, dateFmt)),
          pw.SizedBox(height: 20),
          pw.Text(
            'Expenses',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Divider(),
          if (expenses.isEmpty) pw.Text('No expenses recorded.'),
          if (expenses.isNotEmpty) _expenseTable(expenses, dateFmt),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total: ${CurrencyFormatter.format(total)}',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    return _saveDoc(doc, '${site.name}_report');
  }

  static Future<File> generateProjectReport({
    required Project project,
    required List<Site> sites,
    required Map<String, List<DailyLog>> logsBySite,
    required Map<String, List<Expense>> expensesBySite,
  }) async {
    final doc = pw.Document();
    final dateFmt = DateFormat.yMMMd();

    double projectTotal = 0;
    for (final e in expensesBySite.values.expand((x) => x)) {
      projectTotal += e.amount;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header(project.name, project.client ?? 'Project Report', null),
          pw.SizedBox(height: 8),
          pw.Text(
            'Total Project Expenses: ${CurrencyFormatter.format(projectTotal)}',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 20),
          for (final site in sites) ...[
            pw.Text(
              site.name,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (site.address != null)
              pw.Text(site.address!, style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(),
            pw.Text(
              'Daily Logs',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            ...(logsBySite[site.id] ?? []).map((log) => _logBlock(log, dateFmt)),
            pw.SizedBox(height: 8),
            pw.Text(
              'Expenses',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            if ((expensesBySite[site.id] ?? []).isNotEmpty)
              _expenseTable(expensesBySite[site.id]!, dateFmt)
            else
              pw.Text('No expenses recorded.'),
            pw.SizedBox(height: 20),
          ],
        ],
      ),
    );

    return _saveDoc(doc, '${project.name}_full_report');
  }

  /// Generates a single daily-log "executive report" with navy/steel-blue
  /// styling, including work activities, attendance, materials, equipment,
  /// expenses, and a cash-flow summary.
  static Future<File> generateDailyLogReport({
    required Site site,
    required DailyLog log,
    required List<Attendance> attendance,
    required List<Worker> workers,
    required List<MaterialStockLog> materials,
    required List<EquipmentDippingLog> equipment,
    required List<Expense> expenses,
  }) async {
    final pdf = pw.Document();
    final navy = PdfColor.fromHex('#1A365D');
    final steelBlue = PdfColor.fromHex('#2B6CB0');
    final iceBlue = PdfColor.fromHex('#EBF8FF');
    final slateBorder = PdfColors.blueGrey200;
    final emerald = PdfColor.fromHex('#059669');
    final crimson = PdfColor.fromHex('#DC2626');

    final totalExpenses = expenses.fold<double>(0.0, (s, e) => s + e.amount);
    final dateStr = DateFormat.yMMMd().format(log.date);
    final workText = log.workCompleted ?? '';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildDailyHeader(
          navy,
          site.name,
          site.address ?? 'N/A',
          dateStr,
          log.id,
        ),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _sectionTitle('1. WORK ACTIVITIES EXECUTED', steelBlue),
          pw.SizedBox(height: 8),
          if (workText.isEmpty)
            _emptyCard('No work activities recorded')
          else
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: slateBorder),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: workText.split('\n').map((line) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '• ',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Expanded(child: pw.Text(line.trim())),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          pw.SizedBox(height: 20),
          _sectionTitle('2. MATERIAL STOCK RECONCILIATION', steelBlue),
          pw.SizedBox(height: 8),
          if (materials.isEmpty)
            _emptyCard('No material stock records')
          else
            _buildTable(
              headers: ['Item', 'Unit', 'Opening', 'Received', 'Issued', 'Closing'],
              rows: materials.map((m) => [
                m.itemName,
                m.unit,
                m.openingBalance.toStringAsFixed(1),
                m.received.toStringAsFixed(1),
                m.issued.toStringAsFixed(1),
                m.closingBalance.toStringAsFixed(1),
              ]).toList(),
              navy: navy,
              iceBlue: iceBlue,
              slateBorder: slateBorder,
            ),
          pw.SizedBox(height: 20),
          _sectionTitle('3. EQUIPMENT DIPPING & FUEL LOG', steelBlue),
          pw.SizedBox(height: 8),
          if (equipment.isEmpty)
            _emptyCard('No equipment dipping records')
          else
            _buildTable(
              headers: [
                'Equipment',
                'Open Dip (cm)',
                'Close Dip (cm)',
                'Diesel (L)',
                'Engine Oil (L)',
              ],
              rows: equipment.map((e) => [
                e.equipmentName,
                e.openingDipCm?.toStringAsFixed(1) ?? '-',
                e.closingDipCm?.toStringAsFixed(1) ?? '-',
                e.dieselIssuedLitres.toStringAsFixed(1),
                e.engineOilIssuedLitres.toStringAsFixed(1),
              ]).toList(),
              navy: navy,
              iceBlue: iceBlue,
              slateBorder: slateBorder,
            ),
          pw.SizedBox(height: 20),
          _sectionTitle('4. DAILY ITEMIZED EXPENSES LEDGER', steelBlue),
          pw.SizedBox(height: 8),
          if (expenses.isEmpty)
            _emptyCard('No expenses recorded')
          else
            pw.Column(
              children: [
                _buildTable(
                  headers: [
                    'S/N',
                    'Description',
                    'Category',
                    'Unit',
                    'Unit Price',
                    'Total',
                  ],
                  rows: expenses.map((e) => [
                    '${e.serialNo ?? 0}',
                    e.displayDescription,
                    e.category.label,
                    e.unit ?? '-',
                    CurrencyFormatter.format(e.unitPrice ?? e.amount),
                    CurrencyFormatter.format(e.amount),
                  ]).toList(),
                  navy: navy,
                  iceBlue: iceBlue,
                  slateBorder: slateBorder,
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: navy,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'SUB-TOTAL',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        CurrencyFormatter.format(totalExpenses),
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          pw.SizedBox(height: 20),
          _sectionTitle('5. CASH FLOW & FLOAT SUMMARY', steelBlue),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: iceBlue,
              border: pw.Border.all(color: slateBorder),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              children: [
                _summaryRow(
                  'Total Daily Expenses:',
                  CurrencyFormatter.format(totalExpenses),
                ),
                pw.Divider(color: slateBorder),
                _summaryRow(
                  'Net Cash Position:',
                  CurrencyFormatter.format(-totalExpenses),
                  valueColor: totalExpenses > 0 ? crimson : emerald,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 30),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Prepared By:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 24),
                    pw.Container(
                      width: 150,
                      height: 1,
                      color: PdfColors.black,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Site Supervisor Signature',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Verified By:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 24),
                    pw.Container(
                      width: 150,
                      height: 1,
                      color: PdfColors.black,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Project Manager Signature',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return _saveDoc(pdf, '${site.name}_daily_${log.id.substring(0, 8)}');
  }

  static pw.Widget _header(String title, String subtitle, String? extra) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 14)),
        if (extra != null)
          pw.Text(extra, style: const pw.TextStyle(fontSize: 10)),
        pw.Text(
          'Generated: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey600,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildDailyHeader(
    PdfColor navy,
    String siteName,
    String location,
    String date,
    String logId,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(color: navy),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'SITE DAILY REPORT',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            siteName,
            style: pw.TextStyle(color: PdfColors.white, fontSize: 14),
          ),
          pw.Text(
            location,
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 12),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Date: $date',
                style: const pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                ),
              ),
              pw.Text(
                'Ref: SDL-${logId.substring(0, 8)}',
                style: const pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount} • Generated ${DateTime.now().toIso8601String()}',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
      ),
    );
  }

  static pw.Widget _sectionTitle(String text, PdfColor color) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  static pw.Widget _emptyCard(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
      child: pw.Text(text, style: const pw.TextStyle(color: PdfColors.grey)),
    );
  }

  static pw.Widget _buildTable({
    required List<String> headers,
    required List<List<String>> rows,
    required PdfColor navy,
    required PdfColor iceBlue,
    required PdfColor slateBorder,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: slateBorder, width: 0.5),
      columnWidths: {0: const pw.FlexColumnWidth(2)},
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: navy),
          children: headers.map((h) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                h,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            );
          }).toList(),
        ),
        ...rows.asMap().entries.map((entry) {
          final isEven = entry.key % 2 == 0;
          return pw.TableRow(
            decoration: isEven ? null : pw.BoxDecoration(color: iceBlue),
            children: entry.value.map((cell) {
              return pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(cell, style: const pw.TextStyle(fontSize: 10)),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  static pw.Widget _summaryRow(String label, String value, {PdfColor? valueColor}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  static pw.Widget _logBlock(DailyLog log, DateFormat dateFmt) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            dateFmt.format(log.date),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (log.weather != null) pw.Text('Weather: ${log.weather}'),
          if (log.crewCount != null) pw.Text('Crew: ${log.crewCount}'),
          if (log.workCompleted != null)
            pw.Text('Work completed: ${log.workCompleted}'),
          if (log.issues != null) pw.Text('Issues: ${log.issues}'),
          if (log.photoPaths.isNotEmpty)
            pw.Wrap(
              spacing: 6,
              runSpacing: 6,
              children: log.photoPaths.map((path) {
                final file = File(path);
                if (!file.existsSync()) return pw.SizedBox();
                return pw.Image(
                  pw.MemoryImage(file.readAsBytesSync()),
                  width: 100,
                  height: 100,
                  fit: pw.BoxFit.cover,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  static pw.Widget _expenseTable(List<Expense> expenses, DateFormat dateFmt) {
    return pw.TableHelper.fromTextArray(
      headers: ['Date', 'Category', 'Amount', 'Note'],
      data: expenses
          .map((e) => [
                dateFmt.format(e.date),
                _categoryLabel(e.category),
                CurrencyFormatter.format(e.amount),
                e.note ?? '',
              ])
          .toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 10,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  static Future<File> _saveDoc(pw.Document doc, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(p.join(dir.path, 'reports'));
    await reportsDir.create(recursive: true);
    final safeName = baseName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(reportsDir.path, '${safeName}_$timestamp.pdf'));
    await file.writeAsBytes(await doc.save());
    return file;
  }
}
