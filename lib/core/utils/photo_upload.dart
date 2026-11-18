import 'dart:typed_data';

(String extension, String mime) photoUploadType(Uint8List bytes) {
  bool matches(int offset, List<int> signature) =>
      bytes.length >= offset + signature.length &&
      Iterable<int>.generate(signature.length)
          .every((index) => bytes[offset + index] == signature[index]);

  if (matches(0, [255, 216, 255])) return ('jpg', 'image/jpeg');
  if (matches(0, [137, 80, 78, 71, 13, 10, 26, 10])) {
    return ('png', 'image/png');
  }
  if (matches(0, 'RIFF'.codeUnits) && matches(8, 'WEBP'.codeUnits)) {
    return ('webp', 'image/webp');
  }
  throw const FormatException('Choose a JPG, PNG or WebP photo.');
}
