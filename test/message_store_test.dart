import 'package:flutter_test/flutter_test.dart';
import 'package:real_time_chat/chat/message_store.dart';
import 'package:real_time_chat/models/chat_message.dart';

import 'support/fake_chat_repository.dart';

void main() {
  late DateTime now;
  late MessageStore store;

  List<String> ids() => [for (final m in store.visible) m.id];

  ChatMessage outgoing(String id, {String text = 'hi'}) => ChatMessage(
    id: id,
    text: text,
    senderId: 'me',
    senderName: 'Me',
    createdAt: now,
  );

  setUp(() {
    now = testEpoch.add(const Duration(hours: 1));
    store = MessageStore(currentUserId: 'me', clock: () => now);
  });

  group('ordering', () {
    test('lists messages newest first', () {
      store.upsert([msg(2), msg(3), msg(1)]);
      expect(ids(), ['m3', 'm2', 'm1']);
    });

    test('a message that is still being sent is always the newest', () {
      store.upsert([msg(500)]); // far "in the future" for this device's clock
      store.addOutgoing(outgoing('out'));
      expect(ids(), ['out', 'm500']);
    });

    test('returns the identical list until something visible changes', () {
      store.upsert([msg(1), msg(2)]);
      final first = store.visible;
      store.upsert([msg(1), msg(2)]);
      expect(identical(store.visible, first), isTrue);
      store.upsert([msg(2, text: 'changed')]);
      expect(identical(store.visible, first), isFalse);
      expect(store.visible.first.text, 'changed');
    });
  });

  group('optimistic sending', () {
    test('shows the message immediately as sending', () {
      store.addOutgoing(outgoing('out'));
      expect(ids(), ['out']);
      expect(store.visible.single.status, MessageStatus.sending);
    });

    test('keeps its place while Firestore echoes the pending write', () {
      store.upsert([msg(1)]);
      store.addOutgoing(outgoing('out'));
      now = now.add(const Duration(seconds: 3));
      store.upsert([
        ChatMessage(
          id: 'out',
          text: 'hi',
          senderId: 'me',
          senderName: 'Me',
          createdAt: now, // fallback time made up while parsing
          hasPendingWrites: true,
          hasServerTimestamp: false,
        ),
      ]);
      expect(ids(), ['out', 'm1']);
      final message = store.visible.first;
      expect(message.status, MessageStatus.sending);
      expect(message.createdAt, testEpoch.add(const Duration(hours: 1)));
    });

    test('becomes sent, then seen, once the server confirms', () {
      store.addOutgoing(outgoing('out'));
      final serverTime = testEpoch.add(const Duration(hours: 2));
      ChatMessage confirmed({List<String> seenBy = const []}) => ChatMessage(
        id: 'out',
        text: 'hi',
        senderId: 'me',
        senderName: 'Me',
        createdAt: serverTime,
        seenBy: seenBy,
      );

      store.upsert([confirmed()]);
      expect(store.visible.single.status, MessageStatus.sent);
      expect(store.visible.single.createdAt, serverTime);

      store.upsert([
        confirmed(seenBy: ['me']),
      ]);
      expect(store.visible.single.status, MessageStatus.sent);

      store.upsert([
        confirmed(seenBy: ['me', 'sara']),
      ]);
      expect(store.visible.single.status, MessageStatus.seen);
    });

    test('a rejected write stays visible as failed and can be retried', () {
      store.addOutgoing(outgoing('out'));
      store.upsert([
        ChatMessage(
          id: 'out',
          text: 'hi',
          senderId: 'me',
          senderName: 'Me',
          createdAt: now,
          hasPendingWrites: true,
          hasServerTimestamp: false,
        ),
      ]);
      // Firestore rolls the local write back and the future fails.
      store.remove(['out']);
      store.markFailed('out');
      expect(ids(), ['out']);
      expect(store.visible.single.status, MessageStatus.failed);

      expect(store.retry('out')?.sendFailed, isFalse);
      expect(store.visible.single.status, MessageStatus.sending);

      store.markFailed('out');
      store.discard('out');
      expect(store.visible, isEmpty);
    });
  });

  group('edits', () {
    test('shows "edited" while my edit is still pending', () {
      store.upsert([msg(1, sender: 'me')]);
      expect(store.visible.single.isEdited, isFalse);

      store.upsert([msg(1, sender: 'me', text: 'fixed', pending: true)]);
      expect(store.visible.single.text, 'fixed');
      expect(store.visible.single.isEdited, isTrue);
      expect(store.visible.single.status, MessageStatus.sending);

      final editedAt = testEpoch.add(const Duration(hours: 3));
      store.upsert([msg(1, sender: 'me', text: 'fixed', editedAt: editedAt)]);
      expect(store.visible.single.editedAt, editedAt);
      expect(store.visible.single.status, MessageStatus.sent);
    });

    test('a pending read receipt does not mark their message as edited', () {
      store.upsert([
        msg(1, pending: true, seenBy: ['me']),
      ]);
      expect(store.visible.single.isEdited, isFalse);
    });

    test('a deleted message is never shown as edited', () {
      store.upsert([msg(1, sender: 'me', deleted: true, pending: true)]);
      expect(store.visible.single.isEdited, isFalse);
    });
  });

  group('reading older history', () {
    setUp(() {
      store.upsert([msg(1), msg(2)]);
      store.setPinned(false);
    });

    test('holds new messages back and counts them as unread', () {
      final before = store.visible;
      store.upsert([msg(3), msg(4)], announce: true);
      expect(identical(store.visible, before), isTrue);
      expect(store.unreadCount, 2);
    });

    test('releases them when the list is pinned to the bottom again', () {
      store.upsert([msg(3), msg(4)], announce: true);
      store.setPinned(true);
      expect(ids(), ['m4', 'm3', 'm2', 'm1']);
      expect(store.unreadCount, 0);
      expect(store.consumeFresh('m3'), isTrue);
      expect(store.consumeFresh('m4'), isTrue);
    });

    test('still applies edits and deletes to visible messages', () {
      store.upsert([msg(2, deleted: true)], announce: true);
      expect(store.visible.first.deleted, isTrue);
      expect(store.unreadCount, 0);
    });

    test('never holds back older pages', () {
      store.upsert([msg(-1), msg(0)]);
      expect(ids(), ['m2', 'm1', 'm0', 'm-1']);
      expect(store.unreadCount, 0);
    });

    test('never holds back my own messages', () {
      store.upsert([msg(3, sender: 'me')], announce: true);
      expect(ids().first, 'm3');
      expect(store.unreadCount, 0);
    });

    test('a held message that disappears is no longer unread', () {
      store.upsert([msg(3)], announce: true);
      store.remove(['m3']);
      expect(store.unreadCount, 0);
    });
  });

  group('entrance animation', () {
    test('plays once for messages that arrive live', () {
      store.upsert([msg(1)]);
      store.upsert([msg(2)], announce: true);
      expect(store.consumeFresh('m1'), isFalse);
      expect(store.consumeFresh('m2'), isTrue);
      expect(store.consumeFresh('m2'), isFalse);
    });

    test('plays for my own optimistic message', () {
      store.addOutgoing(outgoing('out'));
      expect(store.consumeFresh('out'), isTrue);
    });

    test('is skipped for a burst of messages', () {
      store.upsert([for (var n = 1; n <= 40; n++) msg(n)], announce: true);
      expect(store.visible, hasLength(40));
      expect(store.consumeFresh('m40'), isFalse);
      expect(store.consumeFresh('m1'), isFalse);
    });

    test('is skipped when many held messages are released at once', () {
      store.setPinned(false);
      store.upsert([for (var n = 1; n <= 10; n++) msg(n)], announce: true);
      expect(store.unreadCount, 10);
      store.setPinned(true);
      expect(store.visible, hasLength(10));
      expect(store.consumeFresh('m10'), isFalse);
    });

    test('is skipped when the row is built too late', () {
      store.upsert([msg(2)], announce: true);
      now = now.add(const Duration(seconds: 5));
      expect(store.consumeFresh('m2'), isFalse);
    });
  });

  test('resetRemote replaces the history but keeps the outbox', () {
    store.upsert([msg(1), msg(2)]);
    store.addOutgoing(outgoing('out'));
    store.resetRemote([msg(10), msg(11)]);
    expect(ids(), ['out', 'm11', 'm10']);
  });
}
