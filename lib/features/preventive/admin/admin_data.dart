import 'package:supabase_flutter/supabase_flutter.dart';

typedef AdminRow = Map<String, dynamic>;

List<AdminRow> adminRows(Object? value) =>
    (value as List? ?? const []).cast<AdminRow>();

const facilityFields =
    'id,name,parent_id,facility_type,metadata,is_active,effective_active:preventive_facility_is_active';
const taskFields =
    'id,title,category,zone_id,instructions,required_job_role,checklist,is_active,duration_minutes';
const orderFields =
    'id,title,worker_id,scheduled_for,due_at,status,preventive_work_order_target(facility_path)';

String adminError(Object error) => switch (error) {
  PostgrestException(:final code, :final message)
      when ['23514', '23503', '23505', '42501', '22023'].contains(code) =>
    message,
  PostgrestException(:final code) when code?.startsWith('PGRST20') == true =>
    'This page needs the current Uni360 database migrations.',
  FormatException(:final message) => message,
  _ => 'Uni360 could not complete the request. Please try again.',
};

class AdminData {
  const AdminData(this.client);

  final SupabaseClient client;

  SupabaseQueryBuilder table(String name) =>
      client.schema('maintenance_api').from(name);

  Future<AdminRow> accounts(String action, AdminRow values) async {
    if (action == 'list') {
      return await client.rpc(
        'list_managed_accounts',
        params: {
          'search_text': values['search'],
          'page_number': values['page'],
          'active_filter': switch (values['status']) {
            'active' => true,
            'inactive' => false,
            _ => null,
          },
        },
      ) as AdminRow;
    }
    try {
      final response = await client.functions.invoke(
        'manage-accounts',
        body: {'action': action, ...values},
      );
      return response.data as AdminRow;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw FormatException(details['error'] as String);
      }
      rethrow;
    }
  }

  Future<List<AdminRow>> all(
    PostgrestFilterBuilder<PostgrestList> query,
    String order,
    String id,
  ) async {
    const size = 500;
    final rows = <AdminRow>[];
    for (var index = 0; ; index += size) {
      final batch = await query
          .order(order, ascending: true)
          .order(id, ascending: true)
          .range(index, index + size - 1);
      rows.addAll(batch);
      if (batch.length < size) return rows;
    }
  }

  Future<void> write(
    PostgrestFilterBuilder<dynamic> query, [
    String id = 'id',
  ]) async {
    if (await query.select(id).maybeSingle() == null) {
      throw const FormatException(
        'This record has changed or is unavailable. Refresh and try again.',
      );
    }
  }

  Future<List<AdminRow>> facilities() =>
      all(table('preventive_facility').select(facilityFields), 'name', 'id');

  Future<List<AdminRow>> zones() =>
      all(table('preventive_zone').select('id,name'), 'name', 'id');

  Future<List<String>> scheduledTaskNames() async {
    final orders = await all(
      table('preventive_work_order')
          .select('id,title')
          .isFilter('cancelled_at', null),
      'title',
      'id',
    );
    return orders.map((order) => order['title'] as String).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<List<AdminRow>> scheduledTasksOn(String title, DateTime date) => all(
    table('preventive_work_order')
        .select(orderFields)
        .eq('title', title)
        .isFilter('cancelled_at', null)
        .gte('scheduled_for', midnight(date))
        .lt(
          'scheduled_for',
          midnight(DateTime.utc(date.year, date.month, date.day + 1)),
        ),
    'scheduled_for',
    'id',
  );

  Future<List<AdminRow>> workers([String search = '', int page = 0]) async =>
      adminRows(
        await client.rpc(
          'workforce_directory',
          params: {'search_text': search, 'start_at': page * 25},
        ),
      );

  Future<Map<String, AdminRow>> workerDirectory() async {
    final result = <String, AdminRow>{};
    for (var page = 0; ; page++) {
      final batch = await workers('', page);
      for (final worker in batch.take(25)) {
        result[worker['worker_id'] as String] = worker;
      }
      if (batch.length <= 25) return result;
    }
  }
}

String workerLabel(AdminRow? row) => row == null
    ? 'Assigned worker'
    : '${row['full_name']} · ${row['employee_id']}';

String orderLocation(AdminRow row) =>
    (adminRows(row['preventive_work_order_target'])
            .map((target) => target['facility_path'] as String)
            .toList()
          ..sort())
        .join(', ');

String orderStatus(AdminRow row) => switch (row['status']) {
  'in_progress' => 'In progress',
  'submitted' => 'Awaiting approval',
  'completed' => 'Completed',
  _ => 'Assigned',
};

DateTime malaysiaDateTime(Object value) =>
    DateTime.parse('$value').toUtc().add(const Duration(hours: 8));

DateTime adminToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 8));
  return DateTime.utc(now.year, now.month, now.day);
}

DateTime adminDay(Object value) {
  final date = malaysiaDateTime(value);
  return DateTime.utc(date.year, date.month, date.day);
}

String isoDate(DateTime date) => date.toIso8601String().substring(0, 10);
String midnight(DateTime date) => '${isoDate(date)}T00:00:00+08:00';
String malaysiaClock(Object value) =>
    malaysiaDateTime(value).toIso8601String().substring(11, 16);
String malaysiaStamp(Object value) =>
    '${isoDate(adminDay(value))} · ${malaysiaClock(value)}';
String scheduleTime(
  AdminRow row, {
  String start = 'scheduled_for',
  String end = 'due_at',
}) {
  final first = row[start] as String;
  final last = row[end] as String;
  final until = adminDay(first) == adminDay(last)
      ? malaysiaClock(last)
      : malaysiaStamp(last);
  return '${malaysiaClock(first)}–$until';
}
