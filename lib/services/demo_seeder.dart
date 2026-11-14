import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'demo_conversation.dart';
import 'firestore_chat_repository.dart';

/// Inserts the scripted 40-message conversation so the room looks alive:
/// two days of history, several senders, replies, an edited and a deleted
/// message.
///
/// The messages are backdated and partly written in the name of fictional
/// participants, which regular messages are not allowed to be. The security
/// rules permit it only for documents flagged `demo: true`; delete that rule
/// block (and this action) before shipping.
class DemoSeeder {
  DemoSeeder(this._db, {this.roomId = FirestoreChatRepository.defaultRoomId});

  final FirebaseFirestore _db;
  final String roomId;

  /// Writes the conversation in one batch and returns the number of messages.
  Future<int> seed(AppUser me, {DateTime? now}) async {
    final collection = _db
        .collection('rooms')
        .doc(roomId)
        .collection('messages');
    final messages = demoMessages(
      me: me,
      now: now ?? DateTime.now(),
      newId: () => collection.doc().id,
    );

    final batch = _db.batch();
    for (final message in messages) {
      final editedAt = message.editedAt;
      batch.set(collection.doc(message.id), <String, dynamic>{
        'text': message.text,
        'senderId': message.senderId,
        'senderName': message.senderName,
        'createdAt': Timestamp.fromDate(message.createdAt),
        'editedAt': editedAt == null ? null : Timestamp.fromDate(editedAt),
        'deleted': message.deleted,
        'replyTo': message.replyTo?.toMap(),
        'seenBy': message.seenBy,
        'demo': true,
      });
    }
    await batch.commit();
    return messages.length;
  }
}
