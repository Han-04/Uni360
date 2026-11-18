import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

typedef CorrectiveRow = Map<String, dynamic>;

const correctiveCategories = [
  'Plumbing',
  'Electrical',
  'Air conditioning',
  'Lift',
  'Furniture',
  'Building',
  'Pest control',
  'Cleaning',
  'Security',
  'Grounds',
  'Other',
];
const correctiveUrgencies = ['Low', 'Medium', 'High', 'Critical'];
bool correctiveHighPriority(String value) =>
    value == 'High' || value == 'Critical';

const correctiveStatuses = {
  'reported': 'Awaiting review',
  'needs_info': 'More information needed',
  'inspection': 'Inspection requested',
  'approved': 'Approved for assignment',
  'merged': 'Linked to an existing case',
  'assigned': 'Assigned',
  'acknowledged': 'Acknowledged',
  'checked_in': 'Checked in',
  'in_progress': 'In progress',
  'submitted': 'Evidence submitted',
  'rework': 'Rework required',
  'rejected': 'Rejected',
  'resolved': 'Resolved',
  'escalated': 'Escalated',
  'external': 'External assistance',
  'dismissed': 'Dismissed',
};

const closedCorrectiveStatuses = {
  'resolved',
  'rejected',
  'dismissed',
  'merged',
};

List<CorrectiveRow> correctiveRows(Object? data) =>
    (data as List? ?? const []).cast<CorrectiveRow>();

class CorrectiveIncident {
  CorrectiveIncident(this.data);
  final CorrectiveRow data;

  String get id => data['id'] as String;
  String get reference => 'CM-${data['reference'].toString().padLeft(4, '0')}';
  String get title => data['title'] as String;
  String get facility => data['facility_name'] as String;
  String get facilityId => data['facility_id'] as String;
  String get location => data['location_detail'] as String;
  String get category => data['category'] as String;
  String get urgency => data['urgency'] as String;
  String get status => data['status'] as String;
  String get statusLabel => data['withdrawn_at'] == null
      ? correctiveStatuses[status] ?? status
      : 'Withdrawn';
  bool get archived => data['archived_at'] != null;
  bool get canEditReport =>
      const {'reported', 'needs_info'}.contains(status) &&
      data['approved_at'] == null;
  String get reporter => data['reporter_name'] as String;
  String get reporterId => data['reporter_id'] as String;
  String? get worker => data['worker_name'] as String?;
  String? get workerId => data['worker_id'] as String?;
  String? get reportPhoto => data['report_photo'] as String?;
  String get description => data['description'] as String;
  DateTime get created => DateTime.parse(data['created_at'] as String);
  DateTime? get due => DateTime.tryParse('${data['due_at']}');
  DateTime? get target => DateTime.tryParse('${data['target_at']}');
  bool get overdue =>
      !closedCorrectiveStatuses.contains(status) &&
      (target?.isBefore(DateTime.now()) ?? false);
  DateTime? get resolved => DateTime.tryParse('${data['resolved_at']}');
  int get attempt => data['attempt'] as int;
  List<String> get checklist => (data['checklist'] as List).cast<String>();
}

class CorrectiveDetail {
  const CorrectiveDetail(this.incident, this.events, this.visits, this.photos);
  final CorrectiveIncident incident;
  final List<CorrectiveRow> events, visits, photos;

  CorrectiveRow? get visit {
    for (final row in visits) {
      if (row['attempt'] == incident.attempt) return row;
    }
    return null;
  }
}

class CorrectiveRepository {
  CorrectiveRepository(this.client, {this._actorId});
  final SupabaseClient client;
  final String? _actorId;
  static const _bucket = 'corrective-evidence';
  static const _uuid = Uuid();
  SupabaseQuerySchema get _maintenance => client.schema('maintenance_api');

  String newId() => _uuid.v4();

  Future<CorrectiveRow> catalog() async =>
      await client.rpc('corrective_catalog') as CorrectiveRow;

  Future<List<CorrectiveRow>> categories() =>
      _maintenance.from('corrective_category').select().order('name');

  Future<void> saveCategory(
    String name,
    CorrectiveRow values, {
    required bool creating,
  }) async {
    final table = _maintenance.from('corrective_category');
    if (creating) {
      await table.insert({'name': name, ...values});
    } else {
      await table.update(values).eq('name', name);
    }
  }

  Future<String> lookupFacility(String qr) async =>
      await client.rpc('corrective_lookup_qr', params: {'code': qr}) as String;

  Future<void> reporterAction(
    String id,
    String command,
    CorrectiveRow payload,
  ) async {
    await client.rpc(
      'corrective_reporter',
      params: {'target': id, 'command': command, 'payload': payload},
    );
  }

  Future<List<CorrectiveRow>> notifications() => _maintenance
      .from('corrective_notification')
      .select()
      .order('id', ascending: false)
      .limit(100);

  Future<int> unreadNotifications() async => await _maintenance
      .from('corrective_notification')
      .count(CountOption.exact)
      .isFilter('read_at', null);

  Future<void> markRead(int id) async {
    final readAt = await client.rpc<String?>(
      'mark_corrective_notification_read',
      params: {'notification_id': id},
    );
    if (readAt == null) {
      throw const FormatException('This notification is no longer available.');
    }
  }

  Future<List<CorrectiveIncident>> list(
    String actor, {
    bool admin = false,
  }) async {
    final reports = <CorrectiveRow>[];
    int? before;
    const pageSize = 500;
    while (true) {
      var query = client.from('corrective_incident').select();
      if (!admin) query = query.or('reporter_id.eq.$actor,worker_id.eq.$actor');
      if (before != null) query = query.lt('reference', before);
      final page = await query
          .order('reference', ascending: false)
          .limit(pageSize);
      reports.addAll(page);
      if (page.length < pageSize) break;
      before = page.last['reference'] as int;
    }
    reports.sort(
      (a, b) =>
          (b['updated_at'] as String).compareTo(a['updated_at'] as String),
    );
    return reports.map(CorrectiveIncident.new).toList();
  }

  RealtimeChannel watch(
    String listener,
    void Function() onChange, {
    String? incidentId,
  }) {
    final channel = client
        .channel('corrective-$listener-${newId()}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'corrective_incident',
          filter: incidentId == null
              ? null
              : PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'id',
                  value: incidentId,
                ),
          callback: (_) => onChange(),
        );
    final recipientId = _actorId ?? client.auth.currentUser?.id;
    if (incidentId == null && recipientId != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'uni360_data',
        table: 'maintenance_activity',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'recipient_id',
          value: recipientId,
        ),
        callback: (_) => onChange(),
      );
    }
    return channel.subscribe();
  }

  Future<void> unwatch(RealtimeChannel channel) async {
    await client.removeChannel(channel);
  }

  Future<CorrectiveDetail> detail(String id) async {
    final results = await Future.wait([
      client.from('corrective_incident').select().eq('id', id).single(),
      _maintenance
          .from('corrective_event')
          .select()
          .eq('incident_id', id)
          .order('id', ascending: false),
      _maintenance
          .from('corrective_visit')
          .select()
          .eq('incident_id', id)
          .order('attempt', ascending: false),
      _maintenance
          .from('corrective_photo')
          .select()
          .eq('incident_id', id)
          .order('captured_at'),
      _maintenance.from('corrective_position').select().eq('incident_id', id),
    ]);
    final positions = {
      for (final position in correctiveRows(results[4]))
        position['attempt']: position,
    };
    return CorrectiveDetail(
      CorrectiveIncident(results[0] as CorrectiveRow),
      correctiveRows(results[1]),
      [
        for (final visit in correctiveRows(results[2]))
          {...visit, ...?positions[visit['attempt']]},
      ],
      correctiveRows(results[3]),
    );
  }

  Future<CorrectiveRow> adminOptions(String id) async =>
      await client.rpc('corrective_admin_options', params: {'target': id})
          as CorrectiveRow;

  Future<void> action(
    String id,
    String command, {
    bool admin = false,
    CorrectiveRow payload = const {},
  }) async {
    await client.rpc(
      admin ? 'corrective_admin' : 'corrective_worker',
      params: {'target': id, 'command': command, 'payload': payload},
    );
  }

  Future<CorrectiveRow> verifyLocation(
    String id,
    CorrectiveRow position,
  ) async => await client.rpc(
    'corrective_location',
    params: {'target': id, 'payload': position},
  ) as CorrectiveRow;

  Future<CorrectiveRow?> site(String id) => _maintenance
      .from('corrective_site')
      .select()
      .eq('facility_id', id)
      .maybeSingle();

  Future<CorrectiveRow> saveSite(String id, CorrectiveRow payload) async =>
      await client.rpc(
        'corrective_configure_site',
        params: {'target': id, 'payload': payload},
      ) as CorrectiveRow;

  Future<String> photoUrl(String path) =>
      client.storage.from(_bucket).createSignedUrl(path, 90);

  Future<void> report(CorrectiveRow report, {String? photo}) async {
    await client.rpc(
      'corrective_report',
      params: {
        'payload': {...report, 'photo': photo},
      },
    );
  }

  Future<String> reportReference(String id) async {
    final row = await client
        .from('corrective_incident')
        .select('reference')
        .eq('id', id)
        .single();
    return 'CM-${row['reference'].toString().padLeft(4, '0')}';
  }

  Future<String> upload(
    String id,
    Uint8List bytes, {
    required bool report,
  }) async {
    final actor = _actorId ?? client.auth.currentUser?.id;
    if (actor == null) throw const CorrectiveException('Sign in to continue.');
    if (bytes.length > 10485760) {
      throw const CorrectiveException(
        'Choose a photograph smaller than 10 MB.',
      );
    }
    final (extension, mimeType) = switch (bytes) {
      [0xff, 0xd8, 0xff, ...] => ('jpg', 'image/jpeg'),
      [0x89, 0x50, 0x4e, 0x47, ...] => ('png', 'image/png'),
      [0x52, 0x49, 0x46, 0x46, _, _, _, _, 0x57, 0x45, 0x42, 0x50, ...] => (
        'webp',
        'image/webp',
      ),
      _ => throw const CorrectiveException(
        'Use a JPEG, PNG or WebP photograph.',
      ),
    };
    final path =
        '$actor/$id/${report ? 'report' : 'work'}/${newId()}.$extension';
    await client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );
    return path;
  }

  Future<void> discardDraft(String path) async {
    try {
      await client.storage.from(_bucket).remove([path]);
    } on Exception {
      // The evidence may already have been committed or the device is offline.
    }
  }
}

class CorrectiveException implements Exception {
  const CorrectiveException(this.message);
  final String message;
}

String correctiveError(Object error) => switch (error) {
  CorrectiveException(:final message) => message,
  PostgrestException(code: 'PGRST202' || 'PGRST205' || '42P01') => 'Corrective Maintenance is unavailable. Ask your administrator to apply its Supabase migration.',
  PostgrestException(code: '42501') =>
    'Your account cannot access this record or action.',
  PostgrestException(code: 'P0001', :final message) => message,
  PostgrestException(code: '23514' || '22P02' || '23502') =>
    'Check the required values and try again.',
  StorageException() =>
    'The photograph could not be saved or opened. Try again.',
  _ => 'Could not connect to Uni360. Check your connection and try again.',
};
