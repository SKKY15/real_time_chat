import 'dart:async';

import '../models/typing_user.dart';

/// Reader side of the typing indicator.
///
/// Turns the raw typing documents into "who is typing right now". A writer
/// deletes its document after 3 s without keystrokes, but a crashed or
/// offline client cannot, so every entry also expires locally after [ttl].
///
/// Expiry is measured from the moment *this* device observed the last ping,
/// which keeps it independent of clock differences between phones.
class TypingTracker {
  TypingTracker({
    required this.selfId,
    required this.onChanged,
    this.ttl = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String selfId;
  final Duration ttl;
  final void Function(List<TypingUser> typing) onChanged;
  final DateTime Function() _clock;

  final Map<String, TypingUser> _users = <String, TypingUser>{};
  final Map<String, DateTime> _observedAt = <String, DateTime>{};
  List<TypingUser> _active = const <TypingUser>[];
  Timer? _expiry;
  bool _first = true;

  /// People currently typing, excluding the local user.
  List<TypingUser> get active => _active;

  /// Feeds the latest snapshot of the typing collection.
  void apply(List<TypingUser> documents) {
    final now = _clock();
    final seen = <String>{};
    for (final user in documents) {
      if (user.userId == selfId) continue;
      seen.add(user.userId);
      final previous = _users[user.userId];
      if (previous == null || previous.updatedAt != user.updatedAt) {
        _observedAt[user.userId] = _first
            ? _initialObservation(user, now)
            : now;
      }
      _users[user.userId] = user;
    }
    _users.removeWhere((id, _) => !seen.contains(id));
    _observedAt.removeWhere((id, _) => !seen.contains(id));
    _first = false;
    _refresh();
  }

  void dispose() {
    _expiry?.cancel();
    _expiry = null;
  }

  /// Documents that already exist when we start listening may be leftovers,
  /// so their age is taken from the server timestamp (never from the future).
  DateTime _initialObservation(TypingUser user, DateTime now) {
    final updatedAt = user.updatedAt;
    if (updatedAt == null || updatedAt.isAfter(now)) return now;
    return updatedAt;
  }

  void _refresh() {
    _expiry?.cancel();
    _expiry = null;
    final now = _clock();
    Duration? nextExpiry;
    final active = <TypingUser>[];
    for (final user in _users.values) {
      final remaining = ttl - now.difference(_observedAt[user.userId]!);
      if (remaining <= Duration.zero) continue;
      active.add(user);
      if (nextExpiry == null || remaining < nextExpiry) nextExpiry = remaining;
    }
    active.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (nextExpiry != null) {
      _expiry = Timer(nextExpiry + const Duration(milliseconds: 20), _refresh);
    }
    if (!_sameUsers(active, _active)) {
      _active = List.unmodifiable(active);
      onChanged(_active);
    }
  }

  static bool _sameUsers(List<TypingUser> a, List<TypingUser> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].userId != b[i].userId || a[i].name != b[i].name) return false;
    }
    return true;
  }
}

/// Writer side of the typing indicator: a throttle plus a debounce.
///
/// While the user keeps typing, [onPing] fires at most once per
/// [refreshInterval]. After [idleTimeout] without input (or as soon as the
/// field is emptied or the message sent) [onStop] fires once.
class TypingSignal {
  TypingSignal({
    required this.onPing,
    required this.onStop,
    this.idleTimeout = const Duration(seconds: 3),
    this.refreshInterval = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final void Function() onPing;
  final void Function() onStop;
  final Duration idleTimeout;
  final Duration refreshInterval;
  final DateTime Function() _clock;

  Timer? _idle;
  DateTime? _lastPing;
  bool _active = false;

  bool get isActive => _active;

  /// Call on every change of the input text.
  void input(String text) {
    if (text.trim().isEmpty) {
      stop();
      return;
    }
    final now = _clock();
    final lastPing = _lastPing;
    if (!_active ||
        lastPing == null ||
        now.difference(lastPing) >= refreshInterval) {
      _active = true;
      _lastPing = now;
      onPing();
    }
    _idle?.cancel();
    _idle = Timer(idleTimeout, stop);
  }

  /// Stops immediately (message sent, field cleared, app paused).
  void stop() {
    _idle?.cancel();
    _idle = null;
    if (!_active) return;
    _active = false;
    _lastPing = null;
    onStop();
  }

  void dispose() => stop();
}

/// Text of the typing indicator for the given names:
/// "Sara is typing…", "Sara and Omar are typing…", "Sara and 2 others are
/// typing…". Empty when nobody is typing.
String typingLabel(List<String> names) {
  return switch (names.length) {
    0 => '',
    1 => '${names[0]} is typing…',
    2 => '${names[0]} and ${names[1]} are typing…',
    final count => '${names[0]} and ${count - 1} others are typing…',
  };
}
