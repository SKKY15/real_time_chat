import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:real_time_chat/models/chat_message.dart';
import 'package:real_time_chat/models/reply_preview.dart';
import 'package:real_time_chat/models/typing_user.dart';
import 'package:real_time_chat/widgets/composer_banner.dart';
import 'package:real_time_chat/widgets/reply_quote.dart';
import 'package:real_time_chat/widgets/scroll_to_bottom_button.dart';
import 'package:real_time_chat/widgets/send_button.dart';
import 'package:real_time_chat/widgets/typing_indicator.dart';
import 'package:real_time_chat/widgets/user_avatar.dart';

import 'chat_harness.dart';

const Duration _short = Duration(milliseconds: 400);

void main() {
  group('history', () {
    testWidgets('shows a spinner until the first snapshot arrives', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Lounge'), findsOneWidget);
      expect(find.text('You are Me'), findsOneWidget);
    });

    testWidgets('an empty room offers the sample conversation', (tester) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(const <ChatMessage>[]);

      expect(find.text('No messages yet'), findsOneWidget);
      await tester.tap(find.text('Add 40 sample messages'));
      await h.settle();
      expect(h.seeder.calls, 1);
    });

    testWidgets('says so when the sample conversation cannot be written', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(const <ChatMessage>[]);

      h.seeder.error = StateError('permission-denied');
      await tester.tap(find.text('Add 40 sample messages'));
      await h.settle();
      await h.pumpFor(_short);
      expect(
        find.textContaining('Could not add the sample messages'),
        findsOneWidget,
      );
    });

    testWidgets('a failing query shows an error that can be retried', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      h.repository.latest.addError(StateError('permission-denied'));
      await h.settle();
      await h.pumpFor(_short);

      expect(find.text("Couldn't load the chat"), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await h.settle();
      expect(h.repository.latestQueries, hasLength(2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await h.load(conversation(1, 3));
      expect(h.bubble('m3'), findsOneWidget);
      expect(find.text("Couldn't load the chat"), findsNothing);
    });

    testWidgets('groups, names, day separators and message states', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      final yesterday = at(0).subtract(const Duration(days: 1));
      await h.load(<ChatMessage>[
        chatMessage(1, time: yesterday, text: 'Old news'),
        chatMessage(
          2,
          time: yesterday.add(const Duration(minutes: 1)),
          sender: 'me',
          text: 'Seen it',
          seenBy: const <String>['sara'],
        ),
        chatMessage(10, text: 'Morning!'),
        chatMessage(11, text: 'Anyone up?'),
        chatMessage(12, sender: 'omar', text: 'Barely', edited: true),
        chatMessage(13, sender: 'omar', deleted: true),
        chatMessage(
          14,
          sender: 'me',
          text: 'Coffee first',
          replyTo: const ReplyPreview(
            messageId: 'm11',
            text: 'Anyone up?',
            senderName: 'Sara',
          ),
        ),
        chatMessage(15, sender: 'me', text: 'Then work', pending: true),
      ]);

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);

      // Incoming groups carry the name once (plus the name inside the
      // quote); my own bubbles carry none.
      expect(find.text('Sara'), findsNWidgets(3));
      expect(find.text('Omar'), findsOneWidget);
      expect(find.text('Me'), findsNothing);
      // One avatar per incoming group, next to its last bubble.
      expect(find.byType(UserAvatar), findsNWidgets(3));

      expect(find.text('edited  '), findsWidgets);
      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.byType(ReplyQuote), findsOneWidget);

      // Seen, sent and still sending.
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);

      // Mine on the right, theirs on the left.
      expect(tester.getTopRight(h.bubble('m15')).dx, greaterThan(300));
      expect(tester.getTopLeft(h.bubble('m10')).dx, lessThan(60));

      // What is on screen has been read: every stored message of the others
      // gets a receipt, deleted ones and my own do not.
      expect(
        h.repository.seen.expand((ids) => ids),
        unorderedEquals(<String>['m1', 'm10', 'm11', 'm12']),
      );
    });

    testWidgets('a bubble is as wide as its longest line', (tester) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(<ChatMessage>[
        chatMessage(1, text: 'ok'),
        // Too long for one line: breaks after the first word.
        chatMessage(2, sender: 'omar', text: 'aaaaaaaaaaaaa bbbb'),
        chatMessage(3, sender: 'me', text: 'aaaaaaaaaaaaa bbbb'),
      ]);

      const widest = 390 * 0.78;
      final oneLine = tester.getSize(h.bubble('m1'));
      for (final id in <String>['m2', 'm3']) {
        final wrapped = tester.getSize(h.bubble(id));
        expect(wrapped.width, greaterThan(oneLine.width));
        expect(wrapped.width, lessThan(widest - 20));
      }
      // Both wrapped: the first two carry a name, so they compare directly.
      expect(
        tester.getSize(h.bubble('m2')).height,
        greaterThan(oneLine.height + 10),
      );
      expect(tester.getSize(h.bubble('m3')).height, greaterThan(50));
    });
  });

  group('sending', () {
    testWidgets('shows the message at once and follows its delivery', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      final history = conversation(1, 6);
      await h.load(history);

      SendButton sendButton() =>
          tester.widget<SendButton>(find.byType(SendButton));
      expect(sendButton().enabled, isFalse);
      await h.typeMessage('  Hello there  ');
      expect(sendButton().enabled, isTrue);

      await h.tapSend();
      final sent = h.repository.sent.single;
      expect(sent.text, 'Hello there');
      expect(sent.senderId, 'me');
      expect(h.composerText, isEmpty);
      expect(sendButton().enabled, isFalse);
      expect(h.messageIds.first, sent.id);
      await h.frames();
      expect(h.bubble(sent.id), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      await h.pumpFor(_short);

      // The server stores it.
      final stored = ChatMessage(
        id: sent.id,
        text: sent.text,
        senderId: 'me',
        senderName: 'Me',
        createdAt: at(30),
      );
      await h.update(<ChatMessage>[...history, stored]);
      await h.pumpFor(_short);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);

      // Somebody reads it.
      await h.update(<ChatMessage>[
        ...history,
        stored.copyWith(seenBy: const <String>['sara']),
      ]);
      await h.pumpFor(_short);
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(h.bubble(sent.id), findsOneWidget);
      expect(h.messageIds, hasLength(7));
    });

    testWidgets('a rejected message can be sent again or discarded', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(1, 6));

      h.repository.sendError = StateError('permission-denied');
      await h.typeMessage('Will not go through');
      await h.tapSend();
      await h.pumpFor(_short);
      final id = h.repository.sent.single.id;
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      h.repository.sendError = StateError('permission-denied');
      await h.openMenu(id);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Reply'), findsNothing);
      await h.chooseMenuItem('Try again');
      expect(h.repository.sent, hasLength(2));
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      await h.openMenu(id);
      await h.chooseMenuItem('Discard');
      expect(h.bubble(id), findsNothing);
      expect(h.messageIds, hasLength(6));
    });

    testWidgets('announces my typing and stops when idle or sent', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(1, 6));

      await h.typeMessage('H');
      expect(h.repository.typingEvents, <String>['set Me']);
      await h.typeMessage('He');
      expect(h.repository.typingEvents, <String>['set Me']);

      await tester.pump(const Duration(seconds: 4));
      expect(h.repository.typingEvents, <String>['set Me', 'clear me']);

      await h.typeMessage('Hey');
      await h.tapSend();
      expect(h.repository.typingEvents, <String>[
        'set Me',
        'clear me',
        'set Me',
        'clear me',
      ]);
      await h.pumpFor(_short);
    });
  });

  group('receiving', () {
    testWidgets('a new message appears at the bottom and is marked as seen', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      final history = conversation(1, 6);
      await h.load(history);
      expect(h.repository.seen, hasLength(1));

      await h.update(<ChatMessage>[
        ...history,
        chatMessage(7, sender: 'omar', text: 'Fresh one'),
      ]);
      await h.frames();
      expect(h.bubble('m7'), findsOneWidget);
      expect(h.repository.seen.last, <String>['m7']);

      // The row grows into place instead of popping in.
      final entering = tester.getSize(h.row('m7')).height;
      await h.pumpFor(_short);
      expect(tester.getSize(h.row('m7')).height, greaterThan(entering));
      expect(h.scroll.pixels, 0);
    });

    testWidgets('while reading history new messages wait behind the button', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      final history = conversation(1, 40);
      await h.load(history);
      expect(h.jumpButtonVisible, isFalse);

      await h.scrollUp(600);
      expect(h.scroll.pixels, greaterThan(300));
      expect(h.jumpButtonVisible, isTrue);

      final offset = h.scroll.pixels;
      final anchor = tester.getTopLeft(h.row('m20'));
      await h.update(<ChatMessage>[
        ...history,
        chatMessage(41, text: 'You missed this'),
      ]);
      await h.pumpFor(_short);
      // Nothing moved, the message is counted on the button instead.
      expect(h.messageIds, isNot(contains('m41')));
      expect(h.state.unreadCount, 1);
      expect(find.text('1'), findsOneWidget);
      expect(h.scroll.pixels, offset);
      expect(tester.getTopLeft(h.row('m20')), anchor);

      await tester.tap(find.byType(ScrollToBottomButton));
      await h.pumpFor(const Duration(milliseconds: 700));
      expect(h.scroll.pixels, 0);
      expect(h.bubble('m41'), findsOneWidget);
      expect(h.state.unreadCount, 0);
      expect(h.jumpButtonVisible, isFalse);
      expect(h.repository.seen.last, <String>['m41']);
    });

    testWidgets('shows who is typing', (tester) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(1, 6));
      double height() => tester.getSize(find.byType(TypingIndicator)).height;
      expect(height(), 0);

      h.repository.typing.add(const <TypingUser>[
        TypingUser(userId: 'sara', name: 'Sara'),
      ]);
      await h.settle();
      await h.pumpFor(_short);
      expect(find.text('Sara is typing…'), findsOneWidget);
      expect(height(), greaterThan(20));

      // My own typing document never shows up.
      h.repository.typing.add(const <TypingUser>[
        TypingUser(userId: 'sara', name: 'Sara'),
        TypingUser(userId: 'omar', name: 'Omar'),
        TypingUser(userId: 'me', name: 'Me'),
      ]);
      await h.settle();
      await h.pumpFor(_short);
      expect(find.text('Omar and Sara are typing…'), findsOneWidget);

      // The row fades out first, then the space it took closes.
      h.repository.typing.add(const <TypingUser>[]);
      await h.settle();
      await h.pumpFor(const Duration(milliseconds: 700));
      expect(find.textContaining('typing…'), findsNothing);
      expect(height(), 0);
    });
  });

  group('history paging', () {
    testWidgets('older messages load on demand without moving the list', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(31, 60));
      expect(h.state.hasMore, isTrue);

      await h.scrollUp(500);
      expect(h.repository.older, hasLength(1));
      expect(h.state.isLoadingMore, isTrue);

      final anchor = tester.getTopLeft(h.row('m42'));
      h.repository.older.single.controller.add(batchOf(conversation(1, 30)));
      await h.settle();
      expect(h.messageIds, hasLength(60));
      expect(h.state.isLoadingMore, isFalse);
      expect(tester.getTopLeft(h.row('m42')), anchor);

      // At the very top the next page is requested; an empty one means the
      // beginning has been reached.
      h.scroll.jumpTo(h.scroll.maxScrollExtent);
      await h.settle();
      expect(h.repository.older, hasLength(2));
      h.repository.older.last.controller.add(batchOf(const <ChatMessage>[]));
      await h.settle();
      h.scroll.jumpTo(h.scroll.maxScrollExtent);
      await h.settle();
      expect(h.state.hasMore, isFalse);
      expect(
        find.text('This is the beginning of the conversation'),
        findsOneWidget,
      );
    });

    testWidgets('the newest message stays in place when the keyboard opens', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(1, 40));
      final before = tester.getBottomLeft(h.row('m40')).dy;

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await h.settle();
      expect(h.scroll.pixels, 0);
      expect(tester.getBottomLeft(h.row('m40')).dy, closeTo(before - 300, 0.5));
    });
  });

  group('reply', () {
    testWidgets('swiping a bubble to the right starts a reply', (tester) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(1, 6));
      double bannerHeight() =>
          tester.getSize(find.byType(ComposerBanner)).height;
      expect(bannerHeight(), 0);

      await tester.drag(h.bubble('m4'), const Offset(140, 0));
      await h.pumpFor(_short);
      expect(find.text('Reply to Omar'), findsOneWidget);
      expect(bannerHeight(), greaterThan(30));

      await h.typeMessage('Agreed');
      await h.tapSend();
      final sent = h.repository.sent.single;
      expect(sent.text, 'Agreed');
      expect(sent.replyTo?.messageId, 'm4');
      expect(sent.replyTo?.senderName, 'Omar');
      expect(sent.replyTo?.text, 'message 4');

      await h.pumpFor(_short);
      expect(bannerHeight(), 0);
      // The new bubble quotes the original.
      expect(
        find.descendant(
          of: h.bubble(sent.id),
          matching: find.byType(ReplyQuote),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a short swipe or a swipe to the left does nothing', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(1, 6));

      await tester.drag(h.bubble('m4'), const Offset(50, 0));
      await h.pumpFor(_short);
      await tester.drag(h.bubble('m4'), const Offset(-140, 0));
      await h.pumpFor(_short);
      expect(tester.getSize(find.byType(ComposerBanner)).height, 0);
      expect(tester.getTopLeft(h.bubble('m4')).dx, lessThan(60));
    });

    testWidgets('the reply can be cancelled', (tester) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(1, 6));

      await h.openMenu('m4');
      await h.chooseMenuItem('Reply');
      expect(find.text('Reply to Omar'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel'));
      await h.pumpFor(_short);
      expect(tester.getSize(find.byType(ComposerBanner)).height, 0);

      await h.typeMessage('Not a reply');
      await h.tapSend();
      expect(h.repository.sent.single.replyTo, isNull);
      await h.pumpFor(_short);
    });

    testWidgets('tapping a quote jumps to the original message', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(<ChatMessage>[
        ...conversation(1, 40),
        chatMessage(
          41,
          sender: 'me',
          text: 'About that',
          replyTo: const ReplyPreview(
            messageId: 'm3',
            text: 'message 3',
            senderName: 'Omar',
          ),
        ),
      ]);
      expect(h.row('m3'), findsNothing);

      await tester.tap(find.byType(ReplyQuote));
      await h.pumpFor(const Duration(seconds: 1));
      expect(h.row('m3'), findsOneWidget);
      final row = tester.getRect(h.row('m3'));
      final list = tester.getRect(find.byType(ListView));
      expect(row.top, greaterThanOrEqualTo(list.top));
      expect(row.bottom, lessThanOrEqualTo(list.bottom));

      // Let the highlight fade out.
      await h.pumpFor(const Duration(milliseconds: 1300));
    });

    testWidgets('loads older pages when the original is not there yet', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(<ChatMessage>[
        ...conversation(11, 40),
        chatMessage(
          41,
          sender: 'me',
          text: 'About that',
          replyTo: const ReplyPreview(
            messageId: 'm3',
            text: 'message 3',
            senderName: 'Omar',
          ),
        ),
      ]);
      expect(h.messageIds, isNot(contains('m3')));

      await tester.tap(find.byType(ReplyQuote));
      await h.settle();
      expect(h.repository.older, hasLength(1));
      h.repository.older.single.controller.add(batchOf(conversation(1, 10)));
      await h.pumpFor(const Duration(seconds: 1));

      expect(h.row('m3'), findsOneWidget);
      final row = tester.getRect(h.row('m3'));
      final list = tester.getRect(find.byType(ListView));
      expect(row.top, greaterThanOrEqualTo(list.top));
      expect(row.bottom, lessThanOrEqualTo(list.bottom));
      await h.pumpFor(const Duration(milliseconds: 1300));
    });

    testWidgets('says so when the original no longer exists', (tester) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(<ChatMessage>[
        ...conversation(1, 6),
        chatMessage(
          7,
          sender: 'me',
          text: 'About that',
          replyTo: const ReplyPreview(
            messageId: 'gone',
            text: 'something',
            senderName: 'Omar',
          ),
        ),
      ]);

      await tester.tap(find.byType(ReplyQuote));
      await h.settle();
      await h.pumpFor(_short);
      expect(
        find.text('The original message is not available'),
        findsOneWidget,
      );
    });
  });

  group('message menu', () {
    testWidgets('opens beside the bubble, on its side of the screen', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(<ChatMessage>[
        ...conversation(1, 20),
        chatMessage(
          21,
          sender: 'me',
          text: 'Mine',
        ).copyWith(hasServerTimestamp: false),
        chatMessage(22, text: 'Theirs'),
      ]);

      // In the upper half of the screen: right below the bubble.
      final upper = <String>[for (var n = 1; n <= 20; n++) 'm$n']
          .firstWhere((id) {
            final finder = h.bubble(id);
            if (finder.evaluate().isEmpty) return false;
            final rect = tester.getRect(finder);
            return rect.top > 120 && rect.bottom < 320;
          });
      await h.openMenu(upper);
      var bubble = tester.getRect(h.bubble(upper));
      expect(h.menuRect.top, closeTo(bubble.bottom + 6, 0.5));
      expect(h.menuRect.left, closeTo(bubble.left + 6, 0.5));
      await h.dismissMenu();

      // The last message has no room below: right above the bubble.
      await h.openMenu('m22');
      bubble = tester.getRect(h.bubble('m22'));
      expect(h.menuRect.bottom, closeTo(bubble.top - 6, 0.5));
      expect(h.menuRect.left, closeTo(bubble.left + 6, 0.5));
      await h.dismissMenu();

      // My own bubbles sit on the right, and so does their menu.
      await h.openMenu('m21');
      bubble = tester.getRect(h.bubble('m21'));
      expect(h.menuRect.right, closeTo(bubble.right - 6, 0.5));
      expect(h.menuRect.overlaps(bubble), isFalse);
      await h.dismissMenu();

      // An open keyboard stays open, so the menu has to stay above it.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await h.pumpFor(const Duration(milliseconds: 300));
      await h.openMenu('m22');
      bubble = tester.getRect(h.bubble('m22'));
      expect(h.menuRect.bottom, closeTo(bubble.top - 6, 0.5));
      expect(bubble.bottom, lessThan(780 - 300));
    });

    testWidgets('opens at the finger when the bubble fills the screen', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(<ChatMessage>[
        chatMessage(1, text: List<String>.filled(60, 'line').join('\n')),
      ]);

      await tester.longPressAt(const Offset(120, 400));
      await h.pumpFor(const Duration(milliseconds: 400));
      expect(find.text('Reply'), findsOneWidget);
      expect(h.menuRect.top, closeTo(400, 0.5));
    });

    testWidgets("somebody else's message can be replied to and copied", (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments as Map<Object?, Object?>;
            copied = arguments['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(1, 6));

      await h.openMenu('m4');
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete for everyone'), findsNothing);

      await h.chooseMenuItem('Copy');
      expect(copied, 'message 4');
      expect(find.text('Message copied'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('my message can be edited, and the draft comes back', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      final others = conversation(1, 5);
      await h.load(<ChatMessage>[
        ...others,
        chatMessage(6, sender: 'me', text: 'Frist!'),
      ]);
      SendButton sendButton() =>
          tester.widget<SendButton>(find.byType(SendButton));

      await h.typeMessage('half a draft');
      await h.openMenu('m6');
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete for everyone'), findsOneWidget);
      await h.chooseMenuItem('Edit');

      expect(find.text('Edit message'), findsOneWidget);
      expect(h.composerText, 'Frist!');
      expect(sendButton().isEditing, isTrue);

      await h.typeMessage('First!');
      await h.tapSend();
      expect(h.repository.edits, <String, String>{'m6': 'First!'});
      expect(h.repository.sent, isEmpty);
      expect(h.composerText, 'half a draft');
      expect(sendButton().isEditing, isFalse);
      await h.pumpFor(_short);
      expect(tester.getSize(find.byType(ComposerBanner)).height, 0);

      // Firestore echoes the edit.
      await h.update(<ChatMessage>[
        ...others,
        chatMessage(6, sender: 'me', text: 'First!', edited: true),
      ]);
      expect(find.textContaining('First!'), findsOneWidget);
      expect(find.text('edited  '), findsWidgets);
    });

    testWidgets('my message can be deleted for everyone', (tester) async {
      final h = ChatHarness(tester);
      await h.pump();
      final others = conversation(1, 5);
      await h.load(<ChatMessage>[
        ...others,
        chatMessage(6, sender: 'me', text: 'Oops'),
      ]);

      await h.openMenu('m6');
      await h.chooseMenuItem('Delete for everyone');
      expect(h.repository.deleted, <String>['m6']);

      await h.update(<ChatMessage>[
        ...others,
        chatMessage(6, sender: 'me', deleted: true),
      ]);
      await h.pumpFor(_short);
      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.textContaining('Oops'), findsNothing);

      // What is deleted has no menu and cannot be replied to.
      await tester.longPress(h.bubble('m6'));
      await h.pumpFor(_short);
      expect(find.text('Reply'), findsNothing);
      await tester.drag(h.bubble('m6'), const Offset(-140, 0));
      await tester.drag(h.bubble('m6'), const Offset(140, 0));
      await h.pumpFor(_short);
      expect(tester.getSize(find.byType(ComposerBanner)).height, 0);
    });

    testWidgets('deleting the message being edited leaves edit mode', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(<ChatMessage>[
        ...conversation(1, 5),
        chatMessage(6, sender: 'me', text: 'Oops'),
      ]);

      await h.openMenu('m6');
      await h.chooseMenuItem('Edit');
      expect(h.composerText, 'Oops');

      await h.openMenu('m6');
      await h.chooseMenuItem('Delete for everyone');
      expect(h.repository.deleted, <String>['m6']);
      expect(h.composerText, isEmpty);
      expect(
        tester.widget<SendButton>(find.byType(SendButton)).isEditing,
        isFalse,
      );
    });
  });

  group('right-to-left text', () {
    testWidgets('messages and the text field follow the script', (
      tester,
    ) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(<ChatMessage>[
        chatMessage(1, text: 'Hello'),
        chatMessage(2, text: 'مرحبا بالجميع'),
      ]);

      // Laid out right to left, with the time on a line of its own.
      final arabic = find.text('مرحبا بالجميع');
      expect(tester.widget<Text>(arabic).textDirection, TextDirection.rtl);
      final time = find.descendant(
        of: h.bubble('m2'),
        matching: find.textContaining('10:02'),
      );
      expect(time, findsOneWidget);
      expect(
        tester.getTopLeft(time).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(arabic).dy),
      );

      TextDirection? fieldDirection() =>
          tester.widget<TextField>(find.byType(TextField)).textDirection;
      expect(fieldDirection(), isNull);
      await h.typeMessage('مرحبا');
      expect(fieldDirection(), TextDirection.rtl);
      await h.typeMessage('Hello');
      expect(fieldDirection(), isNull);
    });
  });

  group('app bar menu', () {
    testWidgets('adds the sample conversation', (tester) async {
      final h = ChatHarness(tester);
      await h.pump();
      await h.load(conversation(1, 6));

      await tester.tap(find.byTooltip('More'));
      await h.pumpFor(_short);
      expect(find.text('Sign out'), findsOneWidget);
      await tester.tap(find.text('Add 40 sample messages'));
      await h.pumpFor(_short);
      expect(h.seeder.calls, 1);
      expect(find.text('Added 40 sample messages'), findsOneWidget);
    });
  });
}
