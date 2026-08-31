import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../db/database_helper.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';
import '../models/cash_float.dart';

class ExcelExportService {
  static final _dateFmt = DateFormat.yMMMd();

  static Future<File> generateProjectWorkbook({
    required Project project,
    required List<Site> sites,
    required Map<String, List<DailyLog>> logsBySite,
    required Map<String, List<MaterialItem>> materialsBySite,
    required Map<String, List<Expense>> expensesBySite,
  }) async {
    final excel = Excel.createExcel();
    final siteNameById = {for (final s in sites) s.id: s.name};

    _buildLogsSheet(excel, sites, logsBySite, siteNameById, includeSiteColumn: true);
    _buildMaterialsSheet(excel, sites, materialsBySite, siteNameById, includeSiteColumn: true);
    _buildExpensesSheet(excel, sites, expensesBySite, siteNameById, includeSiteColumn: true);
    await _buildMonthlySummarySheet(excel, sites, expensesBySite, siteNameById);
    await _buildOverallSummarySheet(excel, sites, expensesBySite, siteNameById);
    await _buildCashFlowSheet(excel, sites);

    if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
      excel.delete('Sheet1');
    }

    return _save(excel, '${project.name}_export');
  }

  static Future<File> generateSiteWorkbook({
    required Project project,
    required Site site,
    required List<DailyLog> logs,
    required List<MaterialItem> materials,
    required List<Expense> expenses,
  }) async {
    final excel = Excel.createExcel();
    final siteNameById = {site.id: site.name};

    _buildLogsSheet(excel, [site], {site.id: logs}, siteNameById, includeSiteColumn: false);
    _buildMaterialsSheet(excel, [site], {site.id: materials}, siteNameById, includeSiteColumn: false);
    _buildExpensesSheet(excel, [site], {site.id: expenses}, siteNameById, includeSiteColumn: false);
    await _buildMonthlySummarySheet(excel, [site], {site.id: expenses}, siteNameById);
    await _buildOverallSummarySheet(excel, [site], {site.id: expenses}, siteNameById);
    await _buildCashFlowSheet(excel, [site]);

    if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
      excel.delete('Sheet1');
    }

    return _save(excel, '${site.name}_export');
  }

  static void _buildLogsSheet(
    Excel excel,
    List<Site> sites,
    Map<String, List<DailyLog>> logsBySite,
    Map<String, String> siteNameById, {
    required bool includeSiteColumn,
  }) {
    final sheet = excel['Daily Logs'];
    final headers = [
      if (includeSiteColumn) 'Site',
      'Date',
      'Weather',
      'Crew Count',
      'Work Completed',
      'Issues / Delays',
      'Latitude',
      'Longitude',
      'Photos',
      'Synced',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final site in sites) {
      final logs = logsBySite[site.id] ?? [];
      for (final log in logs) {
        sheet.appendRow([
          if (includeSiteColumn) TextCellValue(siteNameById[site.id] ?? site.id),
          TextCellValue(_dateFmt.format(log.date)),
          TextCellValue(log.weather ?? ''),
          if (log.crewCount != null) IntCellValue(log.crewCount!) else TextCellValue(''),
          TextCellValue(log.workCompleted ?? ''),
          TextCellValue(log.issues ?? ''),
          if (log.latitude != null) DoubleCellValue(log.latitude!) else TextCellValue(''),
          if (log.longitude != null) DoubleCellValue(log.longitude!) else TextCellValue(''),
          IntCellValue(log.photoPaths.length),
          TextCellValue(log.isSynced ? 'Synced' : 'Pending Sync'),
        ]);
      }
    }
    _autoWidth(sheet, headers.length);
  }

  static void _buildMaterialsSheet(
    Excel excel,
    List<Site> sites,
    Map<String, List<MaterialItem>> materialsBySite,
    Map<String, String> siteNameById, {
    required bool includeSiteColumn,
  }) {
    final sheet = excel['Materials & Equipment'];
    final headers = [
      if (includeSiteColumn) 'Site',
      'Item',
      'Quantity',
      'Unit',
      'Category',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final site in sites) {
      final items = materialsBySite[site.id] ?? [];
      for (final item in items) {
        sheet.appendRow([
          if (includeSiteColumn) TextCellValue(siteNameById[site.id] ?? site.id),
          TextCellValue(item.itemName),
          DoubleCellValue(item.quantity),
          TextCellValue(item.unit ?? ''),
          TextCellValue(item.category.label),
        ]);
      }
    }
    _autoWidth(sheet, headers.length);
  }

  static void _buildExpensesSheet(
    Excel excel,
    List<Site> sites,
    Map<String, List<Expense>> expensesBySite,
    Map<String, String> siteNameById, {
    required bool includeSiteColumn,
  }) {
    final sheet = excel['Expenses'];
    final headers = [
      if (includeSiteColumn) 'Site',
      'Date',
      'Category',
      'S/N',
      'Description',
      'Unit',
      'Unit Price',
      'Amount',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    double total = 0;
    for (final site in sites) {
      final expenses = expensesBySite[site.id] ?? [];
      for (final e in expenses) {
        total += e.amount;
        sheet.appendRow([
          if (includeSiteColumn) TextCellValue(siteNameById[site.id] ?? site.id),
          TextCellValue(_dateFmt.format(e.date)),
          TextCellValue(e.category.label),
          if (e.serialNo != null) IntCellValue(e.serialNo!) else TextCellValue(''),
          TextCellValue(e.displayDescription),
          TextCellValue(e.unit ?? ''),
          if (e.unitPrice != null) DoubleCellValue(e.unitPrice!) else TextCellValue(''),
          DoubleCellValue(e.amount),
        ]);
      }
    }
    sheet.appendRow([]);
    final totalRow = [
      if (includeSiteColumn) TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Total'),
      DoubleCellValue(total),
    ];
    sheet.appendRow(totalRow);
    _autoWidth(sheet, headers.length);
  }

  static Future<void> _buildMonthlySummarySheet(
    Excel excel,
    List<Site> sites,
    Map<String, List<Expense>> expensesBySite,
    Map<String, String> siteNameById,
  ) async {
    final sheet = excel['Monthly Summary'];
    final db = DatabaseHelper.instance;

    final allExpenses = expensesBySite.values.expand((x) => x).toList();
    final months = allExpenses.map((e) => e.monthKey).toSet().toList()..sort();

    final headers = ['Category', ...months, 'Total'];
    _writeHeader(sheet, headers);

    int rowIdx = 1;
    for (final cat in ExpenseCategory.values) {
      final row = <dynamic>[cat.label];
      double catTotal = 0;
      for (final month in months) {
        double sum = 0;
        for (final site in sites) {
          final siteExp = await db.getExpensesByMonth(site.id, month);
          sum += siteExp.where((e) => e.category == cat).fold<double>(0.0, (s, e) => s + e.amount);
        }
        row.add(sum);
        catTotal += sum;
      }
      row.add(catTotal);
      _writeRow(sheet, rowIdx++, row);
    }
    _autoWidth(sheet, headers.length);
  }

  static Future<void> _buildOverallSummarySheet(
    Excel excel,
    List<Site> sites,
    Map<String, List<Expense>> expensesBySite,
    Map<String, String> siteNameById,
  ) async {
    final sheet = excel['Overall Summary'];
    final db = DatabaseHelper.instance;

    final allExpenses = expensesBySite.values.expand((x) => x).toList();
    final totals = <String, double>{};
    for (final site in sites) {
      final siteTotals = await db.getExpenseTotalsByCategory(site.id);
      siteTotals.forEach((k, v) => totals[k] = (totals[k] ?? 0.0) + v);
    }
    final grandTotal = totals.values.fold<double>(0.0, (s, v) => s + v);

    _writeHeader(sheet, ['Category', 'Item Count', 'Total Spend', '% Share']);
    int rowIdx = 1;
    for (final cat in ExpenseCategory.values) {
      final total = totals[cat.name] ?? 0.0;
      final count = allExpenses.where((e) => e.category == cat).length;
      final pct = grandTotal > 0 ? (total / grandTotal * 100).toStringAsFixed(1) : '0.0';
      _writeRow(sheet, rowIdx++, [cat.label, count, total, '$pct%']);
    }
    _writeRow(sheet, rowIdx, ['GRAND TOTAL', allExpenses.length, grandTotal, '100.0%'], isBold: true);
    _autoWidth(sheet, 4);
  }

  static Future<void> _buildCashFlowSheet(Excel excel, List<Site> sites) async {
    final sheet = excel['Cash Flow'];
    final db = DatabaseHelper.instance;

    _writeHeader(sheet, ['Date', 'Opening', 'Float Received', 'Total Expenses', 'Expected Close', 'Reported Close', 'Variance', 'Status']);
    int rowIdx = 1;
    for (final site in sites) {
      final floats = await db.getCashFloatsForSite(site.id);
      for (final c in floats) {
        _writeRow(sheet, rowIdx++, [
          c.date.toIso8601String().split('T').first,
          c.openingBalance,
          c.floatReceived,
          c.totalExpenses,
          c.expectedClosingBalance,
          c.reportedClosingBalance,
          c.variance,
          c.status.label,
        ]);
      }
    }
    _autoWidth(sheet, 8);
  }

  static void _writeHeader(Sheet sheet, List<dynamic> headers) {
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i].toString());
      cell.cellStyle = CellStyle(
        bold: true,
      );
    }
  }

  static void _writeRow(Sheet sheet, int rowIndex, List<dynamic> values, {bool isBold = false}) {
    for (int i = 0; i < values.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex));
      final val = values[i];
      if (val is String) {
        cell.value = TextCellValue(val);
      } else if (val is int) {
        cell.value = IntCellValue(val);
      } else if (val is double) {
        cell.value = DoubleCellValue(val);
      }
      if (isBold) {
        cell.cellStyle = CellStyle(bold: true);
      }
    }
  }

  static void _autoWidth(Sheet sheet, int columnCount) {
    for (var i = 0; i < columnCount; i++) {
      sheet.setColumnWidth(i, 22);
    }
  }

  static Future<File> _save(Excel excel, String baseName) async {
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
