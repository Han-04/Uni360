import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/photo_upload.dart';

const leaveTypes = {
  'annual': 'Annual leave',
  'medical': 'Medical leave',
  'emergency': 'Emergency leave',
  'other': 'Other leave',
};

String leavePeriod(DateTime first, DateTime last) => first == last
    ? leaveDate(first)
    : '${leaveDate(first)} to ${leaveDate(last)}';

String leaveDate(DateTime date) => date.toIso8601String().substring(0, 10);

class WorkerLeave {
  WorkerLeave.fromRow(Map<String, dynamic> row)
    : id = row['id'] as String,
      workerId = row['worker_id'] as String,
      kind = row['leave_type'] as String,
      first = DateTime.parse(row['starts_on'] as String),
      last = DateTime.parse(row['ends_on'] as String),
      reason = row['reason'] as String,
      status = row['status'] as String,
      requestedAt = DateTime.parse(row['requested_at'] as String),
      note = row['review_note'] as String?,
      documentPath = row['document_path'] as String?,
      documentName = row['document_name'] as String?,
      count = LeaveCoverage(
        row['reassigned_count'] as int,
        row['uncovered_count'] as int,
        row['active_count'] as int,
      );

  final String id, workerId, kind, reason, status;
  final DateTime first, last, requestedAt;
  final String? note, documentPath, documentName;
  final LeaveCoverage count;

  String get title => leaveTypes[kind] ?? 'Leave';
  String get period => leavePeriod(first, last);

  String statusOn(DateTime date) => switch (status) {
    'approved'
        when leaveDate(date).compareTo(leaveDate(first)) >= 0 &&
            leaveDate(date).compareTo(leaveDate(last)) <= 0 =>
      'On leave',
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    _ => 'Pending approval',
  };
}

class LeaveCoverage {
  const LeaveCoverage(this.reassigned, this.uncovered, this.active);
  final int reassigned, uncovered, active;
}

class LeaveDocument {
  LeaveDocument(this.name, this.bytes) {
    if (name.trim().isEmpty ||
        name.length > 255 ||
        bytes.isEmpty ||
        bytes.length > maxBytes) {
      throw const FormatException('Choose one PDF or photo up to 10 MB.');
    }
    if (bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-') {
      extension = 'pdf';
      mime = 'application/pdf';
    } else {
      final (photoExtension, photoMime) = photoUploadType(bytes);
      extension = photoExtension;
      mime = photoMime;
    }
  }

  static const maxBytes = 10 * 1024 * 1024;
  final String name;
  final Uint8List bytes;
  late final String extension, mime;
}

class WorkerLeaveRepository {
  const WorkerLeaveRepository(this._client);
  final SupabaseClient _client;
  static const _fields =
      'id,worker_id,leave_type,starts_on,ends_on,reason,status,requested_at,review_note,reassigned_count,uncovered_count,active_count,document_path,document_name';
  StorageFileApi get _documents => _client.storage.from('leave-documents');

  Future<String> documentUrl(String path) =>
      _documents.createSignedUrl(path, 120);

  Future<String> workerStatus(String workerId, DateTime date) async {
    final (onLeave, profile) = await (
      isOnLeave(workerId, date),
      _client
          .schema('maintenance_api')
          .from('worker_profile')
          .select('employment_status')
          .eq('worker_id', workerId)
          .maybeSingle(),
    ).wait;
    if (onLeave) return 'On leave';
    final status = (profile?['employment_status'] as String?)?.trim();
    if (status == null || status.isEmpty) return 'Status unavailable';
    return status[0].toUpperCase() + status.substring(1);
  }

  Future<bool> isOnLeave(String workerId, DateTime date) async {
    final day = leaveDate(date);
    final result = await _client
        .schema('maintenance_api')
        .from('worker_availability')
        .select('availability_id')
        .eq('worker_id', workerId)
        .eq('leave_status', 'approved')
        .lt(
          'shift_start',
          '${leaveDate(DateTime.utc(date.year, date.month, date.day + 1))}T00:00:00+08:00',
        )
        .gt('shift_end', '${day}T00:00:00+08:00')
        .limit(1);
    return result.isNotEmpty;
  }

  Future<List<WorkerLeave>> list({
    String? workerId,
    String? status,
    int page = 0,
  }) async {
    var query = _client
        .schema('maintenance_api')
        .from('worker_leave_request')
        .select(_fields);
    if (workerId != null) query = query.eq('worker_id', workerId);
    if (status != null) query = query.eq('status', status);
    final rows = await query
        .order('requested_at')
        .order('id')
        .range(page * 25, (page + 1) * 25);
    return rows.map(WorkerLeave.fromRow).toList();
  }

  Future<void> submit(
    String kind,
    DateTime first,
    DateTime last,
    String reason, {
    LeaveDocument? document,
  }) async {
    final params = <String, dynamic>{
      'kind': kind,
      'first_day': leaveDate(first),
      'last_day': leaveDate(last),
      'explanation': reason,
    };
    if (document == null) {
      await _client.rpc('submit_worker_leave', params: params);
      return;
    }
    final worker = _client.auth.currentUser?.id;
    if (worker == null) {
      throw const FormatException('Sign in to attach a document.');
    }
    final path = '$worker/${const Uuid().v4()}.${document.extension}';
    await _documents.uploadBinary(
      path,
      document.bytes,
      fileOptions: FileOptions(contentType: document.mime, cacheControl: '0'),
    );
    try {
      await _client.rpc(
        'submit_worker_leave_with_document',
        params: {...params, 'document': path, 'filename': document.name},
      );
    } catch (_) {
      try {
        await _documents.remove([path]);
      } on Exception {
        // A linked document is protected even if the response was interrupted.
      }
      rethrow;
    }
  }

  Future<LeaveCoverage> review(
    String id, {
    required bool approve,
    String? note,
  }) async {
    final row = await _client.rpc<Map<String, dynamic>>(
      'review_worker_leave',
      params: {'target_request': id, 'approve': approve, 'feedback': note},
    );
    return LeaveCoverage(
      row['reassigned'] as int,
      row['uncovered'] as int,
      row['active'] as int,
    );
  }
}
