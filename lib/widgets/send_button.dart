import 'package:material_ui/material_ui.dart';

import '../theme/chat_colors.dart';

/// Round accent-colored button of the input bar.
///
/// * dims and shrinks while there is nothing to send,
/// * swaps its arrow for a check mark while editing,
/// * "pops" (scales down and springs back) every time [pulse] runs.
class SendButton extends StatelessWidget {
  const SendButton({
    super.key,
    required this.enabled,
    required this.isEditing,
    required this.pulse,
    required this.onPressed,
  });

  final bool enabled;
  final bool isEditing;

  /// Runs from 0 to 1 once per send.
  final Animation<double> pulse;
  final VoidCallback onPressed;

  static final Animatable<double> _pop = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1,
          end: 0.8,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 0.8,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 65,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: isEditing ? 'Save changes' : 'Send message',
      child: ScaleTransition(
        scale: _pop.animate(pulse),
        child: AnimatedScale(
          scale: enabled ? 1 : 0.88,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.4,
            duration: const Duration(milliseconds: 180),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent,
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled ? onPressed : null,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Icon(
                        isEditing
                            ? Icons.check_rounded
                            : Icons.arrow_upward_rounded,
                        key: ValueKey<bool>(isEditing),
                        color: colors.onAccent,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
