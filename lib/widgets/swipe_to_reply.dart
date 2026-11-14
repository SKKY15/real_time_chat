import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/chat_colors.dart';

/// Lets [child] be dragged to the right to trigger a reply.
///
/// The child follows the finger with growing resistance while a reply icon
/// fades in behind it. Crossing the threshold gives a haptic tick; releasing
/// past it calls [onReply]. The child then glides back into place.
///
/// Only a transform changes while dragging: [child] is neither rebuilt nor
/// (behind its repaint boundary) repainted.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  /// Drag distance at which the reply triggers.
  static const double _threshold = 56;

  /// The child never travels further than this.
  static const double _maxOffset = 84;

  /// Current horizontal offset of the child.
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  /// Drives the glide back to zero. Created on the first release, so rows
  /// that are never swiped carry no ticker.
  AnimationController? _settle;
  double _settleFrom = 0;

  double _dragged = 0;
  bool _armed = false;

  /// The hint icon joins the tree on the first drag only.
  bool _showHint = false;

  @override
  void dispose() {
    _settle?.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _settle?.stop();
    _dragged = _offset.value;
    _armed = false;
    if (!_showHint) setState(() => _showHint = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragged = (_dragged + (details.primaryDelta ?? 0)).clamp(0.0, 400.0);
    // Free movement up to the threshold, rubber-band resistance beyond it.
    final eased = _dragged <= _threshold
        ? _dragged
        : _threshold + (_dragged - _threshold) * 0.3;
    _offset.value = eased.clamp(0.0, _maxOffset);

    final armed = _dragged >= _threshold;
    if (armed != _armed) {
      _armed = armed;
      if (armed) HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails details) => _release(reply: _armed);

  void _onDragCancel() => _release(reply: false);

  void _release({required bool reply}) {
    _armed = false;
    _dragged = 0;
    _settleFrom = _offset.value;
    final settle = _settle ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(_onSettleTick);
    settle.forward(from: 0);
    if (reply) widget.onReply();
  }

  void _onSettleTick() {
    final t = Curves.easeOutCubic.transform(_settle?.value ?? 1);
    _offset.value = _settleFrom * (1 - t);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: enabled ? _onDragStart : null,
      onHorizontalDragUpdate: enabled ? _onDragUpdate : null,
      onHorizontalDragEnd: enabled ? _onDragEnd : null,
      onHorizontalDragCancel: enabled ? _onDragCancel : null,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          if (_showHint)
            Positioned(
              left: 14,
              child: ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (context, offset, child) {
                  final progress = (offset / _threshold).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.5 + 0.5 * progress,
                      child: child,
                    ),
                  );
                },
                child: const _ReplyHint(),
              ),
            ),
          // Keyed so the child keeps its element (and state) when the hint
          // above is inserted in front of it.
          ValueListenableBuilder<double>(
            key: const ValueKey<String>('swipe-child'),
            valueListenable: _offset,
            builder: (context, offset, child) =>
                Transform.translate(offset: Offset(offset, 0), child: child),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _ReplyHint extends StatelessWidget {
  const _ReplyHint();

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accent),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(Icons.reply_rounded, size: 18, color: colors.onAccent),
      ),
    );
  }
}
