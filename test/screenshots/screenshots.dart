// Renders the screenshots in docs/screenshots with the real widgets, fed by
// an in-memory repository holding the sample conversation:
//
//   flutter test --update-goldens test/screenshots/screenshots.dart
//
// Not named `*_test.dart` on purpose. A plain `flutter test` skips this file,
// so pixel differences between machines never fail the test suite.
//
// Text is drawn with the fonts found in test/screenshots/fonts (see
// tool/screenshots.sh, which downloads them). Without them Flutter's test
// font is used and every glyph is a box.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:real_time_chat/app.dart';
import 'package:real_time_chat/models/app_user.dart';
import 'package:real_time_chat/models/chat_message.dart';
import 'package:real_time_chat/models/reply_preview.dart';
import 'package:real_time_chat/models/typing_user.dart';
import 'package:real_time_chat/services/demo_conversation.dart';
import 'package:real_time_chat/services/providers.dart';
import 'package:real_time_chat/theme/app_theme.dart';

import '../support/fake_chat_repository.dart';
import '../support/fakes.dart';
import '../ui/chat_harness.dart';

const Size _window = Size(390, 844);

/// A browser window: wide enough for `RoundedWindow` to box the app in a
/// phone-sized screen, with walls around it.
const Size _desktop = Size(780, 932);
const double _pixelRatio = 2;
const AppUser _nadia = AppUser(uid: 'me', name: 'Nadia');
const String _textFamily = 'Rubik';
const String _arabicFamily = 'Arabic';
const String _emojiFamily = 'Emoji';
const Duration _settle = Duration(milliseconds: 600);

bool _hasTextFont = false;

Future<void> _loadFonts() async {
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();

  final directory = Directory('test/screenshots/fonts');
  if (!directory.existsSync()) return;
  final loaders = <String, FontLoader>{};
  for (final file in directory.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last.toLowerCase();
    if (!name.endsWith('.ttf')) continue;
    final String family;
    if (name.contains('emoji')) {
      family = _emojiFamily;
    } else if (name.contains('arabic')) {
      family = _arabicFamily;
    } else if (name.startsWith('rubik')) {
      family = _textFamily;
    } else {
      continue; // a file left over from another typeface
    }
    loaders
        .putIfAbsent(family, () => FontLoader(family))
        .addFont(
          Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
        );
  }
  for (final loader in loaders.values) {
    await loader.load();
  }
  _hasTextFont = loaders.containsKey(_textFamily);
}

/// Lets [duration] pass frame by frame, so every animation runs to its end.
Future<void> _frames(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 16);
  for (var elapsed = Duration.zero; elapsed < duration; elapsed += frame) {
    await tester.pump(frame);
  }
}

/// The app theme with the downloaded font files instead of `google_fonts`.
ThemeData _theme(Brightness brightness) => AppTheme.build(
  brightness,
  applyFont: (textTheme) => _hasTextFont
      ? textTheme.apply(
          fontFamily: _textFamily,
          fontFamilyFallback: const <String>[_arabicFamily, _emojiFamily],
        )
      : textTheme,
);

/// The sample conversation, ending five minutes ago.
List<ChatMessage> _sampleConversation() {
  var next = 0;
  return demoMessages(
    me: _nadia,
    now: DateTime.now(),
    newId: () => 'demo${next++}',
  );
}

/// Id of line [index] of today's part of the script.
String _today(int index) => 'demo${demoYesterday.length + index}';

Future<ChatHarness> _openChat(
  WidgetTester tester,
  Brightness brightness, {
  List<ChatMessage>? messages,
}) async {
  final h = ChatHarness(tester);
  await h.pump(
    user: _nadia,
    size: _window,
    pixelRatio: _pixelRatio,
    theme: _theme(brightness),
  );
  await h.load(messages ?? _sampleConversation());
  return h;
}

/// Declares one screenshot. Shadows are drawn for real while [body] runs;
/// tests normally replace them with outlines.
void _screenshot(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../docs/screenshots/$name.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  });
}

void main() {
  setUpAll(_loadFonts);

  _screenshot('join', (tester) async {
    tester.view.devicePixelRatio = _pixelRatio;
    tester.view.physicalSize = _desktop * _pixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _BrowserWindow(
        child: ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(FakeAuthService()),
            chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          ],
          child: ChatApp(
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Nadia');
    await _frames(tester, _settle);
  });

  _screenshot('chat_light', (tester) async {
    final h = await _openChat(tester, Brightness.light);
    h.repository.typing.add(const <TypingUser>[
      TypingUser(userId: 'demo_sara', name: 'Sara'),
    ]);
    await h.settle();
    await h.pumpFor(_settle);
  });

  _screenshot('chat_dark', (tester) async {
    final h = await _openChat(tester, Brightness.dark);
    await h.typeMessage('See you all at 8:30 ⏰');
    await h.tapSend();
    await h.pumpFor(_settle);
  });

  _screenshot('reply_dark', (tester) async {
    final h = await _openChat(tester, Brightness.dark);
    await tester.drag(h.bubble(_today(24)), const Offset(140, 0));
    await h.typeMessage('Sure you are 😏');
    await h.pumpFor(_settle);
  });

  _screenshot('swipe_light', (tester) async {
    final h = await _openChat(tester, Brightness.light);
    final gesture = await tester.startGesture(
      tester.getCenter(h.bubble(_today(23))),
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    addTearDown(gesture.removePointer);
  });

  _screenshot('menu_light', (tester) async {
    final h = await _openChat(tester, Brightness.light);
    // A bubble with room below it, where the menu hangs from it.
    await h.openMenu(_today(21));
    await h.pumpFor(_settle);
  });

  _screenshot('unread_light', (tester) async {
    final messages = _sampleConversation();
    final h = await _openChat(tester, Brightness.light, messages: messages);
    await h.scrollUp(1500);
    await h.update(<ChatMessage>[
      ...messages,
      for (var i = 0; i < 2; i++)
        ChatMessage(
          id: 'new$i',
          text: 'New message $i',
          senderId: 'demo_lina',
          senderName: 'Lina',
          createdAt: DateTime.now(),
        ),
    ]);
    await h.pumpFor(_settle);
  });

  _screenshot('empty_dark_framed', (tester) async {
    // The chat screen at the size a browser window gives it: the rounded
    // screen, framed by walls.
    final h = ChatHarness(tester);
    await h.pump(
      user: _nadia,
      size: _desktop,
      pixelRatio: _pixelRatio,
      theme: _theme(Brightness.dark),
    );
    await h.load(const <ChatMessage>[]);
    await h.pumpFor(_settle);
  });

  _screenshot('error_light', (tester) async {
    final h = ChatHarness(tester);
    await h.pump(
      user: _nadia,
      size: _desktop,
      pixelRatio: _pixelRatio,
      theme: _theme(Brightness.light),
    );
    h.repository.latest.addError(StateError('permission-denied'));
    await h.settle();
    await h.pumpFor(_settle);
  });

  for (final brightness in Brightness.values) {
    _screenshot('edge_cases_${brightness.name}', (tester) async {
      final h = await _openChat(
        tester,
        brightness,
        messages: <ChatMessage>[
          chatMessage(1, text: 'ok'),
          chatMessage(
            2,
            sender: 'me',
            text:
                'A longer message that wraps onto a second line and then '
                'keeps going for a little while, to see how the time fits.',
            seenBy: const <String>['sara'],
          ),
          chatMessage(
            3,
            sender: 'omar',
            text:
                'مرحبا بالجميع، كيف حالكم؟ هل أنتم '
                'جاهزون لرحلة يوم السبت إلى الشاطئ؟',
          ),
          chatMessage(
            4,
            sender: 'me',
            text: 'مرحبا عمر 👋',
            edited: true,
            replyTo: const ReplyPreview(
              messageId: 'm3',
              text:
                  'مرحبا بالجميع، كيف حالكم؟ هل أنتم جاهزون لرحلة يوم السبت '
                  'إلى الشاطئ؟',
              senderName: 'Omar',
            ),
          ),
          chatMessage(5, sender: 'omar', text: 'line one\nline two'),
          chatMessage(6, sender: 'omar', deleted: true),
          chatMessage(7, sender: 'me', deleted: true),
          chatMessage(8, sender: 'me', text: '👍'),
          chatMessage(9, sender: 'me', text: 'Sent, not seen yet'),
          chatMessage(
            10,
            sender: 'me',
            text: 'Still sending',
            pending: true,
          ).copyWith(hasServerTimestamp: false),
        ],
      );
      h.repository.sendError = StateError('permission-denied');
      await h.typeMessage('This one is rejected');
      await h.tapSend();
      await h.typeMessage('أراكم يوم السبت');
      await h.pumpFor(_settle);
    });
  }
}

/// A browser window around the app, for the README: a title bar with the three
/// window buttons and the address, and the app below it. The colors are the
/// light theme's neutrals (`ChatColors.light`) and do not follow the theme.
class _BrowserWindow extends StatelessWidget {
  const _BrowserWindow({required this.child});

  final Widget child;

  static const Color _page = Color(0xFFE6E4DD);
  static const Color _bar = Color(0xFFF3F2ED);
  static const Color _field = Color(0xFFFFFFFF);
  static const Color _detail = Color(0xFF716F65);
  static const Color _hairline = Color(0x14000000);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _page,
      child: Directionality(
        // The app's MaterialApp is below this window, so the chrome brings its
        // own reading direction and text style.
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: TextStyle(
            color: _detail,
            fontSize: 15,
            fontFamily: _hasTextFont ? _textFamily : null,
          ),
          child: Column(
            children: <Widget>[
              Container(
                height: 84,
                decoration: const BoxDecoration(
                  color: _bar,
                  border: Border(bottom: BorderSide(color: _hairline)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: <Widget>[
                    for (final color in const <Color>[
                      Color(0xFFE5605A),
                      Color(0xFFE8B33F),
                      Color(0xFF63B76B),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 9),
                        child: SizedBox.square(
                          dimension: 12,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 30),
                    Expanded(
                      child: Container(
                        height: 38,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: _field,
                          borderRadius: BorderRadius.all(Radius.circular(19)),
                        ),
                        child: const Text(
                          'localhost:5000',
                          style: TextStyle(letterSpacing: 0.2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 30),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
