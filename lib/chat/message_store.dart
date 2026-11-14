import '../models/chat_message.dart';

/// In-memory source of truth for the message list.
///
/// Merges three inputs into one sorted list (newest first):
///
///  * messages confirmed by Firestore ([upsert] / [remove]),
///  * the outbox: messages shown optimistically while they are being sent,
///  * the "held" set: messages that arrived while the user was reading older
///    history. They stay hidden (and are counted as unread) until the list is
///    pinned to the bottom again, so the scroll position never jumps.
///
/// The class is plain Dart with no Flutter or Firebase imports.
class MessageStore {
  MessageStore({required this.currentUserId, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// How long an id stays eligible for the entrance animation.
  static const Duration freshWindow = Duration(seconds: 2);

  /// More messages than this arriving at once appear without animation.
  static const int maxAnimatedBurst = 6;

  final String currentUserId;
  final DateTime Function() _clock;

  final Map<String, ChatMessage> _remote = <String, ChatMessage>{};
  final Map<String, ChatMessage> _outbox = <String, ChatMessage>{};
  final Map<String, DateTime> _localTimes = <String, DateTime>{};
  final Map<String, DateTime> _pendingEdits = <String, DateTime>{};
  final Map<String, DateTime> _fresh = <String, DateTime>{};
  final Set<String> _held = <String>{};

  List<ChatMessage> _visible = const <ChatMessage>[];
  bool _dirty = false;
  bool _pinned = true;

  /// Messages to render, newest first. The same list instance is returned
  /// until something visible changes, so identity checks are enough to skip
  /// rebuilds.
  List<ChatMessage> get visible {
    if (_dirty) {
      _dirty = false;
      final next = _buildVisible();
      if (!_sameMessages(next, _visible)) _visible = List.unmodifiable(next);
    }
    return _visible;
  }

  /// Messages from other people that arrived while the list was scrolled up.
  int get unreadCount => _held.length;

  /// Whether the list is currently pinned to the newest message.
  bool get isPinned => _pinned;

  bool get hasRemoteMessages => _remote.isNotEmpty;

  bool hasRemote(String id) => _remote.containsKey(id);

  bool contains(String id) =>
      _remote.containsKey(id) || _outbox.containsKey(id);

  ChatMessage? operator [](String id) => _remote[id] ?? _outbox[id];

  /// Adds or updates messages coming from Firestore.
  ///
  /// With [announce] set, messages that were unknown so far are treated as
  /// "just arrived": they animate in when the list is pinned to the bottom
  /// and are held back as unread when it is not.
  void upsert(Iterable<ChatMessage> messages, {bool announce = false}) {
    final arrived = <ChatMessage>[];
    for (final incoming in messages) {
      final id = incoming.id;
      final isNew = !_remote.containsKey(id) && !_outbox.containsKey(id);
      final message = _normalize(incoming);
      if (_remote[id] == message) continue;
      _remote[id] = message;
      _dirty = true;

      if (message.hasServerTimestamp) {
        _outbox.remove(id);
        _localTimes.remove(id);
      }
      if (isNew && announce) arrived.add(message);
    }

    // A whole burst at once (reconnecting, sample data) is a bulk update, not
    // a conversation: it shows up without the entrance animation.
    final animate = arrived.length <= maxAnimatedBurst;
    for (final message in arrived) {
      if (_pinned || message.senderId == currentUserId) {
        if (animate) _markFresh(message.id);
      } else {
        _held.add(message.id);
      }
    }
  }

  /// Drops messages that left a live query (hard deletes, rejected writes).
  void remove(Iterable<String> ids) {
    for (final id in ids) {
      if (_remote.remove(id) != null) _dirty = true;
      _held.remove(id);
      _pendingEdits.remove(id);
      if (!_outbox.containsKey(id)) _localTimes.remove(id);
    }
  }

  /// Replaces everything received from Firestore with [messages]. Used when
  /// the cached history turns out not to be contiguous with the server's.
  void resetRemote(Iterable<ChatMessage> messages) {
    _remote.clear();
    _held.clear();
    _pendingEdits.clear();
    _localTimes.removeWhere((id, _) => !_outbox.containsKey(id));
    _dirty = true;
    upsert(messages);
  }

  /// Shows [message] immediately while it is being written (optimistic UI).
  void addOutgoing(ChatMessage message) {
    _outbox[message.id] = message.copyWith(
      hasPendingWrites: true,
      hasServerTimestamp: false,
      sendFailed: false,
    );
    _localTimes[message.id] = message.createdAt;
    _markFresh(message.id);
    _dirty = true;
  }

  /// Flags an outgoing message as rejected by the server.
  void markFailed(String id) {
    final message = _outbox[id];
    if (message == null) return;
    _outbox[id] = message.copyWith(sendFailed: true);
    _dirty = true;
  }

  /// Puts a failed message back into the "sending" state.
  ChatMessage? retry(String id) {
    final message = _outbox[id];
    if (message == null) return null;
    final retried = message.copyWith(sendFailed: false);
    _outbox[id] = retried;
    _dirty = true;
    return retried;
  }

  /// Forgets a failed message.
  void discard(String id) {
    if (_outbox.remove(id) != null) _dirty = true;
    _localTimes.remove(id);
  }

  /// Tells the store whether the list is pinned to the newest message.
  /// Pinning releases every held message.
  void setPinned(bool pinned) {
    if (_pinned == pinned) return;
    _pinned = pinned;
    if (pinned && _held.isNotEmpty) {
      if (_held.length <= maxAnimatedBurst) _held.forEach(_markFresh);
      _held.clear();
      _dirty = true;
    }
  }

  /// Returns `true` exactly once for a message that should play its entrance
  /// animation.
  bool consumeFresh(String id) {
    final since = _fresh.remove(id);
    return since != null && _clock().difference(since) <= freshWindow;
  }

  ChatMessage _normalize(ChatMessage message) {
    var result = message;
    if (!result.hasServerTimestamp) {
      // Keep one stable local time while the server timestamp is pending so
      // the message does not move on every snapshot.
      final local = _localTimes[result.id] ??= result.createdAt;
      if (result.createdAt != local) result = result.copyWith(createdAt: local);
    }
    if (result.senderId == currentUserId && result.hasServerTimestamp) {
      // A pending write on one of my stored messages that is not a delete can
      // only be an edit. Its server `editedAt` reads as null until the write
      // is acknowledged, so fill it in to show the "edited" label right away.
      if (result.hasPendingWrites && !result.deleted) {
        if (result.editedAt == null) {
          final editedAt = _pendingEdits[result.id] ??= _clock();
          result = result.copyWith(editedAt: editedAt);
        }
      } else {
        _pendingEdits.remove(result.id);
      }
    }
    return result;
  }

  void _markFresh(String id) {
    final now = _clock();
    _fresh.removeWhere((_, since) => now.difference(since) > freshWindow);
    _fresh[id] = now;
  }

  List<ChatMessage> _buildVisible() {
    final result = <ChatMessage>[
      for (final message in _remote.values)
        if (!_held.contains(message.id)) message,
      // Optimistic messages Firestore has not echoed back (yet, or any more
      // after a rejected write).
      for (final message in _outbox.values)
        if (!_remote.containsKey(message.id)) message,
    ];
    result.sort(_newestFirst);
    return result;
  }

  /// Messages still waiting for their server timestamp are always the newest
  /// ones, whatever the device clock says.
  static int _newestFirst(ChatMessage a, ChatMessage b) {
    if (a.hasServerTimestamp != b.hasServerTimestamp) {
      return a.hasServerTimestamp ? 1 : -1;
    }
    final byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  static bool _sameMessages(List<ChatMessage> a, List<ChatMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
