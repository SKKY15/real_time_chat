import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_time_chat/auth/auth_controller.dart';
import 'package:real_time_chat/chat/chat_controller.dart';
import 'package:real_time_chat/chat/chat_state.dart';
import 'package:real_time_chat/chat/composer_controller.dart';
import 'package:real_time_chat/chat/typing_controller.dart';
import 'package:real_time_chat/models/app_user.dart';
import 'package:real_time_chat/models/chat_message.dart';
import 'package:real_time_chat/models/typing_user.dart';
import 'package:real_time_chat/services/chat_repository.dart';
import 'package:real_time_chat/services/providers.dart';

import 'support/fake_chat_repository.dart';
import 'support/fakes.dart';

const AppUser _me = AppUser(uid: 'me', name: 'Me');

void main() {
  late FakeChatRepository repository;
  late FakeAuthController auth;
  late ProviderContainer container;
  late List<ChatState> states;

  ChatController controller() =>
      container.read(chatControllerProvider.notifier);
  ChatState state() => container.read(chatControllerProvider);
  List<String> ids() => [for (final m in state().messages) m.id];

  /// Creates the container and keeps the (auto-dispose) chat provider alive,
  /// the way the chat screen does.
  void start({AppUser? user = _me}) {
    repository = FakeChatRepository();
    auth = FakeAuthController(user);
    states = <ChatState>[];
    container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(() => auth),
      ],
    );
    addTearDown(container.dispose);
    container.listen<ChatState>(
      chatControllerProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
  }

  /// Delivers the first page and the answer of the bounded query.
  Future<void> load(int from, int to) async {
    repository.latest.add(batch(from, to));
    await pump();
    repository.since.single.controller.add(batch(from, to, cache: true));
    await pump();
  }

  group('ChatController', () {
    test('starts loading and publishes the first page', () async {
      start();
      expect(state().isLoading, isTrue);
      expect(state().messages, isEmpty);

      await load(1, 30);
      expect(state().isLoading, isFalse);
      expect(state().messages, hasLength(30));
      expect(state().hasMore, isTrue);
      expect(state().error, isNull);
    });

    test('does not notify when a snapshot changes nothing', () async {
      start();
      await load(1, 30);
      final before = states.length;
      repository.since.single.controller.add(batch(1, 30));
      await pump();
      expect(states, hasLength(before));
    });

    test('stays idle without a signed-in user', () async {
      start(user: null);
      expect(state().isLoading, isFalse);
      expect(repository.latestQueries, isEmpty);
      await controller().send('hello');
      expect(repository.sent, isEmpty);
    });

    group('send', () {
      test('shows the message before the write completes', () async {
        start();
        await load(1, 5);
        repository.holdSends = true;

        unawaited(controller().send('  hello there  '));
        // No await in between: the message is already on screen.
        final message = state().messages.first;
        expect(message.text, 'hello there');
        expect(message.senderId, 'me');
        expect(message.senderName, 'Me');
        expect(message.status, MessageStatus.sending);
        expect(repository.sent.single.id, message.id);
        expect(controller().consumeFresh(message.id), isTrue);
      });

      test('is confirmed in place by Firestore', () async {
        start();
        await load(1, 5);
        await controller().send('hello');
        final id = state().messages.first.id;

        final confirmed = ChatMessage(
          id: id,
          text: 'hello',
          senderId: 'me',
          senderName: 'Me',
          createdAt: testEpoch.add(const Duration(hours: 5)),
        );
        repository.since.single.controller.add(
          MessageBatch(
            messages: [confirmed, ...batch(1, 5).messages],
            oldestCursor: 'm1',
          ),
        );
        await pump();
        expect(ids().first, id);
        expect(state().messages, hasLength(6));
        expect(state().messages.first.status, MessageStatus.sent);
      });

      test('ignores empty text', () async {
        start();
        await load(1, 5);
        await controller().send('   \n ');
        expect(repository.sent, isEmpty);
        expect(state().messages, hasLength(5));
      });

      test('attaches a snippet of the message being replied to', () async {
        start();
        await load(1, 5);
        final original = state().messages.last;
        await controller().send('agreed', replyTo: original);
        final reply = state().messages.first.replyTo;
        expect(reply?.messageId, original.id);
        expect(reply?.text, original.text);
        expect(reply?.senderName, original.senderName);
      });

      test('marks the message as failed when the write is rejected', () async {
        start();
        await load(1, 5);
        repository.sendError = StateError('permission-denied');
        await controller().send('hello');
        expect(state().messages.first.status, MessageStatus.failed);
      });

      test('a failed message can be retried or discarded', () async {
        start();
        await load(1, 5);
        repository.sendError = StateError('permission-denied');
        await controller().send('hello');
        final id = state().messages.first.id;

        repository.holdSends = true;
        unawaited(controller().retry(id));
        expect(state().messages.first.status, MessageStatus.sending);
        expect(repository.sent, hasLength(2));

        repository.failSends(StateError('again'));
        await pump();
        expect(state().messages.first.status, MessageStatus.failed);

        controller().discard(id);
        expect(ids(), isNot(contains(id)));
      });

      test('brings held-back messages along', () async {
        start();
        await load(1, 5);
        controller().setPinned(false);
        repository.since.single.controller.add(batch(1, 7));
        await pump();
        expect(state().unreadCount, 2);

        await controller().send('hello');
        expect(state().unreadCount, 0);
        expect(state().messages, hasLength(8));
        expect(state().messages.first.text, 'hello');
      });
    });

    group('edit and delete', () {
      test('edit trims the text and skips unchanged messages', () async {
        start();
        await load(1, 5);
        final message = state().messages.first;

        await controller().edit(message, '  fixed  ');
        expect(repository.edits, {message.id: 'fixed'});

        repository.edits.clear();
        await controller().edit(message, message.text);
        await controller().edit(message, '   ');
        expect(repository.edits, isEmpty);
      });

      test('delete removes the message for everyone', () async {
        start();
        await load(1, 5);
        await controller().delete(state().messages.first);
        expect(repository.deleted, ['m5']);
      });
    });

    group('reading', () {
      test('holds incoming messages back while scrolled up', () async {
        start();
        await load(1, 30);
        controller().setPinned(false);
        repository.since.single.controller.add(batch(1, 32));
        await pump();
        expect(ids().first, 'm30');
        expect(state().unreadCount, 2);

        controller().setPinned(true);
        expect(ids().first, 'm32');
        expect(state().unreadCount, 0);
      });

      test('marks messages of other people as seen exactly once', () async {
        start();
        repository.latest.add(
          MessageBatch(
            messages: [
              msg(4, sender: 'me'),
              msg(3, seenBy: const ['me']),
              msg(2, deleted: true),
              msg(1),
            ],
            oldestCursor: 'm1',
          ),
        );
        await pump();

        controller().markSeen();
        expect(repository.seen, [
          ['m1'],
        ]);

        controller().markSeen();
        expect(repository.seen, hasLength(1));
      });

      test('does not mark held-back messages as seen', () async {
        start();
        await load(1, 3);
        controller().markSeen();
        controller().setPinned(false);
        repository.since.single.controller.add(batch(1, 4));
        await pump();
        controller().markSeen();
        expect(repository.seen, hasLength(1));

        controller().setPinned(true);
        controller().markSeen();
        expect(repository.seen.last, ['m4']);
      });
    });

    group('pagination', () {
      test('loadMore appends the older page', () async {
        start();
        await load(31, 60);
        final loading = controller().loadMore();
        expect(state().isLoadingMore, isTrue);
        await pump();
        repository.older.single.controller.add(batch(1, 30));
        await loading;
        expect(state().isLoadingMore, isFalse);
        expect(state().messages, hasLength(60));
        expect(ids().last, 'm1');
      });

      test('ensureLoaded fetches the page that holds a message', () async {
        start();
        await load(31, 60);
        final found = controller().ensureLoaded('m10');
        await pump();
        repository.older.single.controller.add(batch(1, 30));
        expect(await found, isTrue);
      });
    });

    group('errors and lifecycle', () {
      test('exposes a failing query and reload() retries', () async {
        start();
        repository.latest.addError(StateError('permission-denied'));
        await pump();
        expect(state().error, isStateError);
        expect(state().isLoading, isFalse);

        controller().reload();
        expect(state().error, isNull);
        expect(state().isLoading, isTrue);
        await load(1, 30);
        expect(state().messages, hasLength(30));
      });

      test('a small room needs no reload after backfilling', () async {
        start();
        await load(1, 5);
        controller().resyncAfterBackfill();
        await pump();
        expect(repository.latestQueries, hasLength(1));
      });

      test('a large room is loaded again after backfilling', () async {
        start();
        await load(1, 30);
        controller().resyncAfterBackfill();
        await pump();
        expect(state().isLoading, isTrue);
        expect(repository.latestQueries, hasLength(2));
        expect(repository.latestQueries.first.hasListener, isFalse);

        repository.latest.add(batch(1, 30));
        await pump();
        expect(state().messages, hasLength(30));
      });

      test('starts over for a different user', () async {
        start();
        await load(1, 30);
        auth.change(const AppUser(uid: 'other', name: 'Other'));
        await pump();
        expect(state().isLoading, isTrue);
        expect(state().messages, isEmpty);
        expect(repository.latestQueries, hasLength(2));
      });

      test('renaming the user keeps the loaded history', () async {
        start();
        await load(1, 30);
        auth.change(const AppUser(uid: 'me', name: 'Renamed'));
        await pump();
        expect(state().messages, hasLength(30));
        expect(repository.latestQueries, hasLength(1));

        await controller().send('hi');
        expect(repository.sent.single.senderName, 'Renamed');
      });

      test('stops listening when the room is closed', () async {
        start();
        await load(1, 30);
        container.dispose();
        expect(repository.since.single.controller.hasListener, isFalse);
      });

      test('a write finishing after the room was closed is harmless', () async {
        start();
        await load(1, 5);
        repository.holdSends = true;
        unawaited(controller().send('hello'));
        container.dispose();
        repository.failSends(StateError('offline'));
        await pump();
      });
    });
  });

  group('AuthController', () {
    late FakeAuthService service;
    late ProviderContainer auth;
    late List<AppUser?> users;

    void startAuth([AppUser? restored]) {
      service = FakeAuthService(restored);
      users = <AppUser?>[];
      auth = ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(service)],
      );
      addTearDown(auth.dispose);
      auth.listen<AppUser?>(
        authControllerProvider,
        (_, next) => users.add(next),
        fireImmediately: true,
      );
    }

    test('restores the previous session synchronously', () {
      startAuth(_me);
      expect(users, [_me]);
    });

    test('join signs in and stores the trimmed name', () async {
      startAuth();
      expect(users, [null]);
      await auth.read(authControllerProvider.notifier).join('  Sara ');
      await pump();
      expect(users.last, const AppUser(uid: 'uid-1', name: 'Sara'));
      expect(users.last?.hasName, isTrue);
      // The explicit update and the auth stream agree: one notification.
      expect(users, hasLength(2));
    });

    test('sign-out clears the user', () async {
      startAuth(_me);
      await auth.read(authControllerProvider.notifier).signOut();
      await pump();
      expect(users.last, isNull);
    });
  });

  group('TypingUsersController', () {
    TypingUser typist(String id) =>
        TypingUser(userId: id, name: id, updatedAt: DateTime.now());

    test('lists everyone who is typing except me', () async {
      start();
      final names = <List<String>>[];
      container.listen<List<TypingUser>>(
        typingUsersProvider,
        (_, next) => names.add([for (final user in next) user.name]),
        fireImmediately: true,
      );
      await pump();

      repository.typing.add([typist('me'), typist('sara')]);
      await pump();
      repository.typing.add([typist('me')]);
      await pump();

      expect(names, [
        <String>[],
        ['sara'],
        <String>[],
      ]);
    });

    test('is empty without a signed-in user', () async {
      start(user: null);
      final sub = container.listen<List<TypingUser>>(
        typingUsersProvider,
        (_, _) {},
      );
      expect(sub.read(), isEmpty);
      expect(repository.typing.hasListener, isFalse);
    });
  });

  group('ComposerController', () {
    test('switches between replying, editing and writing', () {
      start();
      final sub = container.listen<ComposerState>(composerProvider, (_, _) {});
      final composer = container.read(composerProvider.notifier);
      final message = msg(1);

      composer.reply(message);
      expect(sub.read().replyTo, message);
      expect(sub.read().isEditing, isFalse);

      composer.edit(message);
      expect(sub.read().editing, message);
      expect(sub.read().replyTo, isNull);

      composer.clear();
      expect(sub.read().editing, isNull);
      expect(sub.read().replyTo, isNull);
    });
  });
}
