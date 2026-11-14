import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:real_time_chat/app.dart';
import 'package:real_time_chat/auth/username_screen.dart';
import 'package:real_time_chat/chat/chat_screen.dart';
import 'package:real_time_chat/models/app_user.dart';
import 'package:real_time_chat/services/providers.dart';

import '../support/fake_chat_repository.dart';
import '../support/fakes.dart';
import 'chat_harness.dart';

const Duration _transition = Duration(milliseconds: 500);

/// Pumps the whole app with a fake sign-in service and an empty room.
Future<FakeAuthService> _pumpApp(WidgetTester tester, {AppUser? user}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 780);
  addTearDown(tester.view.reset);
  final auth = FakeAuthService(user);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        demoSeederProvider.overrideWithValue(FakeDemoSeeder()),
      ],
      child: ChatApp(theme: testTheme(), darkTheme: testTheme(Brightness.dark)),
    ),
  );
  await tester.pump();
  return auth;
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 16);
  for (var elapsed = Duration.zero; elapsed < duration; elapsed += frame) {
    await tester.pump(frame);
  }
  await tester.pump();
}

void main() {
  group('joining', () {
    testWidgets('asks for a name, then opens the chat', (tester) async {
      await _pumpApp(tester);
      expect(find.text('Join the conversation'), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);

      FilledButton joinButton() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(joinButton().onPressed, isNull);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(joinButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), ' Nadia ');
      await tester.pump();
      expect(joinButton().onPressed, isNotNull);
      await tester.tap(find.text('Join chat'));
      await _pumpFor(tester, _transition);

      expect(find.byType(UsernameScreen), findsNothing);
      expect(find.text('Lounge'), findsOneWidget);
      expect(find.text('You are Nadia'), findsOneWidget);
    });

    testWidgets('a returning user goes straight to the chat', (tester) async {
      await _pumpApp(
        tester,
        user: const AppUser(uid: 'u1', name: 'Nadia'),
      );
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byType(UsernameScreen), findsNothing);
      expect(find.text('You are Nadia'), findsOneWidget);
    });

    testWidgets('a signed-in user without a name is asked for one', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        user: const AppUser(uid: 'u1', name: ''),
      );
      expect(find.byType(UsernameScreen), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
    });

    testWidgets('explains why joining failed and lets the user retry', (
      tester,
    ) async {
      final auth = await _pumpApp(tester);
      auth.joinError = StateError('offline');
      await tester.enterText(find.byType(TextField), 'Nadia');
      await tester.pump();
      await tester.tap(find.text('Join chat'));
      await _pumpFor(tester, _transition);

      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(ChatScreen), findsNothing);

      await tester.tap(find.text('Join chat'));
      await _pumpFor(tester, _transition);
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('signing out returns to the name prompt', (tester) async {
      final auth = await _pumpApp(
        tester,
        user: const AppUser(uid: 'u1', name: 'Nadia'),
      );
      await tester.tap(find.byTooltip('More'));
      await _pumpFor(tester, _transition);
      await tester.tap(find.text('Sign out'));
      await _pumpFor(tester, _transition);

      expect(auth.currentUser, isNull);
      expect(find.byType(UsernameScreen), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
    });
  });

  group('theme', () {
    testWidgets('the app bar button switches between light and dark', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        user: const AppUser(uid: 'u1', name: 'Nadia'),
      );
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(ChatScreen))).brightness;
      expect(brightness(), Brightness.light);

      await tester.tap(find.byTooltip('Dark mode'));
      await _pumpFor(tester, _transition);
      expect(brightness(), Brightness.dark);
      expect(find.byTooltip('Dark mode'), findsNothing);

      await tester.tap(find.byTooltip('Light mode'));
      await _pumpFor(tester, _transition);
      expect(brightness(), Brightness.light);
    });

    testWidgets('follows the system until the button is used', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpApp(
        tester,
        user: const AppUser(uid: 'u1', name: 'Nadia'),
      );
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(ChatScreen))).brightness;
      expect(brightness(), Brightness.dark);

      await tester.tap(find.byTooltip('Light mode'));
      await _pumpFor(tester, _transition);
      expect(brightness(), Brightness.light);
    });
  });
}
