import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS kills the app (TCC privacy violation, SIGABRT) the moment a web page's
/// file picker offers the camera if Info.plist has no usage description.
/// That is how uploading a video in an Instagram chat crashed calm_ig
/// (crash logs from 2026-11-12).
void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();

  String? valueOf(String key) {
    final match = RegExp('<key>$key</key>\\s*<string>([^<]*)</string>')
        .firstMatch(plist);
    return match?.group(1);
  }

  for (final key in [
    // "Take Photo or Video" in the upload picker.
    'NSCameraUsageDescription',
    // Recording a video with sound.
    'NSMicrophoneUsageDescription',
    // Choosing from the library / saving a photo from a chat.
    'NSPhotoLibraryUsageDescription',
    'NSPhotoLibraryAddUsageDescription',
  ]) {
    test('$key is set', () {
      final value = valueOf(key);
      expect(value, isNotNull, reason: '$key missing from Info.plist');
      expect(value!.trim(), isNotEmpty);
    });
  }
}
