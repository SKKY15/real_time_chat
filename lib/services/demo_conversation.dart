/// Script of the 40 sample messages inserted by the "Add sample messages"
/// action. Pure data, no Firebase types.
library;

import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/reply_preview.dart';

/// One line of the scripted conversation.
class DemoLine {
  const DemoLine(
    this.sender,
    this.text, {
    this.gap = 1,
    this.replyTo,
    this.edited = false,
    this.deleted = false,
  });

  /// Who says it. `null` means the signed-in user, so some bubbles land on
  /// the right-hand side.
  final DemoPersona? sender;

  final String text;

  /// Minutes since the previous line.
  final int gap;

  /// Index (within its list) of the line this one replies to.
  final int? replyTo;

  final bool edited;
  final bool deleted;
}

/// Fictional participants. Their ids start with `demo_`, which is what the
/// security rules use to recognise seeded messages.
enum DemoPersona {
  sara('demo_sara', 'Sara'),
  omar('demo_omar', 'Omar'),
  lina('demo_lina', 'Lina'),
  yacine('demo_yacine', 'Yacine');

  const DemoPersona(this.id, this.displayName);

  final String id;
  final String displayName;
}

const DemoPersona _sara = DemoPersona.sara;
const DemoPersona _omar = DemoPersona.omar;
const DemoPersona _lina = DemoPersona.lina;
const DemoPersona _yacine = DemoPersona.yacine;

/// Yesterday evening: 14 messages.
const List<DemoLine> demoYesterday = <DemoLine>[
  DemoLine(_sara, 'Okay team, weekend plan? 👀'),
  DemoLine(_omar, 'Beach. Obviously. 🏖️'),
  DemoLine(_lina, "It's November, Omar 😂"),
  DemoLine(_omar, "The sea doesn't check the calendar"),
  DemoLine(
    null,
    'What about a day trip to Tipaza? Roman ruins, sea view, grilled fish 🐟',
    gap: 3,
  ),
  DemoLine(_sara, 'Now THAT is a plan 🔥', replyTo: 4),
  DemoLine(
    _yacine,
    'I can drive. The car fits 5 if nobody brings a suitcase '
    '(looking at you, Lina)',
    gap: 2,
  ),
  DemoLine(_lina, 'It was ONE time'),
  DemoLine(_lina, 'And it was a small suitcase', gap: 0),
  DemoLine(null, 'It had wheels, Lina.'),
  DemoLine(_omar, '😂😂😂'),
  DemoLine(_sara, 'Saturday or Sunday?', gap: 4),
  DemoLine(_yacine, "Saturday. Sunday I'm useless before noon", replyTo: 11),
  DemoLine(null, 'Saturday works for me 🙌'),
];

/// Today: 26 messages, the last one a few minutes ago.
const List<DemoLine> demoToday = <DemoLine>[
  DemoLine(_sara, 'Good morning! ☀️ Quick poll: do we leave at 8 or at 9?'),
  DemoLine(_omar, '9'),
  DemoLine(_lina, '8, so we beat the traffic'),
  DemoLine(_yacine, '8:30 and nobody complains', gap: 2),
  DemoLine(null, '8:30 it is. Democracy has spoken.'),
  DemoLine(_omar, '', deleted: true),
  DemoLine(_lina, 'Omar, what did you just delete 👀'),
  DemoLine(_omar, 'Nothing. A typo. Move on.'),
  DemoLine(_sara, "I'll bring coffee and those almond cookies ☕", gap: 3),
  DemoLine(null, "You're officially my favourite person", replyTo: 8),
  DemoLine(_yacine, 'The playlist is my job. No skipping allowed 🎧', gap: 2),
  DemoLine(
    _lina,
    "As long as it's not three hours of the same artist again",
    replyTo: 10,
  ),
  DemoLine(_yacine, 'It was a themed drive.', edited: true),
  DemoLine(_omar, "I'll handle the snacks. And by handle I mean eat.", gap: 2),
  DemoLine(
    null,
    'Can someone share the meeting point? '
    'I always end up on the wrong side of the square 😅',
    gap: 3,
  ),
  DemoLine(
    _sara,
    'In front of the bakery next to the big clock. Hard to miss, it smells '
    "like fresh bread from two streets away. I'll drop a pin tomorrow "
    'morning too.',
    replyTo: 14,
  ),
  DemoLine(null, 'Perfect, thanks!'),
  DemoLine(_lina, 'Forecast says 22° and sunny 🌤️', gap: 4),
  DemoLine(_omar, 'Told you. Beach.', replyTo: 17),
  DemoLine(_lina, "Fine. Bring a towel. I'm not sharing mine."),
  DemoLine(
    _yacine,
    'Also, cameras! Golden hour at the ruins is unreal 📸',
    gap: 2,
  ),
  DemoLine(null, 'On it. Batteries are charging as we speak 🔋'),
  DemoLine(_sara, 'This is going to be so good', gap: 2),
  DemoLine(_sara, "Don't be late!!", gap: 0),
  DemoLine(_omar, "I'm never late. Time is just early."),
  DemoLine(null, 'Screenshotting that for Saturday at 8:45 😄'),
];

/// Added on top of every gap, so back-to-back lines (`gap: 0`) still have a
/// stable order.
const Duration _beat = Duration(seconds: 9);

/// When each line of a block is sent, for a block that starts at [start].
List<DateTime> demoTimes(List<DemoLine> lines, DateTime start) {
  final times = <DateTime>[];
  var time = start;
  for (final line in lines) {
    time = time.add(Duration(minutes: line.gap) + _beat);
    times.add(time);
  }
  return times;
}

/// Yesterday's part starts in the evening of the previous calendar day, so
/// the "Yesterday" separator always shows up.
DateTime demoYesterdayStart(DateTime now) =>
    DateTime(now.year, now.month, now.day - 1, 20);

/// Today's part is scheduled backwards: its last line is sent five minutes
/// before [now]. Backdated messages must not lie in the future from the
/// server's point of view, and this leaves room for a slightly fast clock.
DateTime demoTodayStart(DateTime now) {
  final length = demoTimes(demoToday, now).last.difference(now);
  return now.subtract(length + const Duration(minutes: 5));
}

/// The whole script as messages, oldest first: yesterday evening followed by
/// today, with lines that have no sender spoken by [me].
///
/// [newId] supplies the document id of each message.
List<ChatMessage> demoMessages({
  required AppUser me,
  required DateTime now,
  required String Function() newId,
}) {
  final messages = <ChatMessage>[];

  void addBlock(List<DemoLine> lines, DateTime start) {
    final ids = <String>[for (final _ in lines) newId()];
    final times = demoTimes(lines, start);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final persona = line.sender;
      final replyIndex = line.replyTo;
      final quoted = replyIndex == null ? null : lines[replyIndex];
      messages.add(
        ChatMessage(
          id: ids[i],
          text: line.text,
          senderId: persona?.id ?? me.uid,
          senderName: persona?.displayName ?? me.name,
          createdAt: times[i],
          editedAt: line.edited
              ? times[i].add(const Duration(seconds: 20))
              : null,
          deleted: line.deleted,
          replyTo: quoted == null || replyIndex == null
              ? null
              : ReplyPreview.snippet(
                  messageId: ids[replyIndex],
                  text: quoted.text,
                  senderName: quoted.sender?.displayName ?? me.name,
                ),
          // My scripted messages were "read" by Sara, so they show the
          // double check.
          seenBy: persona == null
              ? <String>[DemoPersona.sara.id]
              : const <String>[],
        ),
      );
    }
  }

  addBlock(demoYesterday, demoYesterdayStart(now));
  addBlock(demoToday, demoTodayStart(now));
  return messages;
}
