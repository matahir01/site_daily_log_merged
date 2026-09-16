import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

/// Single shared [GoogleSignIn] instance for the whole app.
///
/// The app deliberately requests the narrowest practical Google scopes:
/// - drive.appdata for private database backups in appDataFolder
/// - drive.file for spreadsheets/files Civil Site Manager creates or opens
///
/// `drive.file` is accepted by the Google Sheets API for per-file access, so
/// a broad `spreadsheets` scope is not required for our create/sync workflow.
class GoogleAuth {
  static final GoogleSignIn instance = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveAppdataScope,
      drive.DriveApi.driveFileScope,
    ],
  );

  /// Signs in only if a session already exists — never shows the account
  /// picker. Used for background/auto-sync so routine saves don't
  /// interrupt the user with a sign-in prompt.
  static Future<GoogleSignInAccount?> signInSilentlyOnly() {
    return instance.signInSilently();
  }

  /// Signs in interactively if needed — shows the account picker. Used
  /// only for explicit user actions like "Connect & Sync".
  static Future<GoogleSignInAccount?> signInInteractive() async {
    return await instance.signInSilently() ?? await instance.signIn();
  }

  static Future<http.Client> _authedClient(GoogleSignInAccount account) async {
    final auth = await account.authentication;
    if (auth.accessToken == null) {
      throw Exception('Google Sign-In failed: no access token');
    }
    return _AuthClient(http.Client(), auth.accessToken!);
  }

  static Future<drive.DriveApi> driveApiFor(GoogleSignInAccount account) async {
    return drive.DriveApi(await _authedClient(account));
  }

  static Future<sheets.SheetsApi> sheetsApiFor(GoogleSignInAccount account) async {
    return sheets.SheetsApi(await _authedClient(account));
  }
}

class _AuthClient extends http.BaseClient {
  final http.Client _inner;
  final String _accessToken;

  _AuthClient(this._inner, this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }
}
