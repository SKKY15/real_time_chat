import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:real_time_chat/chat/chat_screen.dart';
import 'package:real_time_chat/widgets/rounded_window.dart';

import 'chat_harness.dart';

/// The corners the app bar is drawn with, as one radius for all four.
BorderRadius appBarCorners(WidgetTester tester) {
  final appBar = tester.widget<AppBar>(find.byType(AppBar)).shape!;
  final radius =
      (appBar as RoundedRectangleBorder).borderRadius as BorderRadius;
  return BorderRadius.all(radius.topLeft);
}

void main() {
  group('the rounded window', () {
    testWidgets('rounds the corners of a phone screen', (tester) async {
      final h = ChatHarness(tester);
      await h.pump();

      expect(
        RoundedWindow.cornersOf(tester.element(find.byType(ChatScreen))),
        isTrue,
      );
      // The app still gets every pixel of the window.
      expect(tester.getSize(find.byType(ChatScreen)), const Size(390, 780));
      expect(tester.getTopLeft(find.byType(ChatScreen)), Offset.zero);
      expect(appBarCorners(tester), RoundedWindow.screenCorners);
    });

    testWidgets('boxes the app in a wide window', (tester) async {
      final h = ChatHarness(tester);
      await h.pump(size: const Size(760, 900));

      expect(
        RoundedWindow.cornersOf(tester.element(find.byType(ChatScreen))),
        isTrue,
      );
      // The screen keeps the width of a phone, centered, and fills the height.
      expect(
        tester.getSize(find.byType(ChatScreen)),
        const Size(RoundedWindow.screenWidth, 900),
      );
      expect(
        tester.getTopLeft(find.byType(ChatScreen)),
        const Offset((760 - RoundedWindow.screenWidth) / 2, 0),
      );
      expect(appBarCorners(tester), RoundedWindow.screenCorners);
    });

    testWidgets('leaves a window too narrow for corners alone', (tester) async {
      final h = ChatHarness(tester);
      await h.pump(size: const Size(300, 600));

      expect(
        RoundedWindow.cornersOf(tester.element(find.byType(ChatScreen))),
        isFalse,
      );
      expect(tester.getSize(find.byType(ChatScreen)), const Size(300, 600));
      expect(appBarCorners(tester), BorderRadius.zero);
    });
  });
}
