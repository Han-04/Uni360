import 'package:supabase_flutter/supabase_flutter.dart';

import 'account.dart';
import 'account_repository.dart';

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;
  static const _fields = 'user_id,employee_id,full_name,phone,role,is_active';

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
    String phone,
  ) async {
    final row = await _client
        .from('account')
        .update({'full_name': name, 'phone': phone})
        .eq('user_id', account.id)
        .select(_fields)
        .maybeSingle();
    if (row == null) {
      throw const AccountException('This profile is no longer available.');
    }
    return _account(row, account.email);
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
    role: AccountRole.values.firstWhere(
      (role) => role.value == row['role'],
      orElse: () =>
          throw const AccountException('This account role is not supported.'),
    ),
  );
}
