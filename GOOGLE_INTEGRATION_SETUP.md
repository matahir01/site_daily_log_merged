# Civil Site Manager — Google Drive & Sheets Setup

Package name: `com.mat.civilsitemanager`

This guide completes Google Sign-In, Drive backup/restore, and Google Sheets sync for the Android app without committing secrets to the repository.

## 1. Create the permanent Android signing key

Create the key on a computer you control and keep both the `.jks` file and its passwords backed up somewhere private. Do not commit it to GitHub or send it through chat.

Example command:

```bash
keytool -genkeypair -v \
  -keystore civil-site-manager-upload.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias civil-site-manager
```

Then obtain the SHA-1 fingerprint:

```bash
keytool -list -v \
  -keystore civil-site-manager-upload.jks \
  -alias civil-site-manager
```

Copy only the `SHA1:` fingerprint. The fingerprint is safe to use in Google Cloud; the keystore/passwords stay private.

## 2. Create the Google Cloud project

In Google Cloud Console:

1. Create a project named `Civil Site Manager`.
2. Enable **Google Drive API**.
3. Enable **Google Sheets API**.
4. Open **Google Auth Platform** and configure Branding/Audience.
5. Use app name `Civil Site Manager` and your own support/contact email.
6. For private testing, choose an External audience and add your Google account as a test user if Google asks for test users.

## 3. Configure OAuth data access

Civil Site Manager now requests only:

- `https://www.googleapis.com/auth/drive.appdata` for private database backups.
- `https://www.googleapis.com/auth/drive.file` for files/spreadsheets created or opened by the app.

The broad `spreadsheets` scope is intentionally not requested. `drive.file` is the narrower per-file scope recommended by Google for apps like this.

## 4. Create the Android OAuth client

In Google Cloud Console → Google Auth Platform / Credentials:

1. Create an OAuth client.
2. Application type: **Android**.
3. Package name: `com.mat.civilsitemanager`.
4. SHA-1 certificate fingerprint: paste the SHA-1 from your permanent signing key.
5. Save.

For this app's current client-only OAuth flow, do not create or commit an API key. The Android OAuth client is the important credential.

## 5. Add release-signing secrets to GitHub Actions

Repository → **Settings → Secrets and variables → Actions → New repository secret**.

Create these four secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The alias should normally be `civil-site-manager` if you used the example command.

Convert the keystore to a one-line Base64 string before storing it in `ANDROID_KEYSTORE_BASE64`.

Linux/macOS:

```bash
base64 < civil-site-manager-upload.jks | tr -d '\n'
```

PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('civil-site-manager-upload.jks'))
```

Do not paste the resulting Base64 string into issues, commits, screenshots, or chat.

The GitHub workflow reconstructs the keystore only inside the temporary build runner and creates `android/key.properties` at build time. Neither file is committed.

## 6. Build and test

After all four GitHub secrets are present, push/merge a commit to `main` so the workflow produces a permanently release-signed APK.

Install that APK, then test:

1. Google Sheets → Connect & Sync.
2. Create/sync a project spreadsheet.
3. Add a new daily log and verify silent auto-sync.
4. Google Drive Backup → Back Up Now.
5. Confirm the backup succeeds.
6. Test restore only after you have a disposable/test database or a safe backup.

If Google Sign-In immediately closes/cancels after selecting an account, the first things to check are package name `com.mat.civilsitemanager`, the OAuth Android client's SHA-1, and whether the APK was signed by the same keystore whose SHA-1 was registered.

## 7. Later, for Play Store release

If Google Play App Signing is enabled, Google Play will use its own app-signing certificate for distributed Play Store builds. Add the Play app-signing SHA-1 as another Android OAuth client/fingerprint when you reach Play Console release testing. Keep the upload keystore as well; it is still used to authenticate uploads to Play.
