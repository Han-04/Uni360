import 'dart:async';

import 'package:flutter/foundation.dart';

import 'account.dart';
import 'account_repository.dart';

class AccountController extends ChangeNotifier {
  AccountController(this._repository) {
    _subscription = _repository.signedOut.listen((_) {
      if (_account == null || _disposed) return;
      _account = null;
      sessionMessage = 'Your session ended. Sign in again.';
      notifyListeners();
    });
  }

  final AccountRepository _repository;
  late final StreamSubscription<void> _subscription;
  Account? _account;
  bool _disposed = false;
  bool _busy = false;
  DateTime lastActivity = DateTime.now();
  String? sessionMessage;

  Account? get account => _account;
  bool get busy => _busy;

  Future<void> signIn(String email, String password) async {
    if (_busy || _account != null) return;
    _busy = true;
    sessionMessage = null;
    notifyListeners();
    try {
      final signedIn = await _repository.signIn(
        email.trim().toLowerCase(),
        password,
      );
      if (_disposed) {
        await _repository.signOut();
        return;
      }
      _account = signedIn;
      lastActivity = DateTime.now();
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> signOut({bool expired = false}) async {
    if (_account == null) return;
    _account = null;
    _busy = true;
    sessionMessage = expired ? 'Your session expired. Sign in again.' : null;
    notifyListeners();
    try {
      await _repository.signOut();
    } on Exception {
      sessionMessage ??=
          'Signed out on this device. Server sign-out could not be confirmed.';
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void touch() {
    checkSession();
    if (_account != null) lastActivity = DateTime.now();
  }

  void checkSession() {
    if (_account != null &&
        DateTime.now().difference(lastActivity).inMinutes >= 15) {
      unawaited(signOut(expired: true));
    }
  }

  Future<void> updateProfile(String name, String phone) async {
    touch();
    final current = _account;
    if (current == null) throw const AccountException('Sign in again.');
    final updated = await _repository.updateContact(
      current,
      name.trim(),
      phone.trim(),
    );
    if (!_disposed && identical(_account, current)) {
      _account = updated;
      notifyListeners();
    }
  }

  Future<void> changePassword(String current, String next) async {
    touch();
    if (_account == null) throw const AccountException('Sign in again.');
    await _repository.changePassword(current, next);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
