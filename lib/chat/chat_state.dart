import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';

/// Everything the chat screen needs to render the message list.
@immutable
class ChatState {
  const ChatState({
    this.messages = const <ChatMessage>[],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.unreadCount = 0,
    this.error,
  });

  /// Messages to render, newest first.
  final List<ChatMessage> messages;

  /// The first snapshot has not arrived yet.
  final bool isLoading;

  /// An older page is being fetched.
  final bool isLoadingMore;

  /// Older messages may exist beyond the loaded ones.
  final bool hasMore;

  /// Messages that arrived while the user was reading older history.
  final int unreadCount;

  /// Set when the room could not be loaded (for example missing rules).
  final Object? error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatState &&
          identical(other.messages, messages) &&
          other.isLoading == isLoading &&
          other.isLoadingMore == isLoadingMore &&
          other.hasMore == hasMore &&
          other.unreadCount == unreadCount &&
          other.error == error;

  @override
  int get hashCode => Object.hash(
    identityHashCode(messages),
    isLoading,
    isLoadingMore,
    hasMore,
    unreadCount,
    error,
  );
}
