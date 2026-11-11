import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef AssignedWorkLoader = Future<List<AssignedWork>> Function(
  String workerId,
  DateTime? date,
);

DateTime malaysiaTime(DateTime time) =>
    time.toUtc().add(const Duration(hours: 8));

DateTime malaysiaToday() {
  final now = malaysiaTime(DateTime.now());
  return DateTime(now.year, now.month, now.day);
}

class AssignedWork {
  const AssignedWork({
    required this.id,
    required this.title,
    required this.instructions,
    required this.starts,
    required this.ends,
    required this.locations,
    required this.checklist,
    this.status = AssignedWorkStatus.assigned,
    this.checkedItems = const {},
    this.photoPaths = const [],
    this.notes = '',
    this.feedback = '',
  });

  final String id, title, instructions;
  final DateTime starts, ends;
  final List<String> locations, checklist;
  final AssignedWorkStatus status;
  final Set<int> checkedItems;
  final List<String> photoPaths;
  final String notes, feedback;
}

enum AssignedWorkStatus {
  assigned('assigned', 'Assigned'),
  inProgress('in_progress', 'In progress'),
  submitted('submitted', 'Awaiting approval'),
  completed('completed', 'Completed');

  const AssignedWorkStatus(this.value, this.label);
  final String value, label;
}

abstract interface class AssignedWorkActions {
  Future<AssignedWork> loadOrder(String workerId, String orderId);
  Future<void> start(String orderId);
  Future<void> checkItem(String orderId, int index, bool checked);
  Future<void> attachPhoto(String workerId, String orderId, Uint8List bytes);
  Future<void> submit(String orderId, String notes);
  Future<String> photoUrl(String path);
}

class AssignedWorkRepository implements AssignedWorkActions {
  const AssignedWorkRepository(this._client);
  final SupabaseClient _client;
  static const _fields = '''
    id,title,instructions,checklist,scheduled_for,due_at,status,checked_items,worker_notes,review_note,
    preventive_work_order_target(facility_path),preventive_work_evidence(path)
  ''';
  static const maxPhotoBytes = 10485760;
  static const _bucket = 'preventive-work-evidence';

  void _requireWorker(String workerId) {
    if (_client.auth.currentUser?.id != workerId) {
      throw StateError('Sign in to view assigned work.');
    }
  }

  PostgrestFilterBuilder<PostgrestList> _orders(String workerId) => _client
      .from('preventive_work_order')
      .select(_fields)
      .eq('worker_id', workerId)
      .isFilter('cancelled_at', null);

  Future<List<AssignedWork>> load(String workerId, DateTime? date) async {
    _requireWorker(workerId);
    final start = date == null
        ? null
        : DateTime.utc(
            date.year,
            date.month,
            date.day,
          ).subtract(const Duration(hours: 8));
    final result = <AssignedWork>[];
    const pageSize = 250;
    for (var offset = 0; ; offset += pageSize) {
      var query = _orders(workerId);
      if (start != null) {
        query = query
            .gte('scheduled_for', start.toIso8601String())
            .lt(
              'scheduled_for',
              start.add(const Duration(days: 1)).toIso8601String(),
            );
      }
      final rows = await query
          .order('scheduled_for', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1);
      _requireWorker(workerId);
      result.addAll(rows.map(_parse));
      if (rows.length < pageSize) return result;
    }
  }

  @override
  Future<AssignedWork> loadOrder(String workerId, String orderId) async {
    _requireWorker(workerId);
    final row = await _orders(workerId).eq('id', orderId).single();
    _requireWorker(workerId);
    return _parse(row);
  }

  AssignedWork _parse(Map<String, dynamic> row) {
    final locations =
        (row['preventive_work_order_target'] as List)
            .map((target) => target['facility_path'] as String)
            .toList()
          ..sort();
    return AssignedWork(
      id: row['id'] as String,
      title: row['title'] as String,
      instructions: row['instructions'] as String,
      starts: malaysiaTime(DateTime.parse(row['scheduled_for'] as String)),
      ends: malaysiaTime(DateTime.parse(row['due_at'] as String)),
      locations: locations,
      checklist: (row['checklist'] as List).cast<String>(),
      status: AssignedWorkStatus.values.firstWhere(
        (status) => status.value == row['status'],
      ),
      checkedItems: (row['checked_items'] as List).cast<int>().toSet(),
      photoPaths: (row['preventive_work_evidence'] as List)
          .map((photo) => photo['path'] as String)
          .toList(),
      notes: row['worker_notes'] as String,
      feedback: row['review_note'] as String,
    );
  }

  Future<void> _action(
    String orderId,
    String action, [
    Map<String, dynamic> fields = const {},
  ]) async {
    await _client.rpc(
      'worker_work_order_action',
      params: {'target_order': orderId, 'action': action, ...fields},
    );
  }

  @override
  Future<void> start(String orderId) => _action(orderId, 'start');

  @override
  Future<void> checkItem(String orderId, int index, bool checked) =>
      _action(orderId, 'check', {'item_index': index, 'item_checked': checked});

  @override
  Future<void> submit(String orderId, String notes) =>
      _action(orderId, 'submit', {'notes': notes});

  @override
  Future<String> photoUrl(String path) =>
      _client.storage.from(_bucket).createSignedUrl(path, 300);

  @override
  Future<void> attachPhoto(
    String workerId,
    String orderId,
    Uint8List bytes,
  ) async {
    _requireWorker(workerId);
    if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
      throw const FormatException('Choose a photo under 10 MB.');
    }
    final (extension, mime) = _photoType(bytes);
    final random = Random.secure();
    final key = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final path = '$workerId/$orderId/$key.$extension';
    final storage = _client.storage.from(_bucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mime, cacheControl: '0'),
    );
    try {
      _requireWorker(workerId);
      await _action(orderId, 'attach', {'evidence_path': path});
    } catch (_) {
      try {
        await storage.remove([path]);
      } catch (_) {
        // The server refuses to delete a photo already attached to an order.
      }
      rethrow;
    }
  }

  (String, String) _photoType(Uint8List bytes) {
    bool matches(int offset, List<int> signature) =>
        bytes.length >= offset + signature.length &&
        Iterable<int>.generate(signature.length)
            .every((i) => bytes[offset + i] == signature[i]);
    if (matches(0, [255, 216, 255])) return ('jpg', 'image/jpeg');
    if (matches(0, [137, 80, 78, 71, 13, 10, 26, 10])) {
      return ('png', 'image/png');
    }
    if (matches(0, 'RIFF'.codeUnits) && matches(8, 'WEBP'.codeUnits)) {
      return ('webp', 'image/webp');
    }
    throw const FormatException('Choose a JPG, PNG or WebP photo.');
  }
}
