import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../models/typing_user.dart';
import '../services/providers.dart';
import 'typing_tracker.dart';

/// People who are typing right now (never the local user).
///
/// A dedicated provider: keystrokes of other people rebuild the typing
/// indicator and nothing else.
final typingUsersProvider =
    NotifierProvider.autoDispose<TypingUsersController, List<TypingUser>>(
      TypingUsersController.new,
    );

class TypingUsersController extends Notifier<List<TypingUser>> {
  @override
  List<TypingUser> build() {
    final repository = ref.watch(chatRepositoryProvider);
    final userId = ref.watch(
      authControllerProvider.select((user) => user?.uid),
    );
    if (userId == null) return const <TypingUser>[];

    final tracker = TypingTracker(
      selfId: userId,
      onChanged: (typing) {
        if (ref.mounted) state = typing;
      },
    );
    final subscription = repository.watchTyping().listen(
      tracker.apply,
      // The indicator is a nicety: a failing query must not surface anywhere.
      onError: (Object _) {},
    );
    ref.onDispose(() {
      unawaited(subscription.cancel());
      tracker.dispose();
    });
    return const <TypingUser>[];
  }
}
