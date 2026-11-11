enum WorkStatus {
  pending('Pending'),
  assigned('Assigned'),
  inProgress('In progress'),
  evidenceSubmitted('Under review'),
  reworkRequired('Rework required'),
  rejected('Rejected'),
  completed('Completed');

  const WorkStatus(this.label);
  final String label;
}

enum TaskPriority {
  high('High'),
  medium('Medium'),
  low('Low');

  const TaskPriority(this.label);
  final String label;
}

class Facility {
  const Facility({
    required this.id,
    required this.name,
    required this.location,
    required this.assetTag,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.qrToken,
    this.requiresQr = true,
  });
  final String id, name, location, assetTag, qrToken;
  final double latitude, longitude, radiusMeters;
  final bool requiresQr;
}

class ChecklistItem {
  ChecklistItem(this.id, this.label, {this.done = false});
  final String id, label;
  bool done;
}

/// A simulated capture is deliberately distinct from a real device photograph.
class TaskEvidence {
  const TaskEvidence({
    required this.id,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
    this.isSimulated = true,
  });
  final String id;
  final DateTime capturedAt;
  final double latitude, longitude;
  final bool isSimulated;
}

class WorkEvent {
  const WorkEvent(this.label, this.at, {this.detail});
  final String label;
  final DateTime at;
  final String? detail;
}

class WorkOrder {
  WorkOrder({
    required this.id,
    required this.workerId,
    required this.title,
    required this.category,
    required this.frequency,
    required this.instructions,
    required this.facility,
    required this.scheduledAt,
    required this.dueAt,
    required this.estimatedMinutes,
    required this.priority,
    required this.checklist,
    required this.history,
    this.requiredPhotos = 2,
    this.status = WorkStatus.assigned,
    this.adminRemarks,
    this.startedAt,
    this.checkedInAt,
    this.submittedAt,
    this.notes = '',
    this.attested = false,
  });
  final String id, workerId, title, category, frequency, instructions;
  final Facility facility;
  final DateTime scheduledAt, dueAt;
  final int estimatedMinutes, requiredPhotos;
  final TaskPriority priority;
  final List<ChecklistItem> checklist;
  final List<WorkEvent> history;
  final List<TaskEvidence> evidence = [];
  WorkStatus status;
  String? adminRemarks;
  DateTime? startedAt, checkedInAt, submittedAt;
  String notes;
  bool attested;
  bool get isEditable => status == WorkStatus.inProgress;
  bool get isOverdue =>
      dueAt.isBefore(DateTime.now()) &&
      [
        WorkStatus.assigned,
        WorkStatus.inProgress,
        WorkStatus.reworkRequired,
      ].contains(status);
  int get completedItems => checklist.where((item) => item.done).length;
  bool get canSubmit =>
      isEditable &&
      checkedInAt != null &&
      completedItems == checklist.length &&
      evidence.length >= requiredPhotos &&
      attested;
}

class WorkerNotification {
  WorkerNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.at,
    this.workOrderId,
    this.read = false,
  });
  final String id, title, message;
  final String? workOrderId;
  final DateTime at;
  bool read;
}
