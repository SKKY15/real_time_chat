import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:real_time_chat/models/chat_message.dart';
import 'package:real_time_chat/models/reply_preview.dart';
import 'package:real_time_chat/models/typing_user.dart';

import 'chat_harness.dart';

/// Messages picked to break layouts: very long, unbreakable, right-to-left,
/// multi-line, tiny, quoted, edited, deleted, pending.
List<ChatMessage> _awkwardConversation() {
  final long = List<String>.filled(40, 'lorem ipsum dolor sit').join(' ');
  return <ChatMessage>[
    chatMessage(1, text: 'ok'),
    chatMessage(2, text: long),
    chatMessage(3, sender: 'me', text: long, seenBy: const <String>['sara']),
    chatMessage(4, sender: 'me', text: 'A' * 150),
    chatMessage(5, text: 'https://example.com/${'path/' * 40}'),
    chatMessage(6, sender: 'omar', text: 'مرحبا بالجميع، كيف حالكم اليوم؟'),
    chatMessage(7, sender: 'me', text: 'שלום לכולם', edited: true),
    chatMessage(8, text: 'line one\nline two\n\nline four'),
    chatMessage(9, sender: 'me', text: '👍'),
    chatMessage(
      10,
      sender: 'bartholomew_the_magnificent_of_the_extremely_long_names',
      text: 'hi',
    ),
    chatMessage(
      11,
      sender: 'me',
      text: 'short',
      replyTo: ReplyPreview(messageId: 'm2', text: long, senderName: 'Sara'),
    ),
    chatMessage(
      12,
      text: 'A reply to something that lost its text',
      replyTo: const ReplyPreview(messageId: 'gone', text: '', senderName: ''),
    ),
    chatMessage(
      13,
      sender: 'me',
      text: 'x',
      edited: true,
      seenBy: const <String>['sara'],
      replyTo: const ReplyPreview(
        messageId: 'm10',
        text: 'hi',
        senderName: 'Bartholomew_the_magnificent_of_the_extremely_long_names',
      ),
    ),
    chatMessage(14, sender: 'omar', deleted: true),
    chatMessage(15, sender: 'me', deleted: true),
    chatMessage(16, sender: 'omar', text: 'edited by Omar', edited: true),
    chatMessage(17, sender: 'me', text: 'still sending', pending: true),
  ];
}

void main() {
  const sizes = <String, Size>{
    'small phone': Size(320, 480),
    'phone': Size(390, 844),
    'landscape': Size(844, 390),
    'tablet': Size(1024, 768),
  };

  for (final MapEntry(key: device, value: size) in sizes.entries) {
    for (final brightness in Brightness.values) {
      for (final textScale in <double>[1, 1.4]) {
        testWidgets(
          'no overflow: $device, ${brightness.name}, text x$textScale',
          (tester) async {
            final h = ChatHarness(tester);
            await h.pump(
              brightness: brightness,
              size: size,
              textScale: textScale,
            );
            await h.load(_awkwardConversation());

            // A reply banner, somebody typing and a draft, all at once.
            await h.openMenu('m17');
            await h.dismissMenu();
            await tester.drag(h.bubble('m16'), const Offset(160, 0));
            h.repository.typing.add(const <TypingUser>[
              TypingUser(userId: 'sara', name: 'Sara'),
              TypingUser(userId: 'omar', name: 'Omar'),
              TypingUser(userId: 'lina', name: 'Lina'),
            ]);
            await h.typeMessage('A draft\nwith\nseveral\nlines\nof\ntext');
            await h.pumpFor(const Duration(milliseconds: 400));

            // Walk through the whole history so every row gets built.
            final scroll = h.scroll;
            while (scroll.pixels < scroll.maxScrollExtent) {
              scroll.jumpTo(
                math.min(scroll.pixels + 200, scroll.maxScrollExtent),
              );
              await tester.pump();
            }
            await h.pumpFor(const Duration(milliseconds: 300));
            expect(h.jumpButtonVisible, isTrue);
          },
        );
      }
    }
  }
}
