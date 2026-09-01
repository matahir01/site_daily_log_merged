import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import 'google_auth.dart';

class GoogleDriveService {
  static Future<drive.DriveApi> _getDriveApi() async {
    final account = await GoogleAuth.signInInteractive();
    if (account == null) throw Exception('Google Sign-In required');
    return GoogleAuth.driveApiFor(account);
  }

  static Future<drive.File> uploadBackup() async {
    final api = await _getDriveApi();
    final dbPath = await DatabaseHelper.instance.getDbPath();
    final file = File(dbPath);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final media = drive.Media(file.openRead(), file.lengthSync());
    final driveFile = drive.File()
      ..name = 'site_daily_log_backup_$timestamp.db'
      ..parents = ['appDataFolder'];
    return api.files.create(driveFile, uploadMedia: media);
  }

  static Future<List<drive.File>> listBackups() async {
    final api = await _getDriveApi();
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "name contains 'site_daily_log_backup'",
      orderBy: 'createdTime desc',
    );
    return result.files ?? [];
  }

  static Future<void> restoreFromBackup(drive.File backup) async {
    final api = await _getDriveApi();
    final media = await api.files.get(backup.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = await media.stream.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
    final dbPath = await DatabaseHelper.instance.getDbPath();
    await DatabaseHelper.instance.closeForRestore();
    final file = File(dbPath);
    await file.writeAsBytes(bytes, flush: true);
  }
}

class SyncStatusProvider extends ChangeNotifier {
  int _pendingCount = 0;

  int get pendingCount => _pendingCount;

  Future<void> refresh() async {
    _pendingCount = await DatabaseHelper.instance.getPendingSyncCount();
    notifyListeners();
  }
}
