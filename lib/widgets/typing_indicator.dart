import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../chat/typing_controller.dart';
import '../chat/typing_tracker.dart';
import '../theme/chat_colors.dart';

/// "Sara is typing…" with three bouncing dots, shown above the input bar.
///
/// It watches its own provider, so somebody typing rebuilds this widget and
/// nothing else. It opens and closes with a size + fade animation.
class TypingIndicator extends ConsumerWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typing = ref.watch(typingUsersProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: _layout,
        child: typing.isEmpty
            ? const SizedBox(
                key: ValueKey<String>('idle'),
                width: double.infinity,
              )
            : _TypingRow(
                key: const ValueKey<String>('typing'),
                text: typingLabel([for (final user in typing) user.name]),
              ),
      ),
    );
  }

  static Widget _layout(Widget? currentChild, List<Widget> previousChildren) {
    final children = <Widget>[...previousChildren];
    if (currentChild != null) children.add(currentChild);
    return Stack(alignment: Alignment.bottomLeft, children: children);
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: colors.incomingMeta);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: <Widget>[
          DecoratedBox(
            decoration: ShapeDecoration(
              color: colors.incoming,
              shape: const StadiumBorder(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: BouncingDots(color: colors.incomingMeta),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// Three dots bouncing one after the other.
///
/// The animation only runs while the widget is on screen and repaints
/// nothing but its own small layer.
class BouncingDots extends StatefulWidget {
  const BouncingDots({super.key, required this.color, this.dotSize = 6});

  final Color color;
  final double dotSize;

  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.dotSize;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(size * 3 + size * 0.7 * 2, size * 1.9),
        painter: _DotsPainter(
          progress: _controller,
          color: widget.color,
          dotSize: size,
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required this.progress,
    required this.color,
    required this.dotSize,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double dotSize;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = dotSize / 2;
    final gap = dotSize * 0.7;
    final lift = size.height - dotSize;
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      // Each dot starts its hop a little after the previous one and rests
      // for the second half of the cycle.
      final phase = (progress.value - i * 0.16) % 1.0;
      final hop = phase < 0.5 ? math.sin(phase * 2 * math.pi) : 0.0;
      paint.color = color.withValues(alpha: 0.55 + 0.45 * hop);
      canvas.drawCircle(
        Offset(radius + i * (dotSize + gap), size.height - radius - lift * hop),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dotSize != dotSize;
}
