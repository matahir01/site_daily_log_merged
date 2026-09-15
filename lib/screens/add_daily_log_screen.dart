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
import '../services/daily_site_report_store.dart';
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
  final _reportNoController = TextEditingController();
  final _progressQuantityController = TextEditingController();
  final _progressUnitController = TextEditingController();
  final _progressPercentController = TextEditingController();
  final _qualityController = TextEditingController();
  final _hseController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _nextDayPlanController = TextEditingController();
  final _documentsController = TextEditingController();
  final _preparedByController = TextEditingController();
  final _positionController = TextEditingController(text: 'Site/Design Engineer');
  final _reviewedByController = TextEditingController();
  final _approvedByController = TextEditingController();
  final List<String> _photoPaths = [];
  String _shift = 'Day';
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _weatherController,
      _crewController,
      _workController,
      _issuesController,
      _reportNoController,
      _progressQuantityController,
      _progressUnitController,
      _progressPercentController,
      _qualityController,
      _hseController,
      _instructionsController,
      _nextDayPlanController,
      _documentsController,
      _preparedByController,
      _positionController,
      _reviewedByController,
      _approvedByController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullable(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (file == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${const Uuid().v4()}${p.extension(file.path)}';
    final rawPath = p.join(appDir.path, 'photos', fileName);
    await Directory(p.join(appDir.path, 'photos')).create(recursive: true);

    final compressed = await ImageCompressionService.compressAndSave(
      sourcePath: file.path,
      destinationPath: rawPath,
    );

    if (widget.siteName != null) {
      final watermarked = await PhotoWatermarkService.watermarkPhoto(
        imagePath: compressed.path,
        siteName: widget.siteName!,
      );
      if (mounted) setState(() => _photoPaths.add(watermarked.path));
    } else {
      if (mounted) setState(() => _photoPaths.add(compressed.path));
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
    final percent = double.tryParse(_progressPercentController.text.trim());
    if (percent != null && (percent < 0 || percent > 100)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Progress percentage must be between 0 and 100.')),
      );
      return;
    }
    final crew = int.tryParse(_crewController.text.trim());
    if (crew != null && crew < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crew count cannot be negative.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final position = await _tryGetLocation();
      final id = const Uuid().v4();
      final log = DailyLog(
        id: id,
        siteId: widget.siteId,
        date: DateTime.now(),
        weather: _nullable(_weatherController),
        crewCount: crew,
        workCompleted: _nullable(_workController),
        issues: _nullable(_issuesController),
        photoPaths: _photoPaths,
        lat: position?.latitude,
        lng: position?.longitude,
      );

      await DatabaseHelper.instance.insertDailyLog(log);
      await DailySiteReportStore.instance.upsert(
        DailySiteReportMeta(
          dailyLogId: id,
          reportNo: _nullable(_reportNoController),
          shift: _shift,
          progressQuantity: _nullable(_progressQuantityController),
          progressUnit: _nullable(_progressUnitController),
          percentComplete: percent,
          qualityInspections: _nullable(_qualityController),
          hseObservations: _nullable(_hseController),
          siteInstructions: _nullable(_instructionsController),
          nextDayPlan: _nullable(_nextDayPlanController),
          documentReferences: _nullable(_documentsController),
          preparedBy: _nullable(_preparedByController),
          preparedByPosition: _nullable(_positionController),
          reviewedBy: _nullable(_reviewedByController),
          approvedBy: _nullable(_approvedByController),
        ),
      );

      GoogleSheetsService.autoSyncSite(widget.siteId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save daily log: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Daily Site Log')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            title: 'Daily overview',
            icon: Icons.today_outlined,
            child: Column(
              children: [
                TextField(
                  controller: _weatherController,
                  decoration: const InputDecoration(labelText: 'Weather', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _crewController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Reported crew count', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _shift,
                  decoration: const InputDecoration(labelText: 'Shift', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Day', child: Text('Day')),
                    DropdownMenuItem(value: 'Night', child: Text('Night')),
                  ],
                  onChanged: (value) => setState(() => _shift = value ?? 'Day'),
                ),
              ],
            ),
          ),
          _sectionCard(
            title: 'Work & progress',
            icon: Icons.engineering_outlined,
            child: Column(
              children: [
                TextField(
                  controller: _workController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Work completed / activities executed',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _progressQuantityController,
                        decoration: const InputDecoration(labelText: 'Measured quantity', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _progressUnitController,
                        decoration: const InputDecoration(labelText: 'Unit', hintText: 'm³, m, nr', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _progressPercentController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Overall / activity progress (%)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _issuesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Issues / delays', alignLabelWithHint: true, border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          _sectionCard(
            title: 'Quality, safety & instructions',
            icon: Icons.fact_check_outlined,
            child: Column(
              children: [
                TextField(
                  controller: _qualityController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Quality control / inspections', alignLabelWithHint: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hseController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'HSE observations / toolbox talk / incidents', alignLabelWithHint: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _instructionsController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Site instructions', alignLabelWithHint: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nextDayPlanController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Next-day plan', alignLabelWithHint: true, border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          _sectionCard(
            title: 'Report references & sign-off',
            icon: Icons.description_outlined,
            child: Column(
              children: [
                TextField(
                  controller: _reportNoController,
                  decoration: const InputDecoration(labelText: 'Report no. (optional — auto-generated if blank)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _documentsController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Drawing / RFI / inspection / document references', alignLabelWithHint: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _preparedByController,
                  decoration: const InputDecoration(labelText: 'Prepared by', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _positionController,
                  decoration: const InputDecoration(labelText: 'Position', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reviewedByController,
                  decoration: const InputDecoration(labelText: 'Reviewed by (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _approvedByController,
                  decoration: const InputDecoration(labelText: 'Approved / noted by (optional)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          _sectionCard(
            title: 'Site photographs',
            icon: Icons.photo_camera_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Capture Site Photo'),
                ),
                if (_photoPaths.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 100,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _photoPaths.map((path) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover),
                            ),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: IconButton.filledTonal(
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                onPressed: () => setState(() => _photoPaths.remove(path)),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save Daily Log'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
