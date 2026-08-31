import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import '../db/database_helper.dart';

class GoogleDriveService {
  static final _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  static Future<drive.DriveApi> _getDriveApi() async {
    final account = await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
    if (account == null) throw Exception('Google Sign-In required');
    final auth = await account.authentication;
    if (auth.accessToken == null) {
      throw Exception('Google Sign-In failed: no access token');
    }
    final client = http.Client();
    return drive.DriveApi(
      _AuthClient(client, auth.accessToken!, auth.idToken),
    );
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

class _AuthClient extends http.BaseClient {
  final http.Client _inner;
  final String _accessToken;
  final String? _idToken;

  _AuthClient(this._inner, this._accessToken, this._idToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    if (_idToken != null) request.headers['X-Goog-AuthUser'] = '0';
    return _inner.send(request);
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
