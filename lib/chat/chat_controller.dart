import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../models/chat_message.dart';
import '../models/reply_preview.dart';
import '../services/chat_repository.dart';
import '../services/providers.dart';
import 'chat_state.dart';
import 'message_feed.dart';
import 'message_store.dart';

/// State of the room's message list plus every action on messages.
///
/// The heavy lifting lives in two plain-Dart classes: [MessageFeed] (live
/// queries and pagination) and [MessageStore] (merging, ordering, optimistic
/// messages). This notifier only wires them to Riverpod.
final chatControllerProvider =
    NotifierProvider.autoDispose<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  late ChatRepository _repository;
  late MessageStore _store;
  late MessageFeed _feed;
  String _userId = '';

  /// Messages already submitted for a read receipt, so each one is written
  /// at most once per session.
  final Set<String> _seenRequested = <String>{};

  @override
  ChatState build() {
    _repository = ref.watch(chatRepositoryProvider);
    // Only the uid matters here: renaming must not restart the feed.
    _userId =
        ref.watch(authControllerProvider.select((user) => user?.uid)) ?? '';
    _seenRequested.clear();
    _store = MessageStore(currentUserId: _userId);
    final feed = MessageFeed(
      repository: _repository,
      store: _store,
      onChanged: _publish,
    );
    _feed = feed;
    ref.onDispose(feed.dispose);

    if (_userId.isEmpty) {
      return const ChatState(isLoading: false, hasMore: false);
    }
    feed.start();
    return const ChatState();
  }

  /// Sends [text], optionally as a reply. The message is on screen before
  /// this method returns; Firestore confirms it afterwards.
  Future<void> send(String text, {ChatMessage? replyTo}) async {
    final user = ref.read(authControllerProvider);
    final trimmed = text.trim();
    if (user == null || trimmed.isEmpty) return;

    final message = ChatMessage(
      id: _repository.newMessageId(),
      text: trimmed,
      senderId: user.uid,
      senderName: user.name,
      createdAt: DateTime.now(),
      replyTo: replyTo == null
          ? null
          : ReplyPreview.snippet(
              messageId: replyTo.id,
              text: replyTo.text,
              senderName: replyTo.senderName,
            ),
      hasPendingWrites: true,
      hasServerTimestamp: false,
    );
    // Sending always brings the list back to the newest message.
    _store
      ..setPinned(true)
      ..addOutgoing(message);
    _publish();
    await _write(message);
  }

  /// Sends a failed message again.
  Future<void> retry(String messageId) async {
    final message = _store.retry(messageId);
    if (message == null) return;
    _publish();
    await _write(message);
  }

  /// Drops a failed message.
  void discard(String messageId) {
    _store.discard(messageId);
    _publish();
  }

  /// Replaces the text of one of my messages. Firestore applies the change
  /// locally at once; the future completes when the server has stored it.
  Future<void> edit(ChatMessage message, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == message.text) return;
    await _repository.editMessage(message.id, trimmed);
  }

  /// Deletes one of my messages for everyone.
  Future<void> delete(ChatMessage message) =>
      _repository.deleteMessage(message.id);

  /// Loads the next page of older messages.
  Future<void> loadMore() => _feed.loadMore();

  /// Makes sure [messageId] is loaded, fetching older pages if needed.
  Future<bool> ensureLoaded(String messageId) => _feed.ensureLoaded(messageId);

  /// Restarts the feed after an error.
  void reload() {
    _feed.start();
    _publish();
  }

  /// Call after messages were written with timestamps in the past, which is
  /// what the sample data does. Such messages can fall outside the windows
  /// that are being watched; if so, the history is loaded again from scratch.
  void resyncAfterBackfill() {
    if (!_feed.watchesWholeRoom) ref.invalidateSelf();
  }

  /// Reports whether the list is scrolled to the newest message. While it
  /// is not, incoming messages are held back and counted as unread.
  void setPinned(bool pinned) {
    if (_store.isPinned == pinned) return;
    _store.setPinned(pinned);
    _publish();
  }

  /// One-shot: whether the row of [messageId] should animate in.
  bool consumeFresh(String messageId) => _store.consumeFresh(messageId);

  /// Adds a read receipt to every visible message from other people.
  void markSeen() {
    if (_userId.isEmpty) return;
    final ids = <String>[];
    for (final message in _store.visible) {
      if (message.senderId == _userId) continue;
      if (message.deleted || !message.hasServerTimestamp) continue;
      if (message.seenBy.contains(_userId)) continue;
      if (_seenRequested.add(message.id)) ids.add(message.id);
    }
    if (ids.isEmpty) return;
    unawaited(
      _repository.markSeen(ids, _userId).catchError((Object _) {
        // Let the next pass try again.
        _seenRequested.removeAll(ids);
      }),
    );
  }

  Future<void> _write(ChatMessage message) async {
    try {
      await _repository.sendMessage(message);
    } on Object {
      if (!ref.mounted) return;
      _store.markFailed(message.id);
      _publish();
    }
  }

  void _publish() {
    if (!ref.mounted) return;
    state = ChatState(
      messages: _store.visible,
      isLoading: _feed.isLoading,
      isLoadingMore: _feed.isLoadingMore,
      hasMore: _feed.hasMore,
      unreadCount: _store.unreadCount,
      error: _feed.error,
    );
  }
}
