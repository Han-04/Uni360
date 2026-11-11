import 'package:flutter/foundation.dart';

import '../../../shared/account/account.dart';
import '../../../shared/account/account_controller.dart';
import '../domain/preventive_repository.dart';
import '../domain/verification_service.dart';
import '../domain/work_order.dart';

class PreventiveController extends ChangeNotifier {
  PreventiveController(this.repository, this.verification, this.accounts) {
    accounts.addListener(_onAccountChanged);
  }
  final PreventiveRepository repository;
  final VerificationService verification;
  final AccountController accounts;
  bool get signedIn =>
      accounts.account?.role == AccountRole.worker &&
      accounts.account?.id == repository.workerId;
  final Map<String, LocationReading> _verifiedLocations = {};
  final Set<String> _verifiedQr = {};
  final List<WorkerNotification> _sessionNotifications = [];
  final Map<String, List<TaskEvidence>> previousEvidence = {};
  List<WorkOrder> get orders =>
      signedIn ? repository.workOrdersFor(repository.workerId) : [];
  List<WorkerNotification> get notifications => signedIn
      ? [
          ..._sessionNotifications,
          ...repository.notificationsFor(repository.workerId),
        ]
      : [];
  int get unreadCount => notifications.where((n) => !n.read).length;
  void _onAccountChanged() {
    if (!signedIn) {
      _verifiedLocations.clear();
      _verifiedQr.clear();
    }
  }

  void _own(WorkOrder order) {
    accounts.touch();
    if (!signedIn || !orders.contains(order)) {
      throw StateError('Sign in to access this work order.');
    }
  }

  void _save(WorkOrder order) {
    repository.saveWorkOrder(order);
    notifyListeners();
  }

  bool hasLocation(WorkOrder order) => _verifiedLocations.containsKey(order.id);
  bool hasQr(WorkOrder order) => _verifiedQr.contains(order.id);
  LocationReading? readingFor(WorkOrder order) => _verifiedLocations[order.id];
  Future<void> verifyLocation(WorkOrder order, {bool outside = false}) async {
    _own(order);
    _verifiedLocations.remove(order.id);
    _verifiedQr.remove(order.id);
    final reading = await verification.locate(order.facility, outside: outside);
    _own(order);
    if (!isInsideGeofence(reading, order.facility)) {
      notifyListeners();
      throw StateError(
        'Check-in failed: You are outside the facility geofence or GPS accuracy is insufficient.',
      );
    }
    _verifiedLocations[order.id] = reading;
    notifyListeners();
  }

  Future<void> verifyQr(WorkOrder order, {bool mismatched = false}) async {
    _own(order);
    if (!hasLocation(order)) {
      throw StateError('Verify your location first.');
    }
    _verifiedQr.remove(order.id);
    final token = await verification.scan(
      order.facility,
      mismatched: mismatched,
    );
    _own(order);
    if (token != order.facility.qrToken) {
      notifyListeners();
      throw StateError(
        'Invalid location code. Scan the QR code at the assigned facility.',
      );
    }
    _verifiedQr.add(order.id);
    notifyListeners();
  }

  void start(WorkOrder order) {
    _own(order);
    if (order.status != WorkStatus.assigned ||
        !hasLocation(order) ||
        (order.facility.requiresQr && !hasQr(order))) {
      throw StateError(
        'Complete location and QR verification before starting work.',
      );
    }
    final now = DateTime.now();
    order.checkedInAt = now;
    order.startedAt = now;
    order.status = WorkStatus.inProgress;
    final reading = _verifiedLocations[order.id]!;
    order.history.add(
      WorkEvent(
        'Location and QR verified',
        now,
        detail:
            'Demo GPS ${reading.latitude.toStringAsFixed(5)}, ${reading.longitude.toStringAsFixed(5)} · ±${reading.accuracyMeters.round()} m',
      ),
    );
    order.history.add(WorkEvent('Work started', now));
    _save(order);
  }

  void restartRework(WorkOrder order) {
    _own(order);
    if (order.status != WorkStatus.reworkRequired) {
      throw StateError('This task does not require rework.');
    }
    previousEvidence.putIfAbsent(order.id, () => []).addAll(order.evidence);
    order.evidence.clear();
    for (final item in order.checklist) {
      item.done = false;
    }
    order.attested = false;
    order.notes = '';
    order.checkedInAt = null;
    order.startedAt = null;
    order.submittedAt = null;
    order.status = WorkStatus.assigned;
    _verifiedLocations.remove(order.id);
    _verifiedQr.remove(order.id);
    order.history.add(
      WorkEvent(
        'Rework acknowledged',
        DateTime.now(),
        detail: order.adminRemarks,
      ),
    );
    _save(order);
  }

  void toggleChecklist(WorkOrder order, ChecklistItem item, bool value) {
    _own(order);
    if (!order.isEditable || !order.checklist.contains(item)) {
      throw StateError('Start work before editing the checklist.');
    }
    item.done = value;
    order.attested = false;
    _save(order);
  }

  Future<void> capture(WorkOrder order) async {
    _own(order);
    if (!order.isEditable) {
      throw StateError('Start work before capturing evidence.');
    }
    final evidence = await verification.capture(order.facility);
    _own(order);
    if (!order.isEditable) {
      throw StateError('This work order is no longer editable.');
    }
    order.evidence.add(evidence);
    _save(order);
  }

  void removeEvidence(WorkOrder order, TaskEvidence evidence) {
    _own(order);
    if (!order.isEditable) {
      throw StateError('Submitted evidence cannot be removed.');
    }
    order.evidence.remove(evidence);
    _save(order);
  }

  void saveDraft(WorkOrder order, String notes, bool attested) {
    _own(order);
    if (!order.isEditable) {
      throw StateError('This task is not editable.');
    }
    order.notes = notes.trim();
    order.attested = attested;
    _save(order);
  }

  void submit(WorkOrder order, String notes, bool attested) {
    saveDraft(order, notes, attested);
    if (!order.canSubmit) {
      throw StateError(
        'Complete all checklist items, capture the required evidence, and confirm your work.',
      );
    }
    order.status = WorkStatus.evidenceSubmitted;
    order.submittedAt = DateTime.now();
    order.history.add(
      WorkEvent(
        'Evidence submitted',
        order.submittedAt!,
        detail: 'Awaiting administrator approval',
      ),
    );
    _sessionNotifications.insert(
      0,
      WorkerNotification(
        id: 'N-${DateTime.now().microsecondsSinceEpoch}',
        title: 'Evidence submitted',
        message: '${order.title} is awaiting administrator review.',
        at: order.submittedAt!,
        workOrderId: order.id,
      ),
    );
    _save(order);
  }

  void markRead(WorkerNotification notification) {
    notification.read = true;
    notifyListeners();
  }

  void markAllRead() {
    for (final n in notifications) {
      n.read = true;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    accounts.removeListener(_onAccountChanged);
    super.dispose();
  }
}
