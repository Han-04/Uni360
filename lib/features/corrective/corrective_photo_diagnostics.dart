import 'dart:typed_data';
import 'dart:ui' as ui;

import 'corrective_repository.dart';

/// Checks exposure and contrast and creates a small perceptual fingerprint.
/// The results help reviewers assess evidence and spot possible duplicates.
Future<CorrectiveRow> inspectCorrectivePhoto(Uint8List bytes) async {
  const width = 9;
  const height = 8;
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: width,
    targetHeight: height,
  );
  try {
    final photo = (await codec.getNextFrame()).image;
    try {
      final pixels = await photo.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) return {};
      final light = [
        for (var offset = 0; offset < pixels.lengthInBytes; offset += 4)
          (pixels.getUint8(offset) * 299 +
                  pixels.getUint8(offset + 1) * 587 +
                  pixels.getUint8(offset + 2) * 114) ~/
              1000,
      ];
      final mean = light.reduce((a, b) => a + b) / light.length;
      final variance =
          light.fold<double>(
            0,
            (sum, value) => sum + (value - mean) * (value - mean),
          ) /
          light.length;
      if (mean < 30) return {'quality': 'dark'};
      if (mean > 230) return {'quality': 'bright'};
      if (variance < 120) return {'quality': 'low_contrast'};

      final fingerprint = StringBuffer();
      for (var row = 0; row < height; row++) {
        for (var start = 0; start < width - 1; start += 4) {
          var digit = 0;
          for (var column = start; column < start + 4; column++) {
            final index = row * width + column;
            digit = (digit << 1) | (light[index] > light[index + 1] ? 1 : 0);
          }
          fingerprint.write(digit.toRadixString(16));
        }
      }
      return {'quality': 'clear', 'fingerprint': fingerprint.toString()};
    } finally {
      photo.dispose();
    }
  } finally {
    codec.dispose();
  }
}
