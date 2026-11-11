import 'work_order.dart';

/// Replace this implementation with an API/database adapter at the app root.
/// The backend must also enforce worker ownership and valid status transitions.
abstract interface class PreventiveRepository {
  String get workerId;
  List<WorkOrder> workOrdersFor(String workerId);
  List<WorkerNotification> notificationsFor(String workerId);
  void saveWorkOrder(WorkOrder order);
}
