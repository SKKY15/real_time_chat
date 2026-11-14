import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../models/chat_message.dart';
import '../widgets/bubble_border.dart';

/// Actions offered by the long-press menu of a message.
enum MessageAction { reply, copy, edit, delete, retry, discard }

const double _itemHeight = 46;
const double _menuPadding = 8;

/// Distance between the bubble and its menu.
const double _gap = 6;

/// Distance the menu keeps from the screen edges and the keyboard.
const double _margin = 8;

/// Shows the long-press menu for [message] and returns the chosen action, or
/// `null` when the menu is dismissed.
///
/// The menu opens below the bubble ([bubbleRect], in global coordinates), on
/// the bubble's side of the screen. Without room below it opens above the
/// bubble, and for a bubble that fills the screen next to the finger
/// ([globalPosition]). The pressed message stays readable that way.
///
/// The menu does not take focus, so an open keyboard stays open and the list
/// does not jump. It stays clear of that keyboard.
Future<MessageAction?> showMessageMenu({
  required BuildContext context,
  required Rect bubbleRect,
  required Offset globalPosition,
  required ChatMessage message,
  required bool isMine,
}) {
  final actions = _actionsFor(message, isMine: isMine);
  if (actions.isEmpty) return Future<MessageAction?>.value();

  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  // Asked from the view: inside the scaffold the media query no longer knows
  // about the keyboard.
  final media = MediaQueryData.fromView(View.of(context));
  final scheme = Theme.of(context).colorScheme;

  final origin = overlay.localToGlobal(Offset.zero);
  final bubble = bubbleRect.shift(-origin);
  final top = media.viewPadding.top + _margin;
  final bottom =
      overlay.size.height -
      math.max(media.viewInsets.bottom, media.viewPadding.bottom) -
      _margin;
  final height = actions.length * _itemHeight + 2 * _menuPadding;

  final double y;
  if (bubble.bottom + _gap + height <= bottom) {
    y = bubble.bottom + _gap;
  } else if (bubble.top - _gap - height >= top) {
    y = bubble.top - _gap - height;
  } else {
    final lowest = math.max(top, bottom - height);
    y = math.min(math.max(globalPosition.dy - origin.dy, top), lowest);
  }
  // The outer edge of the bubble's body (the bubble keeps room for its tail
  // there). A menu anchored in the right half of the screen grows to the
  // left, and the other way around, so it lines up with that edge.
  final x = isMine
      ? bubble.right - BubbleBorder.tailWidth
      : bubble.left + BubbleBorder.tailWidth;

  return showMenu<MessageAction>(
    context: context,
    requestFocus: false,
    position: RelativeRect.fromLTRB(
      x,
      y,
      overlay.size.width - x,
      overlay.size.height - y,
    ),
    menuPadding: const EdgeInsets.symmetric(vertical: _menuPadding),
    constraints: const BoxConstraints(minWidth: 210),
    items: <PopupMenuEntry<MessageAction>>[
      for (final action in actions)
        PopupMenuItem<MessageAction>(
          value: action,
          height: _itemHeight,
          child: _MenuRow(
            icon: _icon(action),
            label: _label(action),
            color: _isDestructive(action) ? scheme.error : scheme.onSurface,
          ),
        ),
    ],
  );
}

List<MessageAction> _actionsFor(ChatMessage message, {required bool isMine}) {
  if (message.sendFailed) {
    return const <MessageAction>[MessageAction.retry, MessageAction.discard];
  }
  if (message.deleted) return const <MessageAction>[];
  final isStored = message.hasServerTimestamp;
  return <MessageAction>[
    if (isStored) MessageAction.reply,
    MessageAction.copy,
    if (isMine && isStored) MessageAction.edit,
    if (isMine && isStored) MessageAction.delete,
  ];
}

IconData _icon(MessageAction action) => switch (action) {
  MessageAction.reply => Icons.reply_rounded,
  MessageAction.copy => Icons.copy_rounded,
  MessageAction.edit => Icons.edit_rounded,
  MessageAction.delete => Icons.delete_outline_rounded,
  MessageAction.retry => Icons.refresh_rounded,
  MessageAction.discard => Icons.delete_outline_rounded,
};

String _label(MessageAction action) => switch (action) {
  MessageAction.reply => 'Reply',
  MessageAction.copy => 'Copy',
  MessageAction.edit => 'Edit',
  MessageAction.delete => 'Delete for everyone',
  MessageAction.retry => 'Try again',
  MessageAction.discard => 'Discard',
};

bool _isDestructive(MessageAction action) =>
    action == MessageAction.delete || action == MessageAction.discard;

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
