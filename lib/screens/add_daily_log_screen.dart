import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../services/google_sheets_service.dart';
import '../services/image_compression_service.dart';
import '../services/photo_watermark_service.dart';

class AddDailyLogScreen extends StatefulWidget {
  final String siteId;
  final String? siteName;
  const AddDailyLogScreen({super.key, required this.siteId, this.siteName});

  @override
  State<AddDailyLogScreen> createState() => _AddDailyLogScreenState();
}

class _AddDailyLogScreenState extends State<AddDailyLogScreen> {
  final _weatherController = TextEditingController();
  final _crewController = TextEditingController();
  final _workController = TextEditingController();
  final _issuesController = TextEditingController();
  final List<String> _photoPaths = [];
  bool _saving = false;

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (file == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${const Uuid().v4()}${p.extension(file.path)}';
    final rawPath = p.join(appDir.path, 'photos', fileName);
    await Directory(p.join(appDir.path, 'photos')).create(recursive: true);

    // 1. Compress first
    final compressed = await ImageCompressionService.compressAndSave(
      sourcePath: file.path,
      destinationPath: rawPath,
    );

    // 2. Watermark after compression
    if (widget.siteName != null) {
      final watermarked = await PhotoWatermarkService.watermarkPhoto(
        imagePath: compressed.path,
        siteName: widget.siteName!,
      );
      setState(() => _photoPaths.add(watermarked.path));
    } else {
      setState(() => _photoPaths.add(compressed.path));
    }
  }

  Future<Position?> _tryGetLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final position = await _tryGetLocation();

    final log = DailyLog(
      id: const Uuid().v4(),
      siteId: widget.siteId,
      date: DateTime.now(),
      weather: _weatherController.text.trim().isEmpty ? null : _weatherController.text.trim(),
      crewCount: int.tryParse(_crewController.text.trim()),
      workCompleted: _workController.text.trim().isEmpty ? null : _workController.text.trim(),
      issues: _issuesController.text.trim().isEmpty ? null : _issuesController.text.trim(),
      photoPaths: _photoPaths,
      lat: position?.latitude,
      lng: position?.longitude,
    );

    await DatabaseHelper.instance.insertDailyLog(log);
    GoogleSheetsService.autoSyncSite(widget.siteId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Daily Log')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _weatherController,
            decoration: const InputDecoration(labelText: 'Weather', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _crewController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Crew Count', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _workController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Work Completed', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _issuesController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Issues / Delays', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Add Photo'),
          ),
          if (_photoPaths.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _photoPaths.map((path) => Padding(
                  padding: const EdgeInsets.only(right: 8, top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover),
                  ),
                )).toList(),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const CircularProgressIndicator() : const Text('Save Daily Log'),
          ),
        ],
      ),
    );
  }
}
