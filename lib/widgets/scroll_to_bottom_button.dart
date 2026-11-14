import 'package:material_ui/material_ui.dart';

import '../theme/chat_colors.dart';

/// Round button that brings the list back to the newest message, with a
/// badge for messages that arrived in the meantime.
///
/// Visibility is animated (scale + fade); while hidden it ignores touches.
class ScrollToBottomButton extends StatelessWidget {
  const ScrollToBottomButton({
    super.key,
    required this.visible,
    required this.unreadCount,
    required this.onPressed,
  });

  final bool visible;
  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.6,
        duration: const Duration(milliseconds: 200),
        curve: visible ? Curves.easeOutBack : Curves.easeIn,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Material(
                color: scheme.surfaceContainerHigh,
                shape: const CircleBorder(),
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: 0.4),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 28,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: 'Scroll to latest message',
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -6,
                right: -4,
                child: _UnreadBadge(count: unreadCount),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChatColors.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: count <= 0
          ? const SizedBox.shrink(key: ValueKey<int>(0))
          : DecoratedBox(
              key: ValueKey<int>(count),
              decoration: ShapeDecoration(
                color: colors.accent,
                shape: const StadiumBorder(),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onAccent,
                        fontSize: 11,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
