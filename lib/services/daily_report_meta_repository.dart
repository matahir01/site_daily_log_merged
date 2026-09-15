import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import '../models/daily_site_report_meta.dart';

class DailyReportMetaRepository {
  static Future<void> _ensureTable() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_site_report_meta (
        daily_log_id TEXT PRIMARY KEY,
        report_no TEXT,
        shift TEXT,
        progress_quantity REAL,
        progress_unit TEXT,
        percent_complete REAL,
        quality_inspections TEXT,
        hse_observations TEXT,
        site_instructions TEXT,
        next_day_plan TEXT,
        document_references TEXT,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> save(DailySiteReportMeta meta) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    await db.insert('daily_site_report_meta', meta.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<DailySiteReportMeta?> getForLog(String logId) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('daily_site_report_meta', where: 'daily_log_id = ?', whereArgs: [logId], limit: 1);
    return rows.isEmpty ? null : DailySiteReportMeta.fromMap(rows.first);
  }
}
