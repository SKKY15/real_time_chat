// Named `widget_test.dart` on purpose: `flutter create .` would otherwise
// generate its counter-app sample test at this path.
import 'package:flutter_test/flutter_test.dart';
import 'package:real_time_chat/chat/message_layout.dart';
import 'package:real_time_chat/models/app_user.dart';
import 'package:real_time_chat/models/chat_message.dart';
import 'package:real_time_chat/models/reply_preview.dart';
import 'package:real_time_chat/services/demo_conversation.dart';
import 'package:real_time_chat/utils/date_labels.dart';

ChatMessage _message(String id, String sender, DateTime createdAt) =>
    ChatMessage(
      id: id,
      text: id,
      senderId: sender,
      senderName: sender,
      createdAt: createdAt,
    );

void main() {
  group('MessageLayout', () {
    final day = DateTime(2026, 11, 11, 10);
    // Newest first, exactly like the list the UI renders.
    final messages = <ChatMessage>[
      _message('f', 'omar', day.add(const Duration(minutes: 30))),
      _message('e', 'sara', day.add(const Duration(minutes: 12))),
      _message('d', 'sara', day.add(const Duration(minutes: 2))),
      _message('c', 'sara', day.add(const Duration(minutes: 1))),
      _message('b', 'sara', day),
      _message('a', 'sara', day.subtract(const Duration(days: 1))),
    ];

    MessageLayout at(String id) =>
        MessageLayout.at(messages, messages.indexWhere((m) => m.id == id));

    test('shows a date separator above the first message of each day', () {
      expect(at('a').showDateSeparator, isTrue, reason: 'oldest loaded');
      expect(at('b').showDateSeparator, isTrue, reason: 'new day');
      expect(at('c').showDateSeparator, isFalse);
      expect(at('f').showDateSeparator, isFalse);
    });

    test('groups consecutive messages of one sender', () {
      expect(at('b').isFirstInGroup, isTrue);
      expect(at('b').isLastInGroup, isFalse);
      expect(at('c').isFirstInGroup, isFalse);
      expect(at('c').isLastInGroup, isFalse);
      expect(at('d').isFirstInGroup, isFalse);
    });

    test('only the last bubble of a group gets the tail', () {
      final tails = [
        for (final m in messages)
          if (at(m.id).isLastInGroup) m.id,
      ];
      expect(tails, ['f', 'e', 'd', 'a']);
    });

    test('a long pause starts a new group for the same sender', () {
      expect(at('d').isLastInGroup, isTrue);
      expect(at('e').isFirstInGroup, isTrue);
    });

    test('a new day always starts a new group', () {
      expect(at('a').isLastInGroup, isTrue);
      expect(at('b').isFirstInGroup, isTrue);
    });

    test('a different sender starts a new group', () {
      expect(at('f').isFirstInGroup, isTrue);
      expect(at('f').isLastInGroup, isTrue);
    });

    test('a single message is a complete group', () {
      final layout = MessageLayout.at([messages.first], 0);
      expect(layout.showDateSeparator, isTrue);
      expect(layout.isFirstInGroup, isTrue);
      expect(layout.isLastInGroup, isTrue);
    });
  });

  group('DateLabels', () {
    final now = DateTime(2026, 11, 11, 9, 30); // a Wednesday

    test('labels today and yesterday', () {
      expect(DateLabels.day(DateTime(2026, 11, 11, 0, 1), now: now), 'Today');
      expect(
        DateLabels.day(DateTime(2026, 11, 10, 23, 59), now: now),
        'Yesterday',
      );
    });

    test('uses the weekday for the rest of the past week', () {
      expect(DateLabels.day(DateTime(2026, 11, 9, 8), now: now), 'Monday');
      expect(DateLabels.day(DateTime(2026, 11, 5, 8), now: now), 'Thursday');
    });

    test('falls back to the date for anything older', () {
      expect(DateLabels.day(DateTime(2026, 11, 4, 8), now: now), 'November 4');
      expect(
        DateLabels.day(DateTime(2025, 12, 31, 8), now: now),
        'December 31, 2025',
      );
    });

    test('yesterday is a calendar day, not "24 hours ago"', () {
      final earlyMorning = DateTime(2026, 11, 11, 0, 10);
      expect(
        DateLabels.day(DateTime(2026, 11, 10, 0, 5), now: earlyMorning),
        'Yesterday',
      );
    });

    test('formats bubble times in 24h and 12h style', () {
      final time = DateTime(2026, 11, 11, 17, 5);
      expect(DateLabels.time(time), '17:05');
      expect(
        DateLabels.time(time, use24HourFormat: false),
        matches(RegExp(r'^5:05\sPM$')),
      );
    });
  });

  group('sample conversation', () {
    test('has 40 messages', () {
      expect(demoYesterday.length + demoToday.length, 40);
    });

    test('is a believable script', () {
      for (final lines in [demoYesterday, demoToday]) {
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          expect(line.gap, greaterThanOrEqualTo(0));
          expect(line.text.isEmpty, line.deleted, reason: 'line $i');
          expect(line.text.length, lessThan(400));
          final replyTo = line.replyTo;
          if (replyTo != null) {
            expect(replyTo, lessThan(i), reason: 'replies point backwards');
            expect(lines[replyTo].deleted, isFalse);
          }
        }
      }
    });

    test('is scheduled in order and never in the future', () {
      for (final now in [
        DateTime(2026, 11, 11, 9, 30),
        DateTime(2026, 11, 11, 0, 10),
        DateTime(2026, 11, 11, 20, 30),
        DateTime(2026, 3, 1, 23, 59),
      ]) {
        final yesterday = demoTimes(demoYesterday, demoYesterdayStart(now));
        final today = demoTimes(demoToday, demoTodayStart(now));
        final all = [...yesterday, ...today];
        for (var i = 1; i < all.length; i++) {
          expect(all[i].isAfter(all[i - 1]), isTrue, reason: '$now, line $i');
        }
        expect(today.last, now.subtract(const Duration(minutes: 5)));
        for (final time in yesterday) {
          expect(DateLabels.day(time, now: now), 'Yesterday');
        }
      }
    });

    test('mixes my messages with those of several other people', () {
      final all = [...demoYesterday, ...demoToday];
      final mine = all.where((line) => line.sender == null).length;
      final others = {
        for (final line in all)
          line.sender,
      };
      expect(mine, inInclusiveRange(6, 14));
      expect(others, hasLength(DemoPersona.values.length));
      expect(all.where((line) => line.edited), isNotEmpty);
      expect(all.where((line) => line.deleted), isNotEmpty);
      expect(all.where((line) => line.replyTo != null).length, greaterThan(3));
    });
  });

  group('demoMessages', () {
    List<ChatMessage> build(DateTime now) {
      var next = 0;
      return demoMessages(
        me: const AppUser(uid: 'me', name: 'Nadia'),
        now: now,
        newId: () => 'id${next++}',
      );
    }

    test('turns the script into 40 messages, oldest first', () {
      final now = DateTime(2026, 11, 11, 15, 30);
      final messages = build(now);
      expect(messages, hasLength(40));
      expect({for (final message in messages) message.id}, hasLength(40));
      for (var i = 1; i < messages.length; i++) {
        expect(
          messages[i].createdAt.isAfter(messages[i - 1].createdAt),
          isTrue,
          reason: 'message $i',
        );
      }
      expect(messages.last.createdAt.isBefore(now), isTrue);
      expect(messages.where((message) => message.deleted), hasLength(1));
      expect(messages.where((message) => message.isEdited), isNotEmpty);
    });

    test('speaks the lines without a sender in my name', () {
      final mine = build(DateTime(2026, 11, 11, 15, 30))
          .where((message) => message.senderId == 'me');
      expect(mine, isNotEmpty);
      for (final message in mine) {
        expect(message.senderName, 'Nadia');
        expect(message.status, MessageStatus.seen);
      }
    });

    test('quotes point at earlier messages of the same conversation', () {
      final messages = build(DateTime(2026, 11, 11, 15, 30));
      final byId = {for (final message in messages) message.id: message};
      var replies = 0;
      for (final message in messages) {
        final reply = message.replyTo;
        if (reply == null) continue;
        replies++;
        final quoted = byId[reply.messageId];
        expect(quoted, isNotNull);
        expect(quoted!.createdAt.isBefore(message.createdAt), isTrue);
        expect(reply.senderName, quoted.senderName);
        expect(reply.text, isNotEmpty);
      }
      expect(replies, greaterThan(3));
    });
  });

  group('ReplyPreview', () {
    test('flattens and shortens the quoted text', () {
      final preview = ReplyPreview.snippet(
        messageId: 'm1',
        text: 'line one\n\nline   two ${'x' * 300}',
        senderName: 'Sara',
      );
      expect(preview.text, startsWith('line one line two xxx'));
      expect(preview.text.length, ReplyPreview.maxSnippetLength);
      expect(preview.text, endsWith('…'));
    });

    test('round-trips through its Firestore map', () {
      const preview = ReplyPreview(
        messageId: 'm1',
        text: 'hello',
        senderName: 'Sara',
      );
      expect(ReplyPreview.fromMap(preview.toMap()), preview);
    });

    test('tolerates missing or malformed data', () {
      expect(ReplyPreview.fromMap(null), isNull);
      expect(ReplyPreview.fromMap('nope'), isNull);
      expect(ReplyPreview.fromMap({'text': 'no id'}), isNull);
      expect(ReplyPreview.fromMap({'messageId': 'm1'})?.text, '');
    });
  });
}
