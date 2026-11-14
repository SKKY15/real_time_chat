import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../services/providers.dart';

/// The signed-in user, or `null` when nobody is signed in.
///
/// The user restored from the previous session is available synchronously,
/// so returning users go straight to the chat without a loading screen.
final authControllerProvider = NotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() {
    final service = ref.watch(authServiceProvider);
    final subscription = service.userChanges().listen(
      (user) => state = user,
      onError: (Object _) {},
    );
    ref.onDispose(subscription.cancel);
    return service.currentUser;
  }

  /// Signs in anonymously (if needed) and saves the chosen [name].
  Future<void> join(String name) async {
    state = await ref.read(authServiceProvider).join(name);
  }

  Future<void> signOut() => ref.read(authServiceProvider).signOut();
}
