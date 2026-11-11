import '../domain/preventive_repository.dart';
import '../domain/work_order.dart';

class MockPreventiveRepository implements PreventiveRepository {
  MockPreventiveRepository({required this.workerId, DateTime? now}) {
    final day = now ?? DateTime.now();
    DateTime at(int offset, int hour) =>
        DateTime(day.year, day.month, day.day + offset, hour);
    const facilities = [
      Facility(
        id: 'FAC-A01',
        name: 'Engineering Block A',
        location: 'Level 2 · AHU room',
        assetTag: 'AC-A-201',
        latitude: 3.2154,
        longitude: 101.7282,
        radiusMeters: 100,
        qrToken: 'UNI360:FAC-A01:AC-A-201',
      ),
      Facility(
        id: 'FAC-L02',
        name: 'Main Library',
        location: 'Ground floor · Electrical room',
        assetTag: 'DB-L-001',
        latitude: 3.2161,
        longitude: 101.7291,
        radiusMeters: 80,
        qrToken: 'UNI360:FAC-L02:DB-L-001',
      ),
      Facility(
        id: 'FAC-H03',
        name: 'Hostel C',
        location: 'Level 1 · Pump room',
        assetTag: 'PMP-C-01',
        latitude: 3.2173,
        longitude: 101.7302,
        radiusMeters: 75,
        qrToken: 'UNI360:FAC-H03:PMP-C-01',
      ),
    ];
    WorkOrder task(
      String id,
      String title,
      int facility,
      int offset,
      int hour,
      WorkStatus status,
      TaskPriority priority,
      List<String> checks,
      String category,
    ) {
      final start = at(offset, hour);
      final order = WorkOrder(
        id: id,
        workerId: workerId,
        title: title,
        category: category,
        frequency: 'Monthly',
        facility: facilities[facility],
        scheduledAt: start,
        dueAt: start.add(const Duration(hours: 2)),
        estimatedMinutes: 45,
        priority: priority,
        status: status,
        instructions: 'Follow the site safety procedure. Isolate equipment where required, complete every inspection, and record clear evidence of the final condition.',
        checklist: [
          for (var i = 0; i < checks.length; i++)
            ChecklistItem('$id-$i', checks[i]),
        ],
        history: [
          WorkEvent(
            'Assigned',
            at(offset - 1, 16),
            detail: 'Assigned by Nur Aina · Facilities Administrator',
          ),
        ],
      );
      if (status != WorkStatus.assigned && status != WorkStatus.pending) {
        order.checkedInAt = start;
        order.startedAt = start.add(const Duration(minutes: 2));
        order.history.addAll([
          WorkEvent('Location and QR verified', start),
          WorkEvent('Work started', order.startedAt!),
        ]);
      }
      if ([
        WorkStatus.evidenceSubmitted,
        WorkStatus.completed,
        WorkStatus.reworkRequired,
        WorkStatus.rejected,
      ].contains(status)) {
        for (final item in order.checklist) {
          item.done = true;
        }
        order.attested = true;
        order.submittedAt = start.add(const Duration(minutes: 42));
        order.notes = 'Scheduled inspection performed. Readings recorded and work area made safe.';
        for (var i = 0; i < order.requiredPhotos; i++) {
          order.evidence.add(
            TaskEvidence(
              id: '$id-photo-$i',
              capturedAt: start.add(Duration(minutes: 35 + i)),
              latitude: order.facility.latitude,
              longitude: order.facility.longitude,
            ),
          );
        }
        order.history.add(WorkEvent('Evidence submitted', order.submittedAt!));
      }
      if (status == WorkStatus.completed) {
        order.adminRemarks = 'Inspection evidence approved. Thank you.';
        order.history.add(
          WorkEvent(
            'Approved',
            start.add(const Duration(hours: 1)),
            detail: order.adminRemarks,
          ),
        );
      }
      if (status == WorkStatus.reworkRequired) {
        order.adminRemarks = 'Please repeat the pressure test and provide a clear photo of the gauge reading. Check for seepage at the outlet joint.';
        order.history.add(
          WorkEvent(
            'Rework requested',
            start.add(const Duration(hours: 1)),
            detail: order.adminRemarks,
          ),
        );
      }
      if (status == WorkStatus.rejected) {
        order.adminRemarks = 'Incorrect asset inspected. Contact the administrator for reassignment.';
        order.history.add(
          WorkEvent(
            'Rejected',
            start.add(const Duration(hours: 1)),
            detail: order.adminRemarks,
          ),
        );
      }
      return order;
    }

    _orders = [
      task(
        'PM-2026-0101',
        'Air-conditioning service',
        0,
        0,
        9,
        WorkStatus.assigned,
        TaskPriority.high,
        [
          'Isolate unit and inspect connections',
          'Clean air filters and drainage tray',
          'Check refrigerant and operating temperature',
          'Restore supply and test operation',
        ],
        'HVAC',
      ),
      task(
        'PM-2026-0102',
        'Distribution board inspection',
        1,
        0,
        11,
        WorkStatus.inProgress,
        TaskPriority.medium,
        [
          'Inspect enclosure and safety labels',
          'Check for overheating and loose connections',
          'Record voltage readings',
          'Clean and secure the electrical room',
        ],
        'Electrical',
      ),
      task(
        'PM-2026-0098',
        'Water pump pressure test',
        2,
        -1,
        10,
        WorkStatus.reworkRequired,
        TaskPriority.high,
        [
          'Inspect pump and outlet joints',
          'Test operating pressure',
          'Record gauge readings',
          'Check for leaks after restart',
        ],
        'Plumbing',
      ),
      task(
        'PM-2026-0103',
        'Emergency lighting test',
        1,
        1,
        9,
        WorkStatus.assigned,
        TaskPriority.medium,
        [
          'Inspect emergency lights',
          'Test battery operation',
          'Record failed fittings',
        ],
        'Electrical',
      ),
      task(
        'PM-2026-0096',
        'Ventilation filter inspection',
        0,
        -1,
        14,
        WorkStatus.evidenceSubmitted,
        TaskPriority.low,
        [
          'Inspect filter condition',
          'Clean accessible surfaces',
          'Record airflow',
        ],
        'HVAC',
      ),
      task(
        'PM-2026-0091',
        'Pump room safety inspection',
        2,
        -2,
        9,
        WorkStatus.completed,
        TaskPriority.medium,
        [
          'Inspect signage and access',
          'Check isolation switch',
          'Clear walkways',
        ],
        'Safety',
      ),
      task(
        'PM-2026-0088',
        'Asset label verification',
        0,
        -3,
        9,
        WorkStatus.rejected,
        TaskPriority.low,
        ['Confirm asset identifier', 'Inspect label condition'],
        'Inspection',
      ),
    ];
    _notifications = [
      WorkerNotification(
        id: 'N1',
        title: 'Rework requested',
        message: 'Water pump pressure test needs new evidence. Read the administrator’s remarks.',
        at: at(0, 8),
        workOrderId: 'PM-2026-0098',
      ),
      WorkerNotification(
        id: 'N2',
        title: 'New preventive assignment',
        message: 'Air-conditioning service is on your schedule today.',
        at: at(0, 7),
        workOrderId: 'PM-2026-0101',
      ),
      WorkerNotification(
        id: 'N3',
        title: 'Work approved',
        message: 'Your pump room safety inspection has been approved.',
        at: at(-1, 15),
        workOrderId: 'PM-2026-0091',
        read: true,
      ),
      WorkerNotification(
        id: 'N4',
        title: 'Evidence rejected',
        message: 'Asset label verification was rejected. Contact your administrator.',
        at: at(-2, 10),
        workOrderId: 'PM-2026-0088',
      ),
    ];
  }
  @override
  final String workerId;
  late final List<WorkOrder> _orders;
  late final List<WorkerNotification> _notifications;
  @override
  List<WorkOrder> workOrdersFor(String workerId) =>
      List.unmodifiable(_orders.where((o) => o.workerId == workerId));
  @override
  List<WorkerNotification> notificationsFor(String workerId) =>
      workerId == this.workerId ? List.unmodifiable(_notifications) : [];

  @override
  void saveWorkOrder(WorkOrder order) {
    if (!_orders.contains(order) || order.workerId != workerId) {
      throw StateError('This work order is not assigned to you.');
    }
  }
}
