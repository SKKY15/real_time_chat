import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';

/// What the input bar is currently doing besides writing a new message.
@immutable
class ComposerState {
  const ComposerState({this.replyTo, this.editing});

  /// Message being replied to.
  final ChatMessage? replyTo;

  /// Message being edited.
  final ChatMessage? editing;

  bool get isEditing => editing != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComposerState &&
          other.replyTo?.id == replyTo?.id &&
          other.editing?.id == editing?.id;

  @override
  int get hashCode => Object.hash(replyTo?.id, editing?.id);
}

/// Reply / edit target of the input bar. Only the input bar listens to it,
/// so starting a reply never rebuilds the message list.
final composerProvider =
    NotifierProvider.autoDispose<ComposerController, ComposerState>(
      ComposerController.new,
    );

class ComposerController extends Notifier<ComposerState> {
  @override
  ComposerState build() => const ComposerState();

  void reply(ChatMessage message) => state = ComposerState(replyTo: message);

  void edit(ChatMessage message) => state = ComposerState(editing: message);

  void clear() => state = const ComposerState();
}
