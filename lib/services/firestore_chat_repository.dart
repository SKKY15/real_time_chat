import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/reply_preview.dart';
import '../models/typing_user.dart';
import 'chat_repository.dart';

/// Cloud Firestore implementation of [ChatRepository].
///
/// ```
/// rooms/{roomId}/messages/{messageId}
///   text, senderId, senderName, createdAt, editedAt, deleted,
///   replyTo {messageId, text, senderName}, seenBy [uid]
/// rooms/{roomId}/typing/{userId}
///   name, updatedAt
/// ```
class FirestoreChatRepository implements ChatRepository {
  FirestoreChatRepository(this._db, {this.roomId = defaultRoomId});

  /// The app has a single group room.
  static const String defaultRoomId = 'lounge';

  /// Firestore allows 500 writes per batch.
  static const int _maxBatchSize = 400;

  final FirebaseFirestore _db;
  final String roomId;

  DocumentReference<Map<String, dynamic>> get _room =>
      _db.collection('rooms').doc(roomId);

  CollectionReference<Map<String, dynamic>> get _messages =>
      _room.collection('messages');

  CollectionReference<Map<String, dynamic>> get _typing =>
      _room.collection('typing');

  Query<Map<String, dynamic>> get _newestFirst =>
      _messages.orderBy('createdAt', descending: true);

  @override
  String newMessageId() => _messages.doc().id;

  @override
  Stream<MessageBatch> watchLatest(int limit) =>
      _watch(_newestFirst.limit(limit));

  @override
  Stream<MessageBatch> watchSince(Object? cursor) => _watch(
    cursor == null ? _newestFirst : _newestFirst.endAtDocument(_cursor(cursor)),
  );

  @override
  Stream<MessageBatch> watchOlder(Object cursor, int limit) =>
      _watch(_newestFirst.startAfterDocument(_cursor(cursor)).limit(limit));

  @override
  Future<void> sendMessage(ChatMessage message) {
    return _messages.doc(message.id).set(<String, dynamic>{
      'text': message.text,
      'senderId': message.senderId,
      'senderName': message.senderName,
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
      'deleted': false,
      'replyTo': message.replyTo?.toMap(),
      'seenBy': <String>[],
    });
  }

  @override
  Future<void> editMessage(String messageId, String text) {
    return _messages.doc(messageId).update(<String, dynamic>{
      'text': text,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteMessage(String messageId) {
    // Soft delete: the content is wiped, the document stays so every client
    // can show "This message was deleted".
    return _messages.doc(messageId).update(<String, dynamic>{
      'deleted': true,
      'text': '',
      'replyTo': null,
    });
  }

  @override
  Future<void> markSeen(Iterable<String> messageIds, String userId) async {
    final ids = messageIds.toList(growable: false);
    for (var start = 0; start < ids.length; start += _maxBatchSize) {
      final batch = _db.batch();
      for (final id in ids.skip(start).take(_maxBatchSize)) {
        batch.update(_messages.doc(id), <String, dynamic>{
          'seenBy': FieldValue.arrayUnion(<String>[userId]),
        });
      }
      await batch.commit();
    }
  }

  @override
  Stream<List<TypingUser>> watchTyping() {
    return _typing.snapshots().map((snapshot) {
      return <TypingUser>[
        for (final doc in snapshot.docs) _typingUserFromDoc(doc),
      ];
    });
  }

  @override
  Future<void> setTyping(AppUser user) {
    return _typing.doc(user.uid).set(<String, dynamic>{
      'name': user.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> clearTyping(String userId) => _typing.doc(userId).delete();

  /// Maps a live query to [MessageBatch]es.
  ///
  /// Metadata changes are included so a message flips from "sending" to
  /// "sent" the moment the server acknowledges the write.
  Stream<MessageBatch> _watch(Query<Map<String, dynamic>> query) {
    var previousIds = const <String>{};
    return query.snapshots(includeMetadataChanges: true).map((snapshot) {
      final docs = snapshot.docs;
      final messages = <ChatMessage>[
        for (final doc in docs) _messageFromDoc(doc),
      ];
      final ids = <String>{for (final doc in docs) doc.id};
      final removedIds = previousIds.difference(ids).toList(growable: false);
      previousIds = ids;
      return MessageBatch(
        messages: messages,
        removedIds: removedIds,
        isFromCache: snapshot.metadata.isFromCache,
        oldestCursor: docs.isEmpty ? null : docs.last,
      );
    });
  }

  static DocumentSnapshot<Map<String, dynamic>> _cursor(Object cursor) =>
      cursor as DocumentSnapshot<Map<String, dynamic>>;

  static ChatMessage _messageFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final Object? text = data['text'];
    final Object? senderId = data['senderId'];
    final Object? senderName = data['senderName'];
    final Object? createdAt = data['createdAt'];
    final Object? editedAt = data['editedAt'];
    final Object? seenBy = data['seenBy'];

    return ChatMessage(
      id: doc.id,
      text: text is String ? text : '',
      senderId: senderId is String ? senderId : '',
      senderName: senderName is String ? senderName : '',
      // A server timestamp reads as null until the write is acknowledged.
      // The message store swaps this fallback for a stable local time.
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      hasServerTimestamp: createdAt is Timestamp,
      editedAt: editedAt is Timestamp ? editedAt.toDate() : null,
      deleted: data['deleted'] == true,
      replyTo: ReplyPreview.fromMap(data['replyTo']),
      seenBy: seenBy is List
          ? List<String>.unmodifiable(seenBy.whereType<String>())
          : const <String>[],
      hasPendingWrites: doc.metadata.hasPendingWrites,
    );
  }

  static TypingUser _typingUserFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final Object? name = data['name'];
    final Object? updatedAt = data['updatedAt'];
    return TypingUser(
      userId: doc.id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : 'Someone',
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }
}
