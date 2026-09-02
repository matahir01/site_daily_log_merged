import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/project_list_screen.dart';
import 'services/google_drive_service.dart';
import 'services/google_sheets_service.dart';
import 'services/offline_queue_service.dart';
import 'services/sync_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 3: offline-first sync — must init before any screen can enqueue
  // or flush a queued Sheets/Drive action.
  await OfflineQueueService.instance.init();
  GoogleDriveService.registerQueueHandler();
  GoogleSheetsService.registerQueueHandler();
  await SyncEngine.instance.init();
  // Best-effort catch-up in case actions were queued last session and the
  // app is opening back online.
  unawaited(SyncEngine.instance.runSync());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SyncStatusProvider()),
        ChangeNotifierProvider.value(value: SyncEngine.instance),
      ],
      child: const SiteDailyLogApp(),
    ),
  );
}

class SiteDailyLogApp extends StatelessWidget {
  const SiteDailyLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Site Daily Log',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ProjectListScreen(),
    );
  }
}
