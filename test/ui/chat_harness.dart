import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:real_time_chat/auth/auth_controller.dart';
import 'package:real_time_chat/chat/chat_controller.dart';
import 'package:real_time_chat/chat/chat_screen.dart';
import 'package:real_time_chat/chat/chat_state.dart';
import 'package:real_time_chat/models/app_user.dart';
import 'package:real_time_chat/models/chat_message.dart';
import 'package:real_time_chat/models/reply_preview.dart';
import 'package:real_time_chat/services/chat_repository.dart';
import 'package:real_time_chat/services/demo_seeder.dart';
import 'package:real_time_chat/services/providers.dart';
import 'package:real_time_chat/theme/app_theme.dart';
import 'package:real_time_chat/widgets/message_bubble.dart';
import 'package:real_time_chat/widgets/message_row.dart';
import 'package:real_time_chat/widgets/rounded_window.dart';
import 'package:real_time_chat/widgets/scroll_to_bottom_button.dart';
import 'package:real_time_chat/widgets/send_button.dart';

import '../support/fake_chat_repository.dart';
import '../support/fakes.dart';

const AppUser me = AppUser(uid: 'me', name: 'Me');

/// The app's theme without the downloaded font, which tests cannot fetch.
ThemeData testTheme([Brightness brightness = Brightness.light]) =>
    AppTheme.build(brightness, applyFont: (textTheme) => textTheme);

/// Today at 10:00 plus [minutes]. Keeps the "Today" label stable whatever
/// time of day the tests run at.
DateTime at(int minutes) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    10,
  ).add(Duration(minutes: minutes));
}

/// Message `m<n>`, sent [n] minutes after 10:00 today unless [time] is given.
ChatMessage chatMessage(
  int n, {
  String sender = 'sara',
  String? text,
  DateTime? time,
  bool deleted = false,
  bool edited = false,
  ReplyPreview? replyTo,
  List<String> seenBy = const <String>[],
  bool pending = false,
}) {
  final createdAt = time ?? at(n);
  return ChatMessage(
    id: 'm$n',
    text: deleted ? '' : text ?? 'message $n',
    senderId: sender,
    senderName: sender == 'me'
        ? 'Me'
        : sender[0].toUpperCase() + sender.substring(1),
    createdAt: createdAt,
    editedAt: edited ? createdAt.add(const Duration(seconds: 30)) : null,
    deleted: deleted,
    replyTo: replyTo,
    seenBy: seenBy,
    hasPendingWrites: pending,
  );
}

/// Messages `m<from>`..`m<to>`, alternating between two other people in runs
/// of three, so the list has groups, names and avatars.
List<ChatMessage> conversation(int from, int to) => <ChatMessage>[
  for (var n = from; n <= to; n++)
    chatMessage(n, sender: (n ~/ 3).isEven ? 'sara' : 'omar'),
];

/// Snapshot of a live query holding [messages] (in any order).
MessageBatch batchOf(List<ChatMessage> messages, {bool cache = false}) {
  final sorted = <ChatMessage>[...messages]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return MessageBatch(
    messages: sorted,
    isFromCache: cache,
    oldestCursor: sorted.isEmpty ? null : sorted.last.id,
  );
}

/// Pumps the chat screen on top of an in-memory repository.
class ChatHarness {
  ChatHarness(this.tester);

  final WidgetTester tester;
  final FakeChatRepository repository = FakeChatRepository();
  final FakeDemoSeeder seeder = FakeDemoSeeder();
  late final FakeAuthController auth;

  /// Shows the chat screen for [user] in a window of [size] logical pixels,
  /// inside the [RoundedWindow] the app draws its screen in.
  /// [theme] replaces the default [testTheme] of the given [brightness].
  Future<void> pump({
    AppUser? user = me,
    Brightness brightness = Brightness.light,
    Size size = const Size(390, 780),
    double textScale = 1,
    double pixelRatio = 1,
    ThemeData? theme,
  }) async {
    tester.view.devicePixelRatio = pixelRatio;
    tester.view.physicalSize = size * pixelRatio;
    addTearDown(tester.view.reset);
    auth = FakeAuthController(user);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repository),
          demoSeederProvider.overrideWithValue(seeder),
          authControllerProvider.overrideWith(() => auth),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme ?? testTheme(brightness),
          builder: (context, child) => RoundedWindow(
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
          home: const ChatScreen(),
        ),
      ),
    );
  }

  /// Runs two frames: one for the pending stream events to be delivered and
  /// one for the widgets they changed.
  Future<void> settle() async {
    await tester.pump();
    await tester.pump();
  }

  /// Runs [count] frames, 16 ms apart. A row that was just inserted starts at
  /// zero height, and finders only see it once it takes up space.
  Future<void> frames([int count = 2]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Lets [duration] pass frame by frame, the way animations run. Never use
  /// `pumpAndSettle` here: the screen has animations that repeat forever.
  Future<void> pumpFor(Duration duration) async {
    const frame = Duration(milliseconds: 16);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += frame) {
      await tester.pump(frame);
    }
    await tester.pump();
  }

  /// Delivers [messages] as the first page, confirmed by the server, and
  /// waits for the list to fade in.
  Future<void> load(List<ChatMessage> messages) async {
    repository.latest.add(batchOf(messages));
    await settle();
    repository.since.last.controller.add(batchOf(messages));
    await settle();
    await pumpFor(const Duration(milliseconds: 300));
  }

  /// Pushes a new snapshot of the live query: [messages] is everything the
  /// query matches now.
  Future<void> update(List<ChatMessage> messages) async {
    repository.since.last.controller.add(batchOf(messages));
    await settle();
  }

  ChatState get state => ProviderScope.containerOf(
    tester.element(find.byType(ChatScreen)),
    listen: false,
  ).read(chatControllerProvider);

  List<String> get messageIds => <String>[
    for (final message in state.messages) message.id,
  ];

  ScrollPosition get scroll => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  bool get jumpButtonVisible => tester
      .widget<ScrollToBottomButton>(find.byType(ScrollToBottomButton))
      .visible;

  Finder bubble(String id) => find.byWidgetPredicate(
    (widget) => widget is MessageBubble && widget.message.id == id,
  );

  Finder row(String id) => find.byWidgetPredicate(
    (widget) => widget is MessageRow && widget.message.id == id,
  );

  /// Scrolls towards older messages by [pixels], like a finger dragging the
  /// list down.
  Future<void> scrollUp(double pixels) async {
    await tester.drag(find.byType(ListView), Offset(0, pixels));
    await settle();
  }

  Future<void> typeMessage(String text) async {
    await tester.enterText(find.byType(TextField), text);
    await settle();
  }

  String get composerText =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  Future<void> tapSend() async {
    await tester.tap(find.byType(SendButton));
    await settle();
  }

  /// Opens the long-press menu of message [id].
  Future<void> openMenu(String id) async {
    await tester.longPress(bubble(id));
    await pumpFor(const Duration(milliseconds: 400));
  }

  /// Closes the open menu by tapping next to it. The tap is aimed where the
  /// menu is not, and not at a corner of the window: `RoundedWindow` rounds
  /// those, and the app does not take a tap there.
  Future<void> dismissMenu() async {
    final menu = menuRect;
    await tester.tapAt(
      menu.left >= 20
          ? Offset(menu.left / 2, menu.center.dy)
          : Offset(menu.right + 20, menu.center.dy),
    );
    await pumpFor(const Duration(milliseconds: 400));
  }

  /// The area covered by the open message menu: its entries plus the padding
  /// above and below them.
  Rect get menuRect {
    final entries = find.byWidgetPredicate(
      (widget) => widget is PopupMenuEntry,
    );
    final first = tester.getRect(entries.first);
    final last = tester.getRect(entries.last);
    return Rect.fromLTRB(
      first.left,
      first.top - 8,
      last.right,
      last.bottom + 8,
    );
  }

  /// Taps the entry [label] of the open menu and waits for it to close.
  Future<void> chooseMenuItem(String label) async {
    await tester.tap(find.text(label));
    await pumpFor(const Duration(milliseconds: 400));
  }
}

/// Stands in for the Firestore-backed seeder.
class FakeDemoSeeder implements DemoSeeder {
  int calls = 0;

  /// When set, [seed] fails with this error.
  Object? error;

  @override
  String get roomId => 'lounge';

  @override
  Future<int> seed(AppUser me, {DateTime? now}) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return 40;
  }
}
