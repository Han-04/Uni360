import 'package:supabase_flutter/supabase_flutter.dart';

class PreventiveAlert {
  const PreventiveAlert(
    this.id,
    this.title,
    this.message,
    this.createdAt,
    this.read, {
    this.senderName,
    this.senderPhotoUrl,
  });
  final String id, title, message;
  final DateTime createdAt;
  final bool read;
  final String? senderName, senderPhotoUrl;
}

class PreventiveAlertRepository {
  const PreventiveAlertRepository(this._client);
  final SupabaseClient _client;

  SupabaseQueryBuilder get _alerts =>
      _client.schema('maintenance_api').from('preventive_notification');

  Future<List<dynamic>> _loadRows(String workerId) async {
    try {
      return await _client.rpc<List<dynamic>>('read_preventive_notifications');
    } on PostgrestException catch (error) {
      // Keep the feed readable while the sender migration is being rolled out.
      if (error.code != 'PGRST202') rethrow;
      return await _alerts
          .select('id,title,message,created_at,read_at')
          .eq('recipient_id', workerId)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(100);
    }
  }

  Future<List<PreventiveAlert>> load(String workerId) async {
    if (_client.auth.currentUser?.id != workerId) return [];
    final rows = await _loadRows(workerId);
    final photoPaths = {
      for (final row in rows)
        if (row['sender_photo'] case final String path) path,
    };
    final photos = Map.fromEntries(
      await Future.wait(
        photoPaths.map((path) async {
          try {
            return MapEntry(
              path,
              await _client.storage
                  .from('account-photos')
                  .createSignedUrl(path, 300),
            );
          } on StorageException {
            return MapEntry<String, String?>(path, null);
          }
        }),
      ),
    );
    return [
      for (final row in rows)
        PreventiveAlert(
          row['id'] as String,
          row['title'] as String,
          row['message'] as String,
          DateTime.parse(row['created_at'] as String),
          row['read_at'] != null,
          senderName: row['sender_name'] as String?,
          senderPhotoUrl: photos[row['sender_photo']],
        ),
    ];
  }

  Future<void> markRead(String workerId, String id) async {
    await _alerts
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('recipient_id', workerId)
        .eq('id', id)
        .isFilter('read_at', null);
  }
}
