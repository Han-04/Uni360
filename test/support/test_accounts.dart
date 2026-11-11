import 'package:uni360/shared/account/account.dart';
import 'package:uni360/shared/account/account_repository.dart';

class TestAccounts implements AccountRepository {
  TestAccounts({AccountRole role = AccountRole.worker})
    : profile = Account(
        id: 'test-user-id',
        employeeId: 'EMP-2026-001',
        email: email,
        name: 'Test Account',
        phone: '',
        role: role,
      );

  static const email = 'account@uni360.example';
  static const password = 'TestPassword';
  Account profile;
  String _password = password;

  @override
  Stream<void> get signedOut => const Stream.empty();

  @override
  Future<Account> signIn(String email, String password) async {
    if (email != profile.email || password != _password) {
      throw const AccountException('Incorrect email or password.');
    }
    return profile;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<Account> updateContact(
    Account account,
    String name,
    String phone,
  ) async {
    return profile = profile.withContact(name: name, phone: phone);
  }

  @override
  Future<void> changePassword(String current, String next) async {
    if (current != _password) {
      throw const AccountException('Incorrect password.');
    }
    _password = next;
  }
}
