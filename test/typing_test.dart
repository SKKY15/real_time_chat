import 'package:flutter_test/flutter_test.dart';
import 'package:real_time_chat/chat/typing_tracker.dart';
import 'package:real_time_chat/models/typing_user.dart';

void main() {
  group('TypingTracker', () {
    late DateTime now;
    late List<List<String>> emitted;
    late TypingTracker tracker;

    TypingUser user(String id, {int updatedSecondsAgo = 0}) => TypingUser(
      userId: id,
      name: id,
      updatedAt: now.subtract(Duration(seconds: updatedSecondsAgo)),
    );

    setUp(() {
      now = DateTime(2026, 11, 11, 12);
      emitted = <List<String>>[];
      tracker = TypingTracker(
        selfId: 'me',
        ttl: const Duration(milliseconds: 120),
        clock: () => now,
        onChanged: (typing) => emitted.add([for (final u in typing) u.name]),
      );
    });

    tearDown(() => tracker.dispose());

    test('reports who is typing, never the local user', () {
      tracker.apply([user('me'), user('sara')]);
      expect(emitted, [
        ['sara'],
      ]);
    });

    test('sorts names and only notifies on changes', () {
      tracker.apply([user('sara'), user('Omar')]);
      tracker.apply([user('sara'), user('Omar')]);
      expect(emitted, [
        ['Omar', 'sara'],
      ]);
    });

    test('clears as soon as the document is deleted', () {
      tracker.apply([user('sara')]);
      tracker.apply([]);
      expect(emitted, [
        ['sara'],
        <String>[],
      ]);
    });

    test('ignores stale documents left behind by a crashed client', () {
      tracker.apply([user('sara', updatedSecondsAgo: 60)]);
      expect(emitted, isEmpty);
      expect(tracker.active, isEmpty);
    });

    test('a stale document comes back to life on the next ping', () {
      tracker.apply([user('sara', updatedSecondsAgo: 60)]);
      now = now.add(const Duration(seconds: 1));
      tracker.apply([user('sara')]);
      expect(emitted, [
        ['sara'],
      ]);
    });

    test('expires on its own when the pings stop', () async {
      tracker.apply([user('sara')]);
      now = now.add(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(emitted, [
        ['sara'],
        <String>[],
      ]);
    });

    test('expiry does not depend on the other phone\'s clock', () {
      // First snapshot is empty, then a ping stamped five minutes in the
      // past (their clock is off): it still counts from when we saw it.
      tracker.apply([]);
      tracker.apply([user('sara', updatedSecondsAgo: 300)]);
      expect(emitted, [
        ['sara'],
      ]);
    });

    test('every new ping extends the indicator', () async {
      tracker.apply([user('sara')]);
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        now = now.add(const Duration(milliseconds: 60));
        tracker.apply([user('sara')]);
      }
      expect(emitted, [
        ['sara'],
      ]);
    });
  });

  group('typingLabel', () {
    test('names up to two people and counts the rest', () {
      expect(typingLabel([]), '');
      expect(typingLabel(['Sara']), 'Sara is typing…');
      expect(typingLabel(['Sara', 'Omar']), 'Sara and Omar are typing…');
      expect(
        typingLabel(['Sara', 'Omar', 'Lina']),
        'Sara and 2 others are typing…',
      );
    });
  });

  group('TypingSignal', () {
    late DateTime now;
    late List<String> events;
    late TypingSignal signal;

    setUp(() {
      now = DateTime(2026, 11, 11, 12);
      events = <String>[];
      signal = TypingSignal(
        onPing: () => events.add('ping'),
        onStop: () => events.add('stop'),
        idleTimeout: const Duration(milliseconds: 80),
        clock: () => now,
      );
    });

    tearDown(() => signal.dispose());

    test('pings on the first keystroke only', () {
      signal.input('h');
      signal.input('he');
      signal.input('hel');
      expect(events, ['ping']);
    });

    test('refreshes the ping while typing continues', () {
      signal.input('h');
      now = now.add(const Duration(seconds: 1));
      signal.input('he');
      now = now.add(const Duration(seconds: 1));
      signal.input('hel');
      expect(events, ['ping', 'ping']);
    });

    test('stops after the idle timeout', () async {
      signal.input('h');
      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(events, ['ping', 'stop']);
      expect(signal.isActive, isFalse);
    });

    test('keystrokes keep postponing the idle timeout', () async {
      for (var i = 0; i < 4; i++) {
        signal.input('typing $i');
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(events, ['ping']);
    });

    test('stops at once when the field is cleared', () {
      signal.input('h');
      signal.input('   ');
      expect(events, ['ping', 'stop']);
    });

    test('stop is a no-op when nothing was announced', () {
      signal.stop();
      signal.input('');
      expect(events, isEmpty);
    });

    test('typing again after a stop pings immediately', () {
      signal.input('h');
      signal.stop();
      signal.input('h');
      expect(events, ['ping', 'stop', 'ping']);
    });
  });
}
