import 'package:material_ui/material_ui.dart';

import '../chat/message_layout.dart';
import '../models/chat_message.dart';
import '../theme/chat_colors.dart';
import 'date_separator.dart';
import 'message_bubble.dart';
import 'swipe_to_reply.dart';
import 'user_avatar.dart';
import 'vertical_reveal.dart';

/// Lookup from message id to the row currently built for it.
///
/// Rows register themselves while they are mounted. The list uses this to
/// scroll to a quoted message and to flash it, without global keys.
class MessageRowRegistry {
  final Map<String, _MessageRowState> _rows = <String, _MessageRowState>{};

  /// Build context of the row showing [messageId], if it is built right now.
  BuildContext? contextOf(String messageId) {
    final row = _rows[messageId];
    return row != null && row.mounted ? row.context : null;
  }

  /// Ids of all rows that are built right now (visible or in the cache
  /// area around the viewport).
  Iterable<String> get builtIds => _rows.keys;

  /// Plays the highlight pulse on the row of [messageId].
  bool flash(String messageId) {
    final row = _rows[messageId];
    if (row == null || !row.mounted) return false;
    row._flash();
    return true;
  }

  void _attach(String messageId, _MessageRowState row) =>
      _rows[messageId] = row;

  void _detach(String messageId, _MessageRowState row) {
    if (identical(_rows[messageId], row)) _rows.remove(messageId);
  }
}

/// Callbacks shared by every row. One instance for the whole list, so
/// building a row allocates no closures.
@immutable
class MessageRowActions {
  const MessageRowActions({
    required this.shouldAnimateIn,
    required this.onReply,
    required this.onOpenMenu,
    required this.onQuoteTap,
  });

  /// One-shot: `true` if the row of this message should play its entrance.
  final bool Function(String messageId) shouldAnimateIn;

  /// The bubble was swiped to the right.
  final void Function(ChatMessage message) onReply;

  /// The bubble, which covers [bubbleRect] on screen, was long-pressed at
  /// [globalPosition].
  final void Function(
    ChatMessage message,
    Rect bubbleRect,
    Offset globalPosition,
  )
  onOpenMenu;

  /// The quote inside a reply was tapped.
  final void Function(String quotedMessageId) onQuoteTap;
}

/// One entry of the message list: optional date separator, avatar and bubble.
///
/// New messages slide up and fade in (230 ms, ease-out cubic) while the row
/// grows from zero height, so the messages above glide instead of jumping.
class MessageRow extends StatefulWidget {
  const MessageRow({
    super.key,
    required this.message,
    required this.layout,
    required this.isMine,
    required this.registry,
    required this.actions,
  });

  final ChatMessage message;
  final MessageLayout layout;
  final bool isMine;
  final MessageRowRegistry registry;
  final MessageRowActions actions;

  @override
  State<MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<MessageRow> with TickerProviderStateMixin {
  static const Duration _entranceDuration = Duration(milliseconds: 230);
  static const Duration _flashDuration = Duration(milliseconds: 1100);

  AnimationController? _entrance;
  CurvedAnimation? _entranceCurve;
  AnimationController? _flashController;

  /// `true` while the entrance animation is running.
  bool _entering = false;

  /// Lets the content keep its state when the entrance wrappers are removed.
  GlobalKey? _contentKey;

  @override
  void initState() {
    super.initState();
    widget.registry._attach(widget.message.id, this);
    if (widget.actions.shouldAnimateIn(widget.message.id)) {
      _contentKey = GlobalKey();
      final controller = AnimationController(
        vsync: this,
        duration: _entranceDuration,
      );
      _entrance = controller;
      _entranceCurve = CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
      );
      _entering = true;
      controller.forward().whenCompleteOrCancel(_onEntranceDone);
    }
  }

  @override
  void didUpdateWidget(MessageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        !identical(oldWidget.registry, widget.registry)) {
      oldWidget.registry._detach(oldWidget.message.id, this);
      widget.registry._attach(widget.message.id, this);
    }
  }

  @override
  void dispose() {
    widget.registry._detach(widget.message.id, this);
    _entranceCurve?.dispose();
    _entrance?.dispose();
    _flashController?.dispose();
    super.dispose();
  }

  void _onEntranceDone() {
    if (!mounted) return;
    // Drop the transition widgets (and their clip) once the row is in place.
    setState(() => _entering = false);
  }

  void _flash() {
    final controller = _flashController ??= AnimationController(
      vsync: this,
      duration: _flashDuration,
    );
    controller.forward(from: 0);
    setState(() {});
  }

  void _onReply() => widget.actions.onReply(widget.message);

  void _onLongPress(Rect bubbleRect, Offset globalPosition) =>
      widget.actions.onOpenMenu(widget.message, bubbleRect, globalPosition);

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final layout = widget.layout;
    final isMine = widget.isMine;
    final canReply = !message.deleted && message.hasServerTimestamp;

    final bubble = _LongPressArea(
      onLongPress: _onLongPress,
      child: RepaintBoundary(
        child: MessageBubble(
          message: message,
          isMine: isMine,
          isFirstInGroup: layout.isFirstInGroup,
          isLastInGroup: layout.isLastInGroup,
          onQuoteTap: widget.actions.onQuoteTap,
        ),
      ),
    );

    Widget content = Column(
      key: _contentKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (layout.showDateSeparator) DateSeparator(date: message.createdAt),
        _FlashBackground(
          animation: _flashController,
          child: SwipeToReply(
            enabled: canReply,
            onReply: _onReply,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                8,
                layout.isFirstInGroup ? 5 : 1.5,
                8,
                layout.isLastInGroup ? 5 : 1.5,
              ),
              child: Row(
                mainAxisAlignment: isMine
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (!isMine)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: layout.isLastInGroup
                          ? UserAvatar(
                              userId: message.senderId,
                              name: message.senderName,
                            )
                          : const SizedBox(width: 28),
                    ),
                  Flexible(child: bubble),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    final curve = _entranceCurve;
    if (_entering && curve != null) {
      content = VerticalReveal(
        factor: curve,
        child: FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(curve),
            child: content,
          ),
        ),
      );
    }
    return content;
  }
}

/// Reports a long press on [child] together with the area [child] covers on
/// screen.
class _LongPressArea extends StatelessWidget {
  const _LongPressArea({required this.onLongPress, required this.child});

  final void Function(Rect globalRect, Offset globalPosition) onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) {
        final box = context.findRenderObject()! as RenderBox;
        onLongPress(
          box.localToGlobal(Offset.zero) & box.size,
          details.globalPosition,
        );
      },
      child: child,
    );
  }
}

/// Tints the row for a moment after jumping to it from a quote.
class _FlashBackground extends StatelessWidget {
  const _FlashBackground({required this.animation, required this.child});

  /// `null` until the row is flashed for the first time.
  final Animation<double>? animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = ChatColors.of(context).highlight;
    return AnimatedBuilder(
      animation: animation ?? kAlwaysDismissedAnimation,
      builder: (context, child) {
        final t = animation?.value ?? 0;
        // Quick fade in, slow fade out.
        final strength = t <= 0 || t >= 1
            ? 0.0
            : t < 0.12
            ? t / 0.12
            : 1 - Curves.easeIn.transform((t - 0.12) / 0.88);
        return ColoredBox(
          color: color.withValues(alpha: color.a * strength),
          child: child,
        );
      },
      child: child,
    );
  }
}
