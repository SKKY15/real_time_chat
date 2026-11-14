import 'dart:async';

import 'package:real_time_chat/auth/auth_controller.dart';
import 'package:real_time_chat/models/app_user.dart';
import 'package:real_time_chat/services/auth_service.dart';

/// Stands in for the Firebase-backed [AuthController]: a fixed user that
/// tests can replace.
class FakeAuthController extends AuthController {
  FakeAuthController(this._initial);

  final AppUser? _initial;

  @override
  AppUser? build() => _initial;

  void change(AppUser? user) => state = user;
}

/// In-memory [AuthService]: anonymous sign-in without Firebase.
class FakeAuthService implements AuthService {
  FakeAuthService([this._current]);

  final StreamController<AppUser?> _changes =
      StreamController<AppUser?>.broadcast();
  AppUser? _current;

  /// When set, the next [join] fails with this error.
  Object? joinError;

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> userChanges() => _changes.stream;

  @override
  Future<AppUser> join(String name) async {
    final error = joinError;
    if (error != null) {
      joinError = null;
      throw error;
    }
    final user = AppUser(uid: _current?.uid ?? 'uid-1', name: name.trim());
    _current = user;
    _changes.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _changes.add(null);
  }
}
