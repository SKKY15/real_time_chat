import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/typing_user.dart';

/// One snapshot of a live message query.
class MessageBatch {
  const MessageBatch({
    required this.messages,
    this.removedIds = const <String>[],
    this.isFromCache = false,
    this.oldestCursor,
  });

  /// Every message currently matched by the query, newest first.
  final List<ChatMessage> messages;

  /// Ids that were part of the previous snapshot of the same query but are
  /// gone now.
  final List<String> removedIds;

  /// `true` while the result has not been confirmed by the server.
  final bool isFromCache;

  /// Opaque pagination cursor pointing at the oldest message of the snapshot,
  /// or `null` when it is empty.
  final Object? oldestCursor;
}

/// Storage boundary of the chat feature.
///
/// The UI and the controllers only talk to this interface;
/// `FirestoreChatRepository` is the production implementation.
abstract interface class ChatRepository {
  /// Reserves an id so a message can be shown before it is written.
  String newMessageId();

  /// Live window with the newest [limit] messages.
  Stream<MessageBatch> watchLatest(int limit);

  /// Live query with every message from the newest one down to [cursor]
  /// (inclusive). With a `null` cursor it covers the whole room.
  Stream<MessageBatch> watchSince(Object? cursor);

  /// Live window with the [limit] messages that are older than [cursor].
  Stream<MessageBatch> watchOlder(Object cursor, int limit);

  /// Writes [message]. Completes once the server has stored it.
  Future<void> sendMessage(ChatMessage message);

  Future<void> editMessage(String messageId, String text);

  /// Soft-deletes the message for everyone.
  Future<void> deleteMessage(String messageId);

  /// Adds [userId] to `seenBy` of every message in [messageIds].
  Future<void> markSeen(Iterable<String> messageIds, String userId);

  /// Everyone with a typing document in the room.
  Stream<List<TypingUser>> watchTyping();

  /// Creates or refreshes the typing document of [user].
  Future<void> setTyping(AppUser user);

  Future<void> clearTyping(String userId);
}
