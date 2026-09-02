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
import '../models/diesel_activity_issuance.dart';
import '../models/concrete_pour.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _db;

  static const int _dbVersion = 6;

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
    await _createV4Tables(db);
    await _createV5Tables(db);
    await _createV6Tables(db);
  }

  Future<void> _createV6Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS concrete_pours (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        element_name TEXT NOT NULL,
        concrete_grade TEXT NOT NULL,
        volume_m3 REAL NOT NULL DEFAULT 0.0,
        slump_mm REAL,
        cubes_cast INTEGER NOT NULL DEFAULT 0,
        batch_ticket_no TEXT,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
    // Engine-hour meter readings for machinery burn-rate calculations.
    // equipment_dipping_logs is created by _createV3Tables (above) without
    // these columns, so this ALTER is needed on both a fresh install and an
    // upgrade from an older version. try/catch guards against ever running
    // it twice against the same database.
    for (final col in [
      'opening_engine_hours REAL',
      'closing_engine_hours REAL',
    ]) {
      try {
        await db.execute('ALTER TABLE equipment_dipping_logs ADD COLUMN $col');
      } catch (_) {}
    }
  }

  Future<void> _createV5Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sheet_sync (
        site_id TEXT PRIMARY KEY,
        spreadsheet_id TEXT,
        spreadsheet_url TEXT,
        auto_sync INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT,
        last_sync_error TEXT,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createV4Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS diesel_activity_issuance (
        id TEXT PRIMARY KEY,
        daily_log_id TEXT NOT NULL,
        activity_name TEXT NOT NULL,
        litres_issued REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (daily_log_id) REFERENCES daily_logs (id) ON DELETE CASCADE
      )
    ''');
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
    if (oldVersion < 4) {
      await _createV4Tables(db);
    }
    if (oldVersion < 5) {
      await _createV5Tables(db);
    }
    if (oldVersion < 6) {
      await _createV6Tables(db);
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

  Future<Site?> getSiteById(String id) async {
    final db = await database;
    final rows = await db.query('sites', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty ? Site.fromMap(rows.first) : null;
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

  Future<void> deleteMaterialStockLogsForLog(String dailyLogId) async {
    final db = await database;
    await db.delete('material_stock_logs', where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
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

  Future<void> deleteEquipmentDippingLogsForLog(String dailyLogId) async {
    final db = await database;
    await db.delete('equipment_dipping_logs', where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
  }

  /// Every material stock row for a site, each tagged with its log's date —
  /// used for exports that need a per-day ledger rather than one log at a time.
  Future<List<Map<String, dynamic>>> getMaterialStockLogsForSite(String siteId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT m.*, l.date AS log_date FROM material_stock_logs m
      INNER JOIN daily_logs l ON m.daily_log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date ASC, m.item_name ASC
    ''', [siteId]);
  }

  /// Every equipment dipping row for a site, each tagged with its log's date.
  Future<List<Map<String, dynamic>>> getEquipmentDippingLogsForSite(String siteId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT e.*, l.date AS log_date FROM equipment_dipping_logs e
      INNER JOIN daily_logs l ON e.daily_log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date ASC, e.equipment_name ASC
    ''', [siteId]);
  }

  /// Every ad-hoc diesel activity issuance row for a site, tagged with date.
  Future<List<Map<String, dynamic>>> getDieselActivityForSite(String siteId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT d.*, l.date AS log_date FROM diesel_activity_issuance d
      INNER JOIN daily_logs l ON d.daily_log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date ASC
    ''', [siteId]);
  }

  // ---------- Concrete Pours / Slump Test QC ----------
  Future<void> insertConcretePour(ConcretePour c) async {
    final db = await database;
    await db.insert('concrete_pours', c.toMap());
  }

  Future<void> updateConcretePour(ConcretePour c) async {
    final db = await database;
    await db.update('concrete_pours', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<List<ConcretePour>> getConcretePoursForLog(String dailyLogId) async {
    final db = await database;
    final rows = await db.query('concrete_pours',
        where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
    return rows.map((r) => ConcretePour.fromMap(r)).toList();
  }

  Future<void> deleteConcretePour(String id) async {
    final db = await database;
    await db.delete('concrete_pours', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteConcretePoursForLog(String dailyLogId) async {
    final db = await database;
    await db.delete('concrete_pours', where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
  }

  /// Every concrete pour row for a site, each tagged with its log's date —
  /// used by the PDF/Excel report engines for the QC table.
  Future<List<Map<String, dynamic>>> getConcretePoursForSite(String siteId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT c.*, l.date AS log_date FROM concrete_pours c
      INNER JOIN daily_logs l ON c.daily_log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date ASC, c.element_name ASC
    ''', [siteId]);
  }

  // ---------- Diesel Activity Issuance (non-dipped machines/activities) ----------
  Future<void> insertDieselActivityIssuance(DieselActivityIssuance d) async {
    final db = await database;
    await db.insert('diesel_activity_issuance', d.toMap());
  }

  Future<List<DieselActivityIssuance>> getDieselActivityForLog(String dailyLogId) async {
    final db = await database;
    final rows = await db.query('diesel_activity_issuance',
        where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
    return rows.map((r) => DieselActivityIssuance.fromMap(r)).toList();
  }

  Future<void> deleteDieselActivityForLog(String dailyLogId) async {
    final db = await database;
    await db.delete('diesel_activity_issuance', where: 'daily_log_id = ?', whereArgs: [dailyLogId]);
  }

  /// Sitewide diesel totals across every daily log for a site — used by
  /// exports (Excel/PDF) to show cumulative received/issued/balance rather
  /// than just a single day's snapshot.
  Future<Map<String, double>> getDieselTotalsForSite(String siteId) async {
    final db = await database;
    final materialRows = await db.rawQuery('''
      SELECT SUM(m.received) AS recv FROM material_stock_logs m
      INNER JOIN daily_logs l ON m.daily_log_id = l.id
      WHERE l.siteId = ? AND m.item_name = 'Diesel'
    ''', [siteId]);
    final machineRows = await db.rawQuery('''
      SELECT SUM(e.diesel_issued_litres) AS issued FROM equipment_dipping_logs e
      INNER JOIN daily_logs l ON e.daily_log_id = l.id
      WHERE l.siteId = ?
    ''', [siteId]);
    final activityRows = await db.rawQuery('''
      SELECT SUM(d.litres_issued) AS issued FROM diesel_activity_issuance d
      INNER JOIN daily_logs l ON d.daily_log_id = l.id
      WHERE l.siteId = ?
    ''', [siteId]);
    final openingBal = await getLastClosingBalance(siteId, 'Diesel') ?? 0.0;
    final received = (materialRows.first['recv'] as num?)?.toDouble() ?? 0.0;
    final issuedMachines = (machineRows.first['issued'] as num?)?.toDouble() ?? 0.0;
    final issuedActivities = (activityRows.first['issued'] as num?)?.toDouble() ?? 0.0;
    return {
      'opening': openingBal,
      'received': received,
      'issuedMachines': issuedMachines,
      'issuedActivities': issuedActivities,
      'balance': openingBal + received - issuedMachines - issuedActivities,
    };
  }

  /// Sitewide reinforcement (rebar) totals per size across every daily log.
  Future<Map<String, Map<String, double>>> getReinforcementTotalsForSite(String siteId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT m.item_name AS item, SUM(m.received) AS recv, SUM(m.issued) AS issued
      FROM material_stock_logs m
      INNER JOIN daily_logs l ON m.daily_log_id = l.id
      WHERE l.siteId = ? AND m.item_name LIKE '%Rebar%'
      GROUP BY m.item_name
    ''', [siteId]);
    final result = <String, Map<String, double>>{};
    for (final r in rows) {
      final item = r['item'] as String;
      final closing = await getLastClosingBalance(siteId, item) ?? 0.0;
      result[item] = {
        'received': (r['recv'] as num?)?.toDouble() ?? 0.0,
        'issued': (r['issued'] as num?)?.toDouble() ?? 0.0,
        'closing': closing,
      };
    }
    return result;
  }

  // ---------- Google Sheets Sync Link ----------
  Future<Map<String, dynamic>?> getSheetSync(String siteId) async {
    final db = await database;
    final rows = await db.query('sheet_sync', where: 'site_id = ?', whereArgs: [siteId]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> upsertSheetSync({
    required String siteId,
    String? spreadsheetId,
    String? spreadsheetUrl,
    bool? autoSync,
    String? lastSyncedAt,
    String? lastSyncError,
  }) async {
    final db = await database;
    final existing = await getSheetSync(siteId);
    final row = {
      'site_id': siteId,
      'spreadsheet_id': spreadsheetId ?? existing?['spreadsheet_id'],
      'spreadsheet_url': spreadsheetUrl ?? existing?['spreadsheet_url'],
      'auto_sync': (autoSync ?? ((existing?['auto_sync'] as int?) == 1)) ? 1 : 0,
      'last_synced_at': lastSyncedAt ?? existing?['last_synced_at'],
      'last_sync_error': lastSyncError,
    };
    if (existing != null) {
      await db.update('sheet_sync', row, where: 'site_id = ?', whereArgs: [siteId]);
    } else {
      await db.insert('sheet_sync', row);
    }
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

  // ---------- Phase 3: Advanced Analytics & Batch Export (date-range aware) ----------

  /// Expenses for a site within an inclusive date range, ascending by date.
  /// Used by the Analytics screen and batch export so both honor the same
  /// customizable date range.
  Future<List<Expense>> getExpensesForSiteInRange(
      String siteId, DateTime start, DateTime end) async {
    final db = await database;
    final rows = await db.query(
      'expenses',
      where: 'siteId = ? AND date >= ? AND date <= ?',
      whereArgs: [siteId, start.toIso8601String(), _endOfDay(end)],
      orderBy: 'date ASC',
    );
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  /// Daily logs for a site within an inclusive date range, ascending by date.
  Future<List<DailyLog>> getLogsForSiteInRange(
      String siteId, DateTime start, DateTime end) async {
    final db = await database;
    final rows = await db.query(
      'daily_logs',
      where: 'siteId = ? AND date >= ? AND date <= ?',
      whereArgs: [siteId, start.toIso8601String(), _endOfDay(end)],
      orderBy: 'date ASC',
    );
    return rows.map((r) => DailyLog.fromMap(r)).toList();
  }

  /// Concrete pour volume (m³) and cube counts per day for a site within a
  /// date range — powers the "Concrete Pour Volumes" analytics chart.
  Future<List<Map<String, dynamic>>> getConcretePourTrendForSite(
      String siteId, DateTime start, DateTime end) async {
    final db = await database;
    return db.rawQuery('''
      SELECT l.date AS log_date,
             SUM(c.volume_m3) AS total_volume,
             SUM(c.cubes_cast) AS total_cubes
      FROM concrete_pours c
      INNER JOIN daily_logs l ON c.daily_log_id = l.id
      WHERE l.siteId = ? AND l.date >= ? AND l.date <= ?
      GROUP BY l.date
      ORDER BY l.date ASC
    ''', [siteId, start.toIso8601String(), _endOfDay(end)]);
  }

  /// Litres of diesel issued per day (dipped machines + ad-hoc activities
  /// combined) for a site within a date range — powers the "Diesel
  /// Consumption Rate" analytics chart.
  Future<List<Map<String, dynamic>>> getDieselConsumptionTrendForSite(
      String siteId, DateTime start, DateTime end) async {
    final db = await database;
    return db.rawQuery('''
      SELECT l.date AS log_date,
        COALESCE((SELECT SUM(e.diesel_issued_litres) FROM equipment_dipping_logs e
                  WHERE e.daily_log_id = l.id), 0.0) AS machine_litres,
        COALESCE((SELECT SUM(a.litres_issued) FROM diesel_activity_issuance a
                  WHERE a.daily_log_id = l.id), 0.0) AS activity_litres
      FROM daily_logs l
      WHERE l.siteId = ? AND l.date >= ? AND l.date <= ?
      ORDER BY l.date ASC
    ''', [siteId, start.toIso8601String(), _endOfDay(end)]);
  }

  /// Daily worker-attendance status counts (Present/Absent/Half-Day) for a
  /// site within a date range — powers the "Worker Attendance Trend" chart.
  Future<List<Map<String, dynamic>>> getAttendanceTrendForSite(
      String siteId, DateTime start, DateTime end) async {
    final db = await database;
    return db.rawQuery('''
      SELECT l.date AS log_date, a.status AS status, COUNT(*) AS cnt
      FROM daily_attendance a
      INNER JOIN daily_logs l ON a.daily_log_id = l.id
      WHERE l.siteId = ? AND l.date >= ? AND l.date <= ?
      GROUP BY l.date, a.status
      ORDER BY l.date ASC
    ''', [siteId, start.toIso8601String(), _endOfDay(end)]);
  }

  /// Latest known closing balance per tracked material/equipment item for a
  /// site (all-time, not range-scoped — a stock level is a running total,
  /// not a range aggregate) — powers the "Material Stock Levels" KPI card.
  Future<Map<String, Map<String, dynamic>>> getCurrentMaterialStockLevels(
      String siteId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT m.item_name AS item, m.unit AS unit, m.closing_balance AS cb, l.date AS d
      FROM material_stock_logs m
      INNER JOIN daily_logs l ON m.daily_log_id = l.id
      WHERE l.siteId = ?
      ORDER BY l.date ASC
    ''', [siteId]);
    final latest = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      latest[r['item'] as String] = {
        'unit': r['unit'] as String? ?? '',
        'balance': (r['cb'] as num?)?.toDouble() ?? 0.0,
      };
    }
    return latest;
  }

  /// Cash floats for a site within an inclusive date range, ascending.
  Future<List<CashFloat>> getCashFloatsForSiteInRange(
      String siteId, DateTime start, DateTime end) async {
    final db = await database;
    final rows = await db.query(
      'cash_floats',
      where: 'site_id = ? AND date >= ? AND date <= ?',
      whereArgs: [siteId, start.toIso8601String(), _endOfDay(end)],
      orderBy: 'date ASC',
    );
    return rows.map((r) => CashFloat.fromMap(r)).toList();
  }

  /// End-of-day ISO bound (23:59:59.999) so a date-range query with an
  /// end date of "today" still includes rows logged later today.
  String _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999).toIso8601String();
}
