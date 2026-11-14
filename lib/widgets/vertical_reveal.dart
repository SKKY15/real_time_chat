import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Animates the height of [child] from nothing to its natural height.
///
/// The box is exactly as wide as the child, so whatever positions the child
/// horizontally (a `Row`, a `Stack` alignment) keeps doing so while it
/// animates. Vertically the child stays pinned to [alignment] and the rest is
/// clipped, which makes it look like it slides out from behind an edge.
class VerticalReveal extends AnimatedWidget {
  const VerticalReveal({
    super.key,
    required Animation<double> factor,
    this.alignment = Alignment.topCenter,
    this.child,
  }) : super(listenable: factor);

  /// Which edge of the child stays in place while the box grows.
  final AlignmentGeometry alignment;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final factor = listenable as Animation<double>;
    return ClipRect(
      child: Align(
        alignment: alignment,
        widthFactor: 1,
        heightFactor: math.max(factor.value, 0),
        child: child,
      ),
    );
  }
}
