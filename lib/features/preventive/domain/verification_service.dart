import 'dart:math';

import 'work_order.dart';

class LocationReading {
  const LocationReading(this.latitude, this.longitude, this.accuracyMeters);
  final double latitude, longitude, accuracyMeters;
}

abstract interface class VerificationService {
  Future<LocationReading> locate(Facility facility, {bool outside = false});
  Future<String> scan(Facility facility, {bool mismatched = false});
  Future<TaskEvidence> capture(Facility facility);
}

double distanceMeters(LocationReading reading, Facility facility) {
  double radians(double degrees) => degrees * pi / 180;
  final lat = radians(facility.latitude - reading.latitude);
  final lon = radians(facility.longitude - reading.longitude);
  final a =
      pow(sin(lat / 2), 2) +
      cos(radians(reading.latitude)) *
          cos(radians(facility.latitude)) *
          pow(sin(lon / 2), 2);
  return 6371000 * 2 * atan2(sqrt(a), sqrt(1 - a));
}

bool isInsideGeofence(LocationReading reading, Facility facility) =>
    reading.accuracyMeters >= 0 &&
    reading.accuracyMeters <= 30 &&
    distanceMeters(reading, facility) + reading.accuracyMeters <=
        facility.radiusMeters;
