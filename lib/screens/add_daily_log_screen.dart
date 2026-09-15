import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../models/daily_site_report_meta.dart';
import '../services/daily_report_meta_repository.dart';
import '../services/google_sheets_service.dart';
import '../services/image_compression_service.dart';
import '../services/photo_watermark_service.dart';

class AddDailyLogScreen extends StatefulWidget {
  final String siteId;
  final String? siteName;
  const AddDailyLogScreen({super.key, required this.siteId, this.siteName});
  @override State<AddDailyLogScreen> createState() => _AddDailyLogScreenState();
}

class _AddDailyLogScreenState extends State<AddDailyLogScreen> {
  final _weatherController = TextEditingController();
  final _crewController = TextEditingController();
  final _workController = TextEditingController();
  final _issuesController = TextEditingController();
  final _reportNoController = TextEditingController();
  final _shiftController = TextEditingController(text: 'Day');
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final _progressController = TextEditingController();
  final _qualityController = TextEditingController();
  final _hseController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _nextDayController = TextEditingController();
  final _referencesController = TextEditingController();
  final List<String> _photoPaths = [];
  bool _saving = false;

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 60);
    if (file == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${const Uuid().v4()}${p.extension(file.path)}';
    final rawPath = p.join(appDir.path, 'photos', fileName);
    await Directory(p.join(appDir.path, 'photos')).create(recursive: true);
    final compressed = await ImageCompressionService.compressAndSave(sourcePath: file.path, destinationPath: rawPath);
    if (widget.siteName != null) {
      final watermarked = await PhotoWatermarkService.watermarkPhoto(imagePath: compressed.path, siteName: widget.siteName!);
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
    } catch (_) { return null; }
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final position = await _tryGetLocation();
      final logId = const Uuid().v4();
      final log = DailyLog(
        id: logId, siteId: widget.siteId, date: DateTime.now(),
        weather: _text(_weatherController), crewCount: int.tryParse(_crewController.text.trim()),
        workCompleted: _text(_workController), issues: _text(_issuesController), photoPaths: _photoPaths,
        lat: position?.latitude, lng: position?.longitude,
      );
      await DatabaseHelper.instance.insertDailyLog(log);
      await DailyReportMetaRepository.save(DailySiteReportMeta(
        dailyLogId: logId, reportNo: _text(_reportNoController), shift: _text(_shiftController),
        progressQuantity: double.tryParse(_quantityController.text.trim()), progressUnit: _text(_unitController),
        percentComplete: double.tryParse(_progressController.text.trim()), qualityInspections: _text(_qualityController),
        hseObservations: _text(_hseController), siteInstructions: _text(_instructionsController),
        nextDayPlan: _text(_nextDayController), documentReferences: _text(_referencesController),
      ));
      GoogleSheetsService.autoSyncSite(widget.siteId);
      if (mounted) Navigator.pop(context);
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Widget _field(TextEditingController c, String label, {int lines = 1, TextInputType? keyboardType}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: c, maxLines: lines, keyboardType: keyboardType, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
  );

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Daily Log')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Daily Record', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: _field(_reportNoController, 'Report No.')), const SizedBox(width: 12), Expanded(child: _field(_shiftController, 'Shift'))]),
        _field(_weatherController, 'Weather'),
        _field(_crewController, 'Crew Count', keyboardType: TextInputType.number),
        _field(_workController, 'Work Activities Executed', lines: 4),
        Row(children: [Expanded(child: _field(_quantityController, 'Progress Quantity', keyboardType: const TextInputType.numberWithOptions(decimal: true))), const SizedBox(width: 12), Expanded(child: _field(_unitController, 'Unit (m, m², m³, no.)'))]),
        _field(_progressController, 'Overall Progress (%)', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        _field(_qualityController, 'Quality Control / Inspections', lines: 3),
        _field(_hseController, 'HSE Observations / Toolbox / Incidents', lines: 3),
        _field(_issuesController, 'Delays / Issues', lines: 3),
        _field(_instructionsController, 'Site Instructions / Decisions', lines: 3),
        _field(_nextDayController, 'Next-Day Plan', lines: 3),
        _field(_referencesController, 'Drawing / RFI / Document References', lines: 2),
        OutlinedButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.add_a_photo), label: const Text('Add Site Photo')),
        if (_photoPaths.isNotEmpty) SizedBox(height: 100, child: ListView(scrollDirection: Axis.horizontal, children: _photoPaths.map((path) => Padding(padding: const EdgeInsets.only(right: 8, top: 8), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover)))).toList())),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Daily Log')),
      ]),
    );
  }
}
