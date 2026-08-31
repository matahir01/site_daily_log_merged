import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Stamps GPS coordinates, site name, and date/time onto a photo.
/// Intended to run **after** [ImageCompressionService.compressAndSave] so the
/// watermark is applied to the final compressed image.
class PhotoWatermarkService {
  static Future<File> watermarkPhoto({
    required String imagePath,
    required String siteName,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
    } catch (_) {
      // GPS unavailable — continue without coordinates
    }

    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final gpsStr = position != null
        ? 'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}'
        : 'GPS: Unavailable';

    final lines = [siteName, '$dateStr | $timeStr', gpsStr];

    final barHeight = 28 * lines.length + 16;
    final yStart = image.height - barHeight;

    for (int y = yStart; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;
        image.setPixel(
          x,
          y,
          img.ColorRgba8(
            (r * 0.3).toInt(),
            (g * 0.3).toInt(),
            (b * 0.3).toInt(),
            200,
          ),
        );
      }
    }

    final font = img.arial14;
    for (int i = 0; i < lines.length; i++) {
      img.drawString(
        image,
        lines[i],
        font: font,
        x: 16,
        y: yStart + 8 + (i * 24),
        color: img.ColorRgba8(255, 255, 255, 255),
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'wm_${now.millisecondsSinceEpoch}.png';
    final outPath = p.join(dir.path, fileName);
    final file = File(outPath);
    await file.writeAsBytes(img.encodePng(image));
    return file;
  }
}
