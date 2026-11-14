import 'package:flutter/widgets.dart';

/// Outline of a chat bubble: a rounded rectangle with an optional tail.
///
/// * The side facing the sender (right for outgoing, left for incoming)
///   always reserves [tailWidth], so bubbles with and without a tail line up.
/// * Bubbles inside a group get a tighter corner where they touch their
///   neighbours ([joinedAbove] / [joinedBelow]).
/// * Only the last bubble of a group draws the tail ([hasTail]).
@immutable
class BubbleBorder extends ShapeBorder {
  const BubbleBorder({
    required this.isOutgoing,
    this.hasTail = false,
    this.joinedAbove = false,
    this.joinedBelow = false,
  });

  /// Horizontal space the tail sticks out of the bubble body.
  static const double tailWidth = 6;
  static const double radius = 20;
  static const double joinedRadius = 6;

  final bool isOutgoing;
  final bool hasTail;
  final bool joinedAbove;
  final bool joinedBelow;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(
    left: isOutgoing ? 0 : tailWidth,
    right: isOutgoing ? tailWidth : 0,
  );

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Rect.fromLTRB(
      isOutgoing ? rect.left : rect.left + tailWidth,
      rect.top,
      isOutgoing ? rect.right - tailWidth : rect.right,
      rect.bottom,
    );
    // Very small bubbles cannot fit the full radius.
    final big = Radius.circular(
      radius.clamp(0.0, body.shortestSide / 2).toDouble(),
    );
    const small = Radius.circular(joinedRadius);
    final top = joinedAbove ? small : big;
    final bottom = joinedBelow && !hasTail ? small : big;

    final bubble = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          body,
          topLeft: isOutgoing ? big : top,
          topRight: isOutgoing ? top : big,
          bottomLeft: isOutgoing ? big : bottom,
          bottomRight: isOutgoing ? bottom : big,
        ),
      );
    if (!hasTail) return bubble;
    return Path.combine(PathOperation.union, bubble, _tail(body, big.x));
  }

  /// A pointed tail growing out of the bottom corner on the sender's side.
  ///
  /// The side of the bubble runs straight down, sweeps outwards to a tip
  /// [tailWidth] beyond the body and returns along the baseline, so there is
  /// no kink where the tail meets the bubble.
  Path _tail(Rect body, double r) {
    final side = isOutgoing ? 1.0 : -1.0;
    final edge = isOutgoing ? body.right : body.left;
    final bottom = body.bottom;
    double x(double inset) => edge - side * inset;

    return Path()
      ..moveTo(edge, bottom - r)
      ..lineTo(edge, bottom - r * 0.55)
      ..quadraticBezierTo(x(-0.5), bottom - 2, x(-tailWidth), bottom)
      ..lineTo(x(r), bottom)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;

  @override
  bool operator ==(Object other) =>
      other is BubbleBorder &&
      other.isOutgoing == isOutgoing &&
      other.hasTail == hasTail &&
      other.joinedAbove == joinedAbove &&
      other.joinedBelow == joinedBelow;

  @override
  int get hashCode =>
      Object.hash(isOutgoing, hasTail, joinedAbove, joinedBelow);
}
