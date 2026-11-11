import '../domain/verification_service.dart';
import '../domain/work_order.dart';

/// No permissions or device hardware are used by this demo adapter.
class MockVerificationService implements VerificationService {
  @override
  Future<LocationReading> locate(
    Facility facility, {
    bool outside = false,
  }) async => LocationReading(
    facility.latitude + (outside ? .01 : .00008),
    facility.longitude,
    8,
  );
  @override
  Future<String> scan(Facility facility, {bool mismatched = false}) async =>
      mismatched ? 'UNI360:OTHER-FACILITY' : facility.qrToken;
  @override
  Future<TaskEvidence> capture(Facility facility) async {
    final now = DateTime.now();
    return TaskEvidence(
      id: 'DEMO-${now.microsecondsSinceEpoch}',
      capturedAt: now,
      latitude: facility.latitude,
      longitude: facility.longitude,
    );
  }
}
