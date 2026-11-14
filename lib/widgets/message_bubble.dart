import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../models/chat_message.dart';
import '../theme/chat_colors.dart';
import '../utils/date_labels.dart';
import '../utils/text_direction.dart';
import 'bubble_border.dart';
import 'message_status_icon.dart';
import 'reply_quote.dart';
import 'user_avatar.dart';
import 'vertical_reveal.dart';

/// A single chat bubble.
///
/// Outgoing bubbles are filled with the accent color, incoming ones with a
/// neutral surface color. When the message gets deleted the content collapses
/// (size + fade) and "This message was deleted" takes its place.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    this.onQuoteTap,
  });

  final ChatMessage message;
  final bool isMine;

  /// First bubble of a sender group: incoming bubbles show the sender name.
  final bool isFirstInGroup;

  /// Last bubble of a sender group: the only one that gets a tail.
  final bool isLastInGroup;

  /// Called with the id of the quoted message when the quote is tapped.
  final ValueChanged<String>? onQuoteTap;

  /// Keeps the outgoing and the incoming child anchored to the bubble's own
  /// corner while they cross-fade.
  Widget _layout(Widget? currentChild, List<Widget> previousChildren) {
    final children = <Widget>[...previousChildren];
    if (currentChild != null) children.add(currentChild);
    return Stack(
      alignment: isMine ? Alignment.bottomRight : Alignment.bottomLeft,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: _layout,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: VerticalReveal(factor: animation, child: child),
      ),
      child: message.deleted
          ? _DeletedBubble(
              key: const ValueKey<String>('deleted'),
              isMine: isMine,
            )
          : _ContentBubble(
              key: const ValueKey<String>('content'),
              message: message,
              isMine: isMine,
              isFirstInGroup: isFirstInGroup,
              isLastInGroup: isLastInGroup,
              onQuoteTap: onQuoteTap,
            ),
    );
  }
}

class _ContentBubble extends StatelessWidget {
  const _ContentBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.onQuoteTap,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final ValueChanged<String>? onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChatColors.of(context);
    final textColor = isMine ? colors.onAccent : colors.onIncoming;
    final reply = message.replyTo;
    final showSender = !isMine && isFirstInGroup;
    final senderColor = colorForUser(message.senderId, theme.brightness);
    // Only the size aspect: the bubble must not rebuild while the keyboard
    // animates the view insets.
    final maxWidth = math.min(MediaQuery.sizeOf(context).width * 0.78, 440.0);

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: reply == null
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showSender)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              message.senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: senderColor),
            ),
          ),
        if (reply != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: ReplyQuote(
              reply: reply,
              bar: isMine ? colors.onAccent : colors.accent,
              nameColor: isMine ? colors.onAccent : theme.colorScheme.primary,
              background: isMine ? colors.outgoingQuote : colors.incomingQuote,
              textColor: textColor,
              onTap: onQuoteTap == null
                  ? null
                  : () => onQuoteTap!(reply.messageId),
            ),
          ),
        _TextWithMeta(message: message, isMine: isMine),
      ],
    );
    // Makes the quote as wide as the text below it. Intrinsic sizing costs an
    // extra layout pass, so it is only paid by bubbles that carry a quote.
    if (reply != null) content = IntrinsicWidth(child: content);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: isMine ? colors.accent : colors.incoming,
          shape: BubbleBorder(
            isOutgoing: isMine,
            hasTail: isLastInGroup,
            joinedAbove: !isFirstInGroup,
            joinedBelow: !isLastInGroup,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isMine ? 12 : 12 + BubbleBorder.tailWidth,
            7,
            isMine ? 12 + BubbleBorder.tailWidth : 12,
            7,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Message text with the time (and "edited", and the status icon) tucked into
/// the end of the last line, the way messengers do it.
class _TextWithMeta extends StatelessWidget {
  const _TextWithMeta({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChatColors.of(context);
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      color: isMine ? colors.onAccent : colors.onIncoming,
      fontSize: 15.5,
      height: 1.32,
    );
    final time = DateLabels.time(
      message.createdAt,
      use24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final meta = _Meta(message: message, isMine: isMine, time: time);

    if (isRightToLeft(message.text)) {
      // Right-to-left text ends on the left, so the time gets its own line.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            message.text,
            textDirection: TextDirection.rtl,
            textWidthBasis: TextWidthBasis.longestLine,
            style: textStyle,
          ),
          const SizedBox(height: 2),
          meta,
        ],
      );
    }

    return Stack(
      children: <Widget>[
        Text.rich(
          TextSpan(
            text: message.text,
            children: <InlineSpan>[
              // Invisible copy of the meta row: reserves exactly the room it
              // needs at the end of the last line, or wraps onto a new line
              // when the text leaves no space.
              WidgetSpan(
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: 0,
                    child: _Meta(
                      message: message,
                      isMine: isMine,
                      time: time,
                      isPlaceholder: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // The bubble is as wide as its longest line, not as wide as it is
          // allowed to be, when the text wraps.
          textWidthBasis: TextWidthBasis.longestLine,
          style: textStyle,
        ),
        Positioned.fill(
          child: Align(alignment: Alignment.bottomRight, child: meta),
        ),
      ],
    );
  }
}

/// "edited 17:42 ✓✓"
class _Meta extends StatelessWidget {
  const _Meta({
    required this.message,
    required this.isMine,
    required this.time,
    this.isPlaceholder = false,
  });

  final ChatMessage message;
  final bool isMine;
  final String time;

  /// The invisible copy used to reserve space: keeps the size, skips the
  /// animated parts.
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final color = isMine ? colors.outgoingMeta : colors.incomingMeta;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: color, fontSize: 11, height: 1.2, letterSpacing: 0);
    // Shrinks instead of overflowing when a narrow bubble meets a very large
    // system font. At its natural size this adds no layer.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (message.isEdited) Text('edited  ', style: style),
            Text(time, style: style),
            if (isMine) ...<Widget>[
              const SizedBox(width: 3),
              if (isPlaceholder)
                const SizedBox(width: 15, height: 15)
              else
                SizedBox(
                  width: 15,
                  height: 15,
                  child: Center(
                    child: MessageStatusIcon(
                      status: message.status,
                      color: color,
                      seenColor: colors.seen,
                      failedColor: colors.outgoingAlert,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeletedBubble extends StatelessWidget {
  const _DeletedBubble({super.key, required this.isMine});

  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      // Lines up with the bodies of regular bubbles, which keep this gap for
      // their tail.
      padding: EdgeInsets.only(
        left: isMine ? 0 : BubbleBorder.tailWidth,
        right: isMine ? BubbleBorder.tailWidth : 0,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(color: color.withValues(alpha: 0.35)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.block_rounded, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'This message was deleted',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
