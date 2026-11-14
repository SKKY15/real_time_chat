import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_time_chat/chat/message_feed.dart';
import 'package:real_time_chat/chat/message_store.dart';
import 'package:real_time_chat/models/chat_message.dart';
import 'package:real_time_chat/services/chat_repository.dart';

import 'support/fake_chat_repository.dart';

void main() {
  late FakeChatRepository repository;
  late MessageStore store;
  late MessageFeed feed;
  late int changes;
  late List<Object> pageErrors;

  List<String> ids() => [for (final m in store.visible) m.id];

  setUp(() {
    repository = FakeChatRepository();
    store = MessageStore(currentUserId: 'me');
    changes = 0;
    pageErrors = <Object>[];
    feed = MessageFeed(
      repository: repository,
      store: store,
      onChanged: () => changes++,
      onError: (error, _) => pageErrors.add(error),
    )..start();
  });

  tearDown(() => feed.dispose());

  group('first load', () {
    test('is loading until the first snapshot arrives', () async {
      expect(feed.isLoading, isTrue);
      repository.latest.add(batch(1, 30));
      await pump();
      expect(feed.isLoading, isFalse);
      expect(store.visible, hasLength(30));
      expect(ids().first, 'm30');
      expect(feed.hasMore, isTrue);
      expect(changes, greaterThan(0));
    });

    test('anchors on the oldest message of the confirmed window', () async {
      repository.latest.add(batch(1, 30));
      await pump();
      expect(repository.since.single.cursor, 'm1');
      expect(feed.watchesWholeRoom, isFalse);

      // The sliding window is dropped once the bounded query answers.
      expect(repository.latest.hasListener, isTrue);
      repository.since.single.controller.add(batch(1, 30, cache: true));
      await pump();
      expect(repository.latest.hasListener, isFalse);
    });

    test('a short first page means there is nothing older', () async {
      repository.latest.add(batch(1, 10));
      await pump();
      expect(feed.hasMore, isFalse);
      await feed.loadMore();
      expect(repository.older, isEmpty);
      // A room this small is watched as a whole, so even backdated messages
      // (the demo seeder) show up live.
      expect(repository.since.single.cursor, isNull);
      expect(feed.watchesWholeRoom, isTrue);
    });

    test('an empty room is watched as a whole', () async {
      repository.latest.add(batch(1, 0));
      await pump();
      expect(feed.isLoading, isFalse);
      expect(feed.hasMore, isFalse);
      expect(repository.since.single.cursor, isNull);

      repository.since.single.controller.add(batch(1, 1));
      await pump();
      expect(ids(), ['m1']);
      expect(store.consumeFresh('m1'), isTrue);
    });

    test('shows cached messages before the server answers', () async {
      repository.latest.add(batch(1, 30, cache: true));
      await pump();
      expect(feed.isLoading, isFalse);
      expect(store.visible, hasLength(30));
      expect(repository.since, isEmpty, reason: 'not confirmed yet');
    });
  });

  group('cache followed by the server', () {
    test('keeps cached messages that connect to the newest ones', () async {
      repository.latest.add(batch(1, 30, cache: true));
      await pump();
      // Ten messages arrived while the app was closed; m1..m10 fell out of
      // the limit(30) window but are still part of the contiguous history.
      repository.latest.add(
        batch(11, 40, removed: [for (var n = 1; n <= 10; n++) 'm$n']),
      );
      await pump();
      expect(store.visible, hasLength(40));
      expect(ids().first, 'm40');
      expect(ids().last, 'm1');
      // The bounded query starts at the oldest message on screen.
      expect(repository.since.single.cursor, 'm1');
      // Messages that were waiting are part of the first load: no animation.
      expect(store.consumeFresh('m40'), isFalse);
    });

    test('starts over when the cache is too old to connect', () async {
      repository.latest.add(batch(1, 30, cache: true));
      await pump();
      unawaited(feed.loadMore());
      await pump();
      expect(repository.older.single.cursor, 'm1');

      repository.latest.add(
        batch(101, 130, removed: [for (var n = 1; n <= 30; n++) 'm$n']),
      );
      await pump();
      expect(store.visible, hasLength(30));
      expect(ids().first, 'm130');
      expect(ids().last, 'm101');
      expect(repository.since.single.cursor, 'm101');
      expect(feed.isLoadingMore, isFalse);
      expect(repository.older.single.controller.hasListener, isFalse);

      // Paging continues from the new history.
      unawaited(feed.loadMore());
      await pump();
      expect(repository.older.last.cursor, 'm101');
    });

    test('removes messages deleted on the server while offline', () async {
      repository.latest.add(batch(1, 30, cache: true));
      await pump();
      // m20 sits inside the confirmed window range but is gone.
      final confirmed = [
        for (var n = 30; n >= 1; n--)
          if (n != 20) msg(n),
      ];
      repository.latest.add(
        MessageBatch(
          messages: confirmed,
          removedIds: const ['m20'],
          oldestCursor: 'm1',
        ),
      );
      await pump();
      expect(store.contains('m20'), isFalse);
      expect(store.visible, hasLength(29));
    });
  });

  group('live updates', () {
    setUp(() async {
      repository.latest.add(batch(1, 30));
      await pump();
      repository.since.single.controller.add(batch(1, 30, cache: true));
      await pump();
    });

    test('new messages animate in while pinned to the bottom', () async {
      repository.since.single.controller.add(batch(1, 31));
      await pump();
      expect(ids().first, 'm31');
      expect(store.consumeFresh('m31'), isTrue);
    });

    test('new messages are held back while reading history', () async {
      store.setPinned(false);
      repository.since.single.controller.add(batch(1, 32));
      await pump();
      expect(ids().first, 'm30');
      expect(store.unreadCount, 2);

      store.setPinned(true);
      expect(ids().first, 'm32');
    });

    test('messages never fall out of the bounded query', () async {
      repository.since.single.controller.add(batch(1, 75));
      await pump();
      expect(store.visible, hasLength(75));
      expect(ids().last, 'm1');
    });

    test('edits, deletes and receipts update loaded messages', () async {
      final messages = [
        for (var n = 30; n >= 1; n--)
          n == 5 ? msg(5, deleted: true, text: '') : msg(n),
      ];
      repository.since.single.controller.add(
        MessageBatch(messages: messages, oldestCursor: 'm1'),
      );
      await pump();
      expect(store['m5']?.deleted, isTrue);
    });

    test('hard deletes disappear', () async {
      repository.since.single.controller.add(batch(1, 30));
      await pump();
      repository.since.single.controller.add(batch(1, 29, removed: ['m30']));
      await pump();
      expect(store.contains('m30'), isFalse);
    });
  });

  group('rejected writes', () {
    test('a local message the server rejected leaves the window', () async {
      repository.latest.add(batch(1, 5, cache: true));
      await pump();
      final pending = ChatMessage(
        id: 'out',
        text: 'hi',
        senderId: 'me',
        senderName: 'Me',
        createdAt: testEpoch,
        hasPendingWrites: true,
        hasServerTimestamp: false,
      );
      repository.latest.add(
        MessageBatch(
          messages: [pending, ...batch(1, 5).messages],
          isFromCache: true,
          oldestCursor: 'm1',
        ),
      );
      await pump();
      expect(store.hasRemote('out'), isTrue);

      repository.latest.add(batch(1, 5, cache: true, removed: ['out']));
      await pump();
      expect(store.hasRemote('out'), isFalse);
    });
  });

  group('pagination', () {
    setUp(() async {
      repository.latest.add(batch(31, 60));
      await pump();
    });

    test('loads the page before the oldest message', () async {
      final load = feed.loadMore();
      expect(feed.isLoadingMore, isTrue);
      await pump();
      expect(repository.older.single.cursor, 'm31');
      expect(repository.older.single.limit, 30);

      repository.older.single.controller.add(batch(1, 30));
      await load;
      expect(feed.isLoadingMore, isFalse);
      expect(feed.hasMore, isTrue);
      expect(store.visible, hasLength(60));
      expect(ids().last, 'm1');
      // Older pages never animate in and are never held back.
      expect(store.consumeFresh('m1'), isFalse);
    });

    test('continues from the oldest loaded message', () async {
      var load = feed.loadMore();
      await pump();
      repository.older[0].controller.add(batch(1, 30));
      await load;

      load = feed.loadMore();
      await pump();
      expect(repository.older[1].cursor, 'm1');
      repository.older[1].controller.add(batch(-9, 0));
      await load;
      expect(feed.hasMore, isFalse);
      expect(store.visible, hasLength(70));

      await feed.loadMore();
      expect(repository.older, hasLength(2));
    });

    test('concurrent calls share one request', () async {
      final first = feed.loadMore();
      final second = feed.loadMore();
      await pump();
      expect(repository.older, hasLength(1));
      repository.older.single.controller.add(batch(1, 30));
      await Future.wait([first, second]);
    });

    test('a short page from the cache waits for the server', () async {
      final load = feed.loadMore();
      var done = false;
      unawaited(load.then((_) => done = true));
      await pump();

      repository.older.single.controller.add(batch(21, 30, cache: true));
      await pump();
      expect(done, isFalse);
      expect(feed.isLoadingMore, isTrue);
      expect(store.visible, hasLength(40), reason: 'cached part is shown');

      repository.older.single.controller.add(batch(1, 30));
      await load;
      expect(feed.hasMore, isTrue);
      expect(store.visible, hasLength(60));
    });

    test('a full page from the cache is enough to continue offline', () async {
      final load = feed.loadMore();
      await pump();
      repository.older.single.controller.add(batch(1, 30, cache: true));
      await load;
      expect(feed.isLoadingMore, isFalse);
      expect(feed.hasMore, isTrue);
    });

    test('loaded pages stay live', () async {
      final load = feed.loadMore();
      await pump();
      repository.older.single.controller.add(batch(1, 30));
      await load;

      final edited = [
        for (var n = 30; n >= 1; n--)
          n == 7 ? msg(7, text: 'edited later', editedAt: testEpoch) : msg(n),
      ];
      repository.older.single.controller.add(
        MessageBatch(messages: edited, oldestCursor: 'm1'),
      );
      await pump();
      expect(store['m7']?.text, 'edited later');
    });

    test('a failing page is reported and can be requested again', () async {
      final load = feed.loadMore();
      await pump();
      repository.older.single.controller.addError(StateError('offline'));
      await load;
      expect(pageErrors.single, isStateError);
      expect(feed.isLoadingMore, isFalse);
      expect(feed.hasMore, isTrue);

      unawaited(feed.loadMore());
      await pump();
      expect(repository.older, hasLength(2));
      expect(repository.older.last.cursor, 'm31');
    });
  });

  group('ensureLoaded', () {
    setUp(() async {
      repository.latest.add(batch(61, 90));
      await pump();
    });

    test('is immediate for a loaded message', () async {
      expect(await feed.ensureLoaded('m70'), isTrue);
      expect(repository.older, isEmpty);
    });

    test('loads pages until the message shows up', () async {
      final result = feed.ensureLoaded('m5');
      await pump();
      repository.older[0].controller.add(batch(31, 60));
      await pump();
      repository.older[1].controller.add(batch(1, 30));
      expect(await result, isTrue);
      expect(repository.older, hasLength(2));
    });

    test('gives up at the beginning of the conversation', () async {
      final result = feed.ensureLoaded('missing');
      await pump();
      repository.older[0].controller.add(batch(51, 60));
      expect(await result, isFalse);
    });

    test('gives up when a page takes too long', () async {
      final result = feed.ensureLoaded(
        'm5',
        pageTimeout: const Duration(milliseconds: 20),
      );
      expect(await result, isFalse);
    });
  });

  group('errors', () {
    test('a failing main query is exposed and start() retries', () async {
      repository.latest.addError(StateError('permission-denied'));
      await pump();
      expect(feed.error, isStateError);
      expect(feed.isLoading, isFalse);

      feed.start();
      expect(feed.error, isNull);
      expect(feed.isLoading, isTrue);
      expect(repository.latestQueries, hasLength(2));
      expect(repository.latestQueries.first.hasListener, isFalse);

      repository.latest.add(batch(1, 30));
      await pump();
      expect(feed.isLoading, isFalse);
      expect(store.visible, hasLength(30));
    });

    test('an error of the bounded query is exposed too', () async {
      repository.latest.add(batch(1, 30));
      await pump();
      repository.since.single.controller.addError(StateError('revoked'));
      await pump();
      expect(feed.error, isStateError);
    });
  });

  test('nothing is delivered after dispose', () async {
    repository.latest.add(batch(1, 30));
    await pump();
    final before = changes;
    feed.dispose();
    expect(repository.latest.hasListener, isFalse);
    expect(repository.since.single.controller.hasListener, isFalse);
    await feed.loadMore();
    expect(changes, before);
  });
}
