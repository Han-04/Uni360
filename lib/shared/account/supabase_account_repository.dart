import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/photo_upload.dart';
import 'account.dart';
import 'account_repository.dart';

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;
  static const _fields =
      'user_id,employee_id,full_name,phone,role,is_active,profile_photo_path';
  static const maxPhotoBytes = 5 * 1024 * 1024;
  StorageFileApi get _photos => _client.storage.from('account-photos');

  @override
  Stream<void> get signedOut => _client.auth.onAuthStateChange
      .where((state) => state.event == AuthChangeEvent.signedOut)
      .map((_) {});

  @override
  Future<Account> signIn(String email, String password) async {
    final AuthResponse response;
    try {
      response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (error) {
      throw AccountException(switch (error.code) {
        'invalid_credentials' => 'Incorrect email or password.',
        'email_not_confirmed' => 'Confirm your email before signing in.',
        'user_banned' =>
          'This account is disabled. Contact your administrator.',
        _ => 'Sign-in is unavailable. Check your connection and try again.',
      });
    }

    try {
      final user = response.user;
      if (response.session == null || user == null || user.email == null) {
        throw const AccountException(
          'The sign-in session could not be created.',
        );
      }
      final row = await _client
          .from('account')
          .select(_fields)
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null || row['is_active'] != true) {
        throw const AccountException(
          'No active Uni360 account was found. Contact your administrator.',
        );
      }
      return _account(row, user.email!);
    } catch (_) {
      try {
        await signOut();
      } on Exception {
        // The SDK clears the local session before attempting remote revocation.
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut(scope: SignOutScope.local);

  @override
  Future<Account> updateContact(
    Account account,
    String name,
    String phone, {
    Uint8List? photo,
  }) async {
    if (_client.auth.currentUser?.id != account.id) {
      throw const AccountException('Sign in again.');
    }
    String? uploaded;
    if (photo != null) {
      if (photo.isEmpty || photo.length > maxPhotoBytes) {
        throw const FormatException('Choose a photo up to 5 MB.');
      }
      final (extension, mime) = photoUploadType(photo);
      uploaded = '${account.id}/${const Uuid().v4()}.$extension';
      await _photos.uploadBinary(
        uploaded,
        photo,
        fileOptions: FileOptions(contentType: mime, cacheControl: '0'),
      );
    }
    try {
      final row = await _client
          .rpc(
            'save_account_profile',
            params: {
              'target_account': account.id,
              'name': name,
              'phone_number': phone,
              'photo': uploaded,
            },
          )
          .single();
      final previous = account.photoPath;
      if (previous != null && uploaded != null) await _removePhoto(previous);
      return _account(row, account.email);
    } catch (_) {
      if (uploaded != null) await _removePhoto(uploaded);
      rethrow;
    }
  }

  Future<void> _removePhoto(String path) async {
    try {
      await _photos.remove([path]);
    } on Exception {
      // The active profile photo remains protected by Storage policies.
    }
  }

  @override
  Future<String?> photoUrl(Account account) async {
    final path = account.photoPath;
    if (path == null || _client.auth.currentUser?.id != account.id) return null;
    return _photos.createSignedUrl(path, 300);
  }

  @override
  Future<void> changePassword(String current, String next) async {
    try {
      await _client.auth.updateUser(
        UserAttributes(currentPassword: current, password: next),
      );
    } on AuthException catch (error) {
      throw AccountException(switch (error.code) {
        'invalid_credentials' => 'Current password is incorrect.',
        'same_password' => 'Choose a password different from your current one.',
        'weak_password' => 'Choose a stronger password.',
        'reauthentication_needed' =>
          'Sign in again before changing your password.',
        _ =>
          'Password update failed. Check your current password and try again.',
      });
    }
  }

  Account _account(Map<String, dynamic> row, String email) => Account(
    id: row['user_id'] as String,
    employeeId: row['employee_id'] as String,
    email: email,
    name: row['full_name'] as String,
    phone: row['phone'] as String,
    photoPath: row['profile_photo_path'] as String?,
    role: AccountRole.values.firstWhere(
      (role) => role.value == row['role'],
      orElse: () =>
          throw const AccountException('This account role is not supported.'),
    ),
  );
}
