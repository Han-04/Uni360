import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class CampusPosition {
  const CampusPosition(
    this.latitude,
    this.longitude,
    this.accuracy,
    this.timestamp,
  );

  final double latitude, longitude, accuracy;
  final DateTime timestamp;

  Map<String, dynamic> toParams() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'fix_at': timestamp.toUtc().toIso8601String(),
  };
}

bool get supportsCampusCapture =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<CampusPosition> readCampusPosition() async {
  if (!supportsCampusCapture) {
    throw const FormatException(
      'Open Uni360 on Android or iOS to verify your campus location.',
    );
  }
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const FormatException(
      'Turn on your device’s location services and try again.',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    throw const FormatException(
      'Allow precise location for Uni360 in device settings and try again.',
    );
  }

  final Position position;
  try {
    position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  } on TimeoutException {
    throw const FormatException(
      'No GPS reading yet. Move to an open area and try again.',
    );
  }
  if (position.isMocked) {
    throw const FormatException(
      'Turn off simulated locations and use your device’s GPS.',
    );
  }
  return CampusPosition(
    position.latitude,
    position.longitude,
    position.accuracy,
    position.timestamp,
  );
}
