import 'account.dart';

abstract interface class AccountRepository {
  Stream<void> get signedOut;
  Future<Account> signIn(String email, String password);
  Future<void> signOut();
  Future<Account> updateContact(Account account, String name, String phone);
  Future<void> changePassword(String current, String next);
}

class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
}
