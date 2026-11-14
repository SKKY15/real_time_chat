import 'reply_preview.dart';

/// Delivery state of an outgoing message, shown as the small check icons.
enum MessageStatus {
  /// Written locally, not yet acknowledged by the server.
  sending,

  /// Stored on the server.
  sent,

  /// At least one other participant has seen it.
  seen,

  /// The server rejected the write.
  failed,
}

/// One chat message (`rooms/{roomId}/messages/{messageId}`).
///
/// Plain immutable Dart: the Firestore mapping lives in the chat repository so
/// the model stays trivially testable.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
    this.editedAt,
    this.deleted = false,
    this.replyTo,
    this.seenBy = const <String>[],
    this.hasPendingWrites = false,
    this.hasServerTimestamp = true,
    this.sendFailed = false,
  });

  final String id;
  final String text;
  final String senderId;
  final String senderName;

  /// Server time once the message is stored. While the message is still being
  /// sent this is the local clock ([hasServerTimestamp] is `false`).
  final DateTime createdAt;

  /// Set when the author edited the message.
  final DateTime? editedAt;

  /// Soft delete flag: the bubble is replaced by "This message was deleted".
  final bool deleted;

  /// Quoted message, when this message is a reply.
  final ReplyPreview? replyTo;

  /// Ids of the users who have seen the message.
  final List<String> seenBy;

  /// A local write (create, edit, delete) has not reached the server yet.
  final bool hasPendingWrites;

  /// `false` until the server has assigned [createdAt].
  final bool hasServerTimestamp;

  /// The server rejected the message; it only exists on this device.
  final bool sendFailed;

  bool get isEdited => editedAt != null && !deleted;

  bool isFrom(String userId) => senderId == userId;

  /// Status as seen by the author.
  MessageStatus get status {
    if (sendFailed) return MessageStatus.failed;
    if (hasPendingWrites || !hasServerTimestamp) return MessageStatus.sending;
    for (final id in seenBy) {
      if (id != senderId) return MessageStatus.seen;
    }
    return MessageStatus.sent;
  }

  ChatMessage copyWith({
    String? text,
    String? senderName,
    DateTime? createdAt,
    DateTime? editedAt,
    bool? deleted,
    List<String>? seenBy,
    bool? hasPendingWrites,
    bool? hasServerTimestamp,
    bool? sendFailed,
  }) {
    return ChatMessage(
      id: id,
      text: text ?? this.text,
      senderId: senderId,
      senderName: senderName ?? this.senderName,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      deleted: deleted ?? this.deleted,
      replyTo: replyTo,
      seenBy: seenBy ?? this.seenBy,
      hasPendingWrites: hasPendingWrites ?? this.hasPendingWrites,
      hasServerTimestamp: hasServerTimestamp ?? this.hasServerTimestamp,
      sendFailed: sendFailed ?? this.sendFailed,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage &&
        other.id == id &&
        other.text == text &&
        other.senderId == senderId &&
        other.senderName == senderName &&
        other.createdAt == createdAt &&
        other.editedAt == editedAt &&
        other.deleted == deleted &&
        other.replyTo == replyTo &&
        other.hasPendingWrites == hasPendingWrites &&
        other.hasServerTimestamp == hasServerTimestamp &&
        other.sendFailed == sendFailed &&
        _sameIds(other.seenBy, seenBy);
  }

  @override
  int get hashCode => Object.hash(
    id,
    text,
    senderId,
    createdAt,
    editedAt,
    deleted,
    hasPendingWrites,
    hasServerTimestamp,
    sendFailed,
    seenBy.length,
  );

  @override
  String toString() => 'ChatMessage($id, $senderName: $text)';

  static bool _sameIds(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
