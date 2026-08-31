import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';
import '../models/worker.dart';
import '../models/attendance.dart';
import '../models/material_stock_log.dart';
import '../models/equipment_dipping_log.dart';
import '../models/cash_float.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _db;

  static const int _dbVersion = 3;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<String> getDbPath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'site_daily_log.db');
  }

  Future<void> closeForRestore() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<Database> _initDb() async {
    final path = await getDbPath();
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        client TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sites (
        id TEXT PRIMARY KEY,
        projectId TEXT NOT NULL,
        name TEXT NOT NULL,
        address TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE daily_logs (
        id TEXT PRIMARY KEY,
        siteId TEXT NOT NULL,
        date TEXT NOT NULL,
        weather TEXT,
        crewCount INTEGER,
        workCompleted TEXT,
        issues TEXT,
        photoPaths TEXT,
        lat REAL,
        lng REAL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (siteId) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        siteId TEXT NOT NULL,
        date TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        receiptPhotoPath TEXT,
        serial_no INTEGER,
        description TEXT,
        unit TEXT,
        unit_price REAL,
        total_amount REAL,
        month TEXT,
        FOREIGN KEY (siteId) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE materials_and_equipment (
        id TEXT PRIMARY KEY,
        log_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT,
        category TEXT NOT NULL DEFAULT 'material',
        FOREIGN KEY (log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
    await _createV3Tables(db);
  }

  Future<void> _createV3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workers (
        id TEXT PRIMARY KEY,
        site_id TEXT NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_attendance (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        worker_id TEXT NOT NULL,
        status TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE,
        FOREIGN KEY (worker_id) REFERENCES workers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS material_stock_logs (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        received REAL NOT NULL DEFAULT 0.0,
        issued REAL NOT NULL DEFAULT 0.0,
        closing_balance REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS equipment_dipping_logs (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        equipment_name TEXT NOT NULL,
        opening_dip_cm REAL,
        closing_dip_cm REAL,
        diesel_issued_litres REAL NOT NULL DEFAULT 0.0,
        engine_oil_issued_litres REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_floats (
        id TEXT PRIMARY KEY,
        site_id TEXT NOT NULL,
        date TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        float_received REAL NOT NULL DEFAULT 0.0,
        total_expenses REAL NOT NULL DEFAULT 0.0,
        expected_closing_balance REAL NOT NULL DEFAULT 0.0,
        reported_closing_balance REAL NOT NULL DEFAULT 0.0,
        variance REAL NOT NULL DEFAULT 0.0,
        status TEXT NOT NULL DEFAULT 'OK',
        notes TEXT,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE daily_logs ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS materials_and_equipment (
          id TEXT PRIMARY KEY,
          log_id TEXT NOT NULL,
          item_name TEXT NOT NULL,
          quantity REAL NOT NULL,
          unit TEXT,
          category TEXT NOT NULL DEFAULT 'material',
          FOREIGN KEY (log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await _createV3Tables(db);
      for (final col in [
        'serial_no INTEGER',
        'description TEXT',
        'unit TEXT',
        'unit_price REAL',
        'total_amount REAL',
        'month TEXT',
      ]) {
        try {
          await db.execute('ALTER TABLE expenses ADD COLUMN $col');
        } catch (_) {}
      }
      await db.execute('''
        UPDATE expenses SET
          total_amount = COALESCE(total_amount, amount),
          unit_price = COALESCE(unit_price, amount),
          description = COALESCE(description, note),
          month = COALESCE(month, substr(date, 1, 7))
        WHERE total_amount IS NULL OR unit_price IS NULL OR description IS NULL OR month IS NULL
      ''');
    }
  }

  // ---------- Projects ----------
  Future<void> insertProject(Project p) async {
    final db = await database;
    await db.insert('projects', p.toMap());
  }

  Future<List<Project>> getProjects() async {
    final db = await database;
    final rows = await db.query('projects', orderBy: 'createdAt DESC');
    return rows.map((r) => Project.fromMap(r)).toList();
  }

  Future<void> deleteProject(String id) async {
    final db = await database;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Sites ----------
  Future<void> insertSite(Site s) async {
    final db = await database;
    await db.insert('sites', s.toMap());
  }

  Future<List<Site>> getSitesForProject(String projectId) async {
    final db = await database;
    final rows = await db.query('sites',
        where: 'projectId = ?', whereArgs: [projectId], orderBy: 'createdAt DESC');
    return rows.map((r) => Site.fromMap(r)).toList();
  }

  Future<void> deleteSite(String id) async {
    final db = await database;
    await db.delete('sites', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Daily Logs ----------
  Future<void> insertDailyLog(DailyLog log) async {
    final db = await database;
    await db.insert('daily_logs', log.toMap());
  }

  Future<List<DailyLog>> getLogsForSite(String siteId) async {
    final db = await database;
    final rows = await db.query('daily_logs',
        where: 'siteId = ?', whereArgs: [siteId], orderBy: 'date DESC');
    return rows.map((r) => DailyLog.fromMap(r)).toList();
  }

  Future<void> deleteDailyLog(String id) async {
    final db = await database;
    await db.delete('daily_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateDailyLog(DailyLog log) async {
    final db = await database;
    await db.update('daily_logs', log.toMap(), where: 'id = ?', whereArgs: [log.id]);
  }

  Future<void> markAllLogsSynced() async {
    final db = await database;
    await db.update('daily_logs', {'is_synced': 1});
  }

  Future<int> getPendingSyncCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM daily_logs WHERE is_synced = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getTotalLogCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM daily_logs');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ---------- Materials & Equipment ----------
  Future<void> insertMaterialItem(MaterialItem item) async {
    final db = await database;
    await db.insert('materials_and_equipment', item.toMap());
  }

  Future<List<MaterialItem>> getMaterialsForLog(String logId) async {
    final db = await database;
    final rows = await db.query('materials_and_equipment', where: 'log_id = ?', whereArgs: [logId]);
    return rows.map((r) => MaterialItem.fromMap(r)).toList();
  }

  Future<List<MaterialItem>> getMaterialsForSite(String siteId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT m.* FROM materials_and_equipment m
      INNER JOIN daily_logs l ON m.log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date DESC
    ''', [siteId]);
    return rows.map((r) => MaterialItem.fromMap(r)).toList();
  }

  Future<void> deleteMaterialItem(String id) async {
    final db = await database;
    await db.delete('materials_and_equipment', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMaterialsForLog(String logId) async {
    final db = await database;
    await db.delete('materials_and_equipment', where: 'log_id = ?', whereArgs: [logId]);
  }

  // ---------- Expenses ----------
  Future<void> insertExpense(Expense e) async {
    final db = await database;
    await db.insert('expenses', e.toMap());
  }

  Future<List<Expense>> getExpensesForSite(String siteId) async {
    final db = await database;
    final rows = await db.query('expenses',
        where: 'siteId = ?', whereArgs: [siteId], orderBy: 'date DESC');
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<List<Expense>> getExpensesForProject(String projectId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT e.* FROM expenses e
      INNER JOIN sites s ON e.siteId = s.id
      WHERE s.projectId = ?
      ORDER BY e.date DESC
    ''', [projectId]);
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<double> getTotalExpensesForProject(String projectId) async {
    final expenses = await getExpensesForProject(projectId);
    return expenses.fold<double>(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> deleteExpense(String id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateExpense(Expense e) async {
    final db = await database;
    await db.update('expenses', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<int> getNextExpenseSerialNo(String siteId, String monthKey) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(serial_no) AS m FROM expenses WHERE siteId = ? AND month = ?',
      [siteId, monthKey],
    );
    final max = result.first['m'] as int?;
    return (max ?? 0) + 1;
  }

  // ---------- NEW: expense queries needed by analytics & cash float ----------
  Future<List<Expense>> getExpensesForSiteAndDate(String siteId, String dateIso) async {
    final db = await database;
    final rows = await db.query('expenses',
        where: 'siteId = ? AND date LIKE ?',
        whereArgs: [siteId, '$dateIso%'],
        orderBy: 'serial_no ASC');
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<double> getTotalExpensesForSiteAndDate(String siteId, String dateIso) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(total_amount) as total FROM expenses
      WHERE siteId = ? AND date LIKE ?
    ''', [siteId, '$dateIso%']);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Expense>> getExpensesByMonth(String siteId, String month) async {
    final db = await database;
    final rows = await db.query('expenses',
        where: 'siteId = ? AND month = ?',
        whereArgs: [siteId, month],
        orderBy: 'date ASC, serial_no ASC');
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  Future<Map<String, double>> getExpenseTotalsByCategory(String siteId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT category, SUM(total_amount) as total
      FROM expenses WHERE siteId = ? GROUP BY category
    ''', [siteId]);
    return {for (var r in result) r['category'] as String: (r['total'] as num).toDouble()};
  }

  // ---------- Workers ----------
  Future<void> insertWorker(Worker w) async {
    final db = await database;
    await db.insert('workers', w.toMap());
  }

  Future<void> updateWorker(Worker w) async {
    final db = await database;
    await db.update('workers', w.toMap(), where: 'id = ?', whereArgs: [w.id]);
  }

  Future<List<Worker>> getWorkersForSite(String siteId, {bool activeOnly = true}) async {
    final db = await database;
    final rows = await db.query('workers',
        where: activeOnly ? 'site_id = ? AND is_active = 1' : 'site_id = ?',
        whereArgs: [siteId],
        orderBy: 'name ASC');
    return rows.map((r) => Worker.fromMap(r)).toList();
  }

  Future<void> deactivateWorker(String id) async {
    final db = await database;
    await db.update('workers', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteWorker(String id) async {
    final db = await database;
    await db.delete('workers', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Attendance ----------
  Future<void> upsertAttendance(Attendance a) async {
    final db = await database;
    await db.insert('daily_attendance', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> bulkUpsertAttendance(List<Attendance> records) async {
    final db = await database;
    final batch = db.batch();
    for (final r in records) {
      batch.insert('daily_attendance', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Attendance>> getAttendanceForLog(String dailyLogId) async {
    final db = await database;
    final rows = await db.query('daily_attendance',
        where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
    return rows.map((r) => Attendance.fromMap(r)).toList();
  }

  Future<void> deleteAttendanceForLog(String dailyLogId) async {
    final db = await database;
    await db.delete('daily_attendance', where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
  }

  Future<Map<String, int>> getAttendanceSummaryForLog(String dailyLogId) async {
    final rows = await getAttendanceForLog(dailyLogId);
    final summary = <String, int>{'Present': 0, 'Absent': 0, 'Half-Day': 0};
    for (final r in rows) {
      summary[r.status.dbValue] = (summary[r.status.dbValue] ?? 0) + 1;
    }
    return summary;
  }

  // ---------- Material Stock Logs ----------
  Future<void> insertMaterialStockLog(MaterialStockLog m) async {
    final db = await database;
    await db.insert('material_stock_logs', m.toMap());
  }

  Future<void> updateMaterialStockLog(MaterialStockLog m) async {
    final db = await database;
    await db.update('material_stock_logs', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
  }

  Future<List<MaterialStockLog>> getMaterialStockLogsForLog(String dailyLogId) async {
    final db = await database;
    final rows = await db.query('material_stock_logs',
        where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
    return rows.map((r) => MaterialStockLog.fromMap(r)).toList();
  }

  Future<double?> getLastClosingBalance(String siteId, String itemName) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT m.closing_balance AS cb FROM material_stock_logs m
      INNER JOIN daily_logs l ON m.daily_log_id = l.id
      WHERE l.siteId = ? AND m.item_name = ?
      ORDER BY l.date DESC LIMIT 1
    ''', [siteId, itemName]);
    if (rows.isEmpty) return null;
    return (rows.first['cb'] as num?)?.toDouble();
  }

  Future<void> deleteMaterialStockLog(String id) async {
    final db = await database;
    await db.delete('material_stock_logs', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Equipment Dipping Logs ----------
  Future<void> insertEquipmentDippingLog(EquipmentDippingLog e) async {
    final db = await database;
    await db.insert('equipment_dipping_logs', e.toMap());
  }

  Future<void> updateEquipmentDippingLog(EquipmentDippingLog e) async {
    final db = await database;
    await db.update('equipment_dipping_logs', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<List<EquipmentDippingLog>> getEquipmentDippingLogsForLog(String dailyLogId) async {
    final db = await database;
    final rows = await db.query('equipment_dipping_logs',
        where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
    return rows.map((r) => EquipmentDippingLog.fromMap(r)).toList();
  }

  Future<void> deleteEquipmentDippingLog(String id) async {
    final db = await database;
    await db.delete('equipment_dipping_logs', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Cash Floats ----------
  Future<void> insertCashFloat(CashFloat c) async {
    final db = await database;
    await db.insert('cash_floats', c.toMap());
  }

  Future<void> updateCashFloat(CashFloat c) async {
    final db = await database;
    await db.update('cash_floats', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<List<CashFloat>> getCashFloatsForSite(String siteId) async {
    final db = await database;
    final rows = await db.query('cash_floats',
        where: 'site_id = ?', whereArgs: [siteId], orderBy: 'date DESC');
    return rows.map((r) => CashFloat.fromMap(r)).toList();
  }

  Future<CashFloat?> getLatestCashFloat(String siteId) async {
    final rows = await getCashFloatsForSite(siteId);
    return rows.isEmpty ? null : rows.first;
  }

  Future<CashFloat?> getCashFloatBySiteAndDate(String siteId, String dateIso) async {
    final db = await database;
    final rows = await db.query('cash_floats',
        where: 'site_id = ? AND date LIKE ?',
        whereArgs: [siteId, '$dateIso%'],
        limit: 1);
    return rows.isNotEmpty ? CashFloat.fromMap(rows.first) : null;
  }

  Future<double> getTotalFloatReceived(String siteId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(float_received) as total FROM cash_floats WHERE site_id = ?
    ''', [siteId]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> deleteCashFloat(String id) async {
    final db = await database;
    await db.delete('cash_floats', where: 'id = ?', whereArgs: [id]);
  }
}
