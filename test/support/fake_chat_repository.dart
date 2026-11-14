import 'dart:async';

import 'package:real_time_chat/models/app_user.dart';
import 'package:real_time_chat/models/chat_message.dart';
import 'package:real_time_chat/models/typing_user.dart';
import 'package:real_time_chat/services/chat_repository.dart';

/// Scriptable in-memory [ChatRepository].
///
/// Every `watch*` call hands out a controller the test can push snapshots
/// into, which makes the ordering of cache and server results explicit.
class FakeChatRepository implements ChatRepository {
  final List<StreamController<MessageBatch>> latestQueries =
      <StreamController<MessageBatch>>[];
  final List<SinceQuery> since = <SinceQuery>[];
  final List<OlderQuery> older = <OlderQuery>[];
  final List<ChatMessage> sent = <ChatMessage>[];
  final Map<String, String> edits = <String, String>{};
  final List<String> deleted = <String>[];
  final List<List<String>> seen = <List<String>>[];

  /// When set, the next [sendMessage] fails with this error.
  Object? sendError;

  /// When `true`, [sendMessage] stays pending until [completeSends] or
  /// [failSends] is called, like a write waiting for the network.
  bool holdSends = false;
  final List<Completer<void>> _heldSends = <Completer<void>>[];

  /// Everyone who is "typing"; push a list to simulate a snapshot.
  final StreamController<List<TypingUser>> typing =
      StreamController<List<TypingUser>>.broadcast();
  final List<String> typingEvents = <String>[];

  int _nextId = 0;

  /// The most recent "latest messages" query.
  StreamController<MessageBatch> get latest => latestQueries.last;

  void completeSends() {
    for (final completer in _heldSends) {
      completer.complete();
    }
    _heldSends.clear();
  }

  void failSends(Object error) {
    for (final completer in _heldSends) {
      completer.completeError(error);
    }
    _heldSends.clear();
  }

  @override
  String newMessageId() => 'local-${_nextId++}';

  @override
  Stream<MessageBatch> watchLatest(int limit) {
    final controller = StreamController<MessageBatch>();
    latestQueries.add(controller);
    return controller.stream;
  }

  @override
  Stream<MessageBatch> watchSince(Object? cursor) {
    final query = SinceQuery(cursor);
    since.add(query);
    return query.controller.stream;
  }

  @override
  Stream<MessageBatch> watchOlder(Object cursor, int limit) {
    final query = OlderQuery(cursor, limit);
    older.add(query);
    return query.controller.stream;
  }

  @override
  Future<void> sendMessage(ChatMessage message) {
    sent.add(message);
    final error = sendError;
    if (error != null) {
      sendError = null;
      return Future<void>.error(error);
    }
    if (holdSends) {
      final completer = Completer<void>();
      _heldSends.add(completer);
      return completer.future;
    }
    return Future<void>.value();
  }

  @override
  Future<void> editMessage(String messageId, String text) async {
    edits[messageId] = text;
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    deleted.add(messageId);
  }

  @override
  Future<void> markSeen(Iterable<String> messageIds, String userId) async {
    seen.add(messageIds.toList());
  }

  @override
  Stream<List<TypingUser>> watchTyping() => typing.stream;

  @override
  Future<void> setTyping(AppUser user) async {
    typingEvents.add('set ${user.name}');
  }

  @override
  Future<void> clearTyping(String userId) async {
    typingEvents.add('clear $userId');
  }
}

class SinceQuery {
  SinceQuery(this.cursor);

  final Object? cursor;
  final StreamController<MessageBatch> controller =
      StreamController<MessageBatch>();
}

class OlderQuery {
  OlderQuery(this.cursor, this.limit);

  final Object cursor;
  final int limit;
  final StreamController<MessageBatch> controller =
      StreamController<MessageBatch>();
}

/// Base time used by the test messages.
final DateTime testEpoch = DateTime(2026, 11, 11, 12);

/// Message number [n]: a higher number means a newer message.
ChatMessage msg(
  int n, {
  String sender = 'omar',
  String? text,
  bool pending = false,
  bool deleted = false,
  DateTime? editedAt,
  List<String> seenBy = const <String>[],
}) {
  return ChatMessage(
    id: 'm$n',
    text: text ?? 'message $n',
    senderId: sender,
    senderName: sender,
    createdAt: testEpoch.add(Duration(minutes: n)),
    editedAt: editedAt,
    deleted: deleted,
    seenBy: seenBy,
    hasPendingWrites: pending,
  );
}

/// Snapshot containing messages [from]..[to] (inclusive), newest first, with
/// the oldest message id as cursor.
MessageBatch batch(
  int from,
  int to, {
  bool cache = false,
  List<String> removed = const <String>[],
}) {
  final messages = <ChatMessage>[for (var n = to; n >= from; n--) msg(n)];
  return MessageBatch(
    messages: messages,
    removedIds: removed,
    isFromCache: cache,
    oldestCursor: messages.isEmpty ? null : messages.last.id,
  );
}

/// Lets pending stream events and microtasks run.
Future<void> pump() => Future<void>.delayed(Duration.zero);
