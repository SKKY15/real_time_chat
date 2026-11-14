import '../models/chat_message.dart';
import '../utils/date_labels.dart';

/// How one message is placed relative to its neighbours.
class MessageLayout {
  const MessageLayout({
    required this.showDateSeparator,
    required this.isFirstInGroup,
    required this.isLastInGroup,
  });

  /// Computes the layout of `messages[index]`.
  ///
  /// [messages] is ordered newest first, so `index + 1` is the message drawn
  /// directly above and `index - 1` the one directly below.
  factory MessageLayout.at(List<ChatMessage> messages, int index) {
    final message = messages[index];
    final above = index + 1 < messages.length ? messages[index + 1] : null;
    final below = index > 0 ? messages[index - 1] : null;

    final startsDay =
        above == null ||
        !DateLabels.isSameDay(above.createdAt, message.createdAt);
    final endsDay =
        below != null &&
        !DateLabels.isSameDay(below.createdAt, message.createdAt);

    return MessageLayout(
      showDateSeparator: startsDay,
      isFirstInGroup: startsDay || !_sameGroup(above, message),
      isLastInGroup: below == null || endsDay || !_sameGroup(message, below),
    );
  }

  /// Messages further apart than this start a new group even when they come
  /// from the same sender.
  static const Duration groupWindow = Duration(minutes: 5);

  /// A date pill ("Today", "Yesterday", …) is drawn above the message.
  final bool showDateSeparator;

  /// First bubble of a run by the same sender: shows the sender name.
  final bool isFirstInGroup;

  /// Last bubble of a run by the same sender: shows the tail and the avatar.
  final bool isLastInGroup;

  static bool _sameGroup(ChatMessage older, ChatMessage newer) {
    if (older.senderId != newer.senderId) return false;
    return newer.createdAt.difference(older.createdAt).abs() <= groupWindow;
  }

  @override
  bool operator ==(Object other) =>
      other is MessageLayout &&
      other.showDateSeparator == showDateSeparator &&
      other.isFirstInGroup == isFirstInGroup &&
      other.isLastInGroup == isLastInGroup;

  @override
  int get hashCode =>
      Object.hash(showDateSeparator, isFirstInGroup, isLastInGroup);
}
