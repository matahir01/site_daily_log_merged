import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/project_list_screen.dart';
import 'services/google_drive_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SyncStatusProvider(),
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
