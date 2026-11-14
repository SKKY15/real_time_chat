import 'package:material_ui/material_ui.dart';

import '../theme/chat_colors.dart';

/// Draws the app as a phone screen with rounded corners.
///
/// Three cases, by the width of the window:
///
///  * [minWidth] or wider (560 px: a browser window, a desktop): the app is
///    boxed in a screen [screenWidth] wide, centered on walls of
///    [ChatColors.bezel].
///  * narrower, down to [minCorneredWidth]: the app takes every pixel it is
///    given and only its four corners are rounded, with the wall color showing
///    through them.
///  * narrower still: the app is left alone.
///
/// The app is never shrunk to make room for the frame, and it keeps normal
/// global coordinates inside it, so menus, the keyboard and links behave as
/// they do without it.
///
/// Only the corners are rounded; the top and the bottom of the walls stay
/// square, so the keyboard reaches the bottom of the window and the menu of a
/// message can still slide to the top of the app.
///
/// Widgets that round their own corners to match the screen (the app bar) ask
/// [cornersOf].
///
/// On a phone the corners of the screen are drawn by the phone itself, so the
/// frame only shows something in a window, where the app is not alone: a
/// browser, a desktop window, a tablet in landscape.
class RoundedWindow extends StatelessWidget {
  const RoundedWindow({super.key, required this.child});

  final Widget child;

  /// How wide the frame's screen is.
  static const double screenWidth = 480;

  /// Radius of the screen's corners.
  static const double cornerRadius = 34;

  /// Room between the screen and the walls, so the frame is visible.
  static const double margin = 40;

  /// Narrowest window that can hold the screen and its walls.
  static const double minWidth = screenWidth + 2 * margin;

  /// Narrowest window that still gets rounded corners. Below it there is too
  /// little room for them.
  static const double minCorneredWidth = 320;

  /// The corners the app is drawn with. Widgets that round their own corners
  /// to match the screen use it (the app bar).
  static const BorderRadius screenCorners = BorderRadius.all(
    Radius.circular(cornerRadius),
  );

  /// The shape of the screen: the [size] rectangle with rounded corners.
  static Path screenClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        Offset.zero & size,
        topLeft: const Radius.circular(cornerRadius),
        topRight: const Radius.circular(cornerRadius),
        bottomLeft: const Radius.circular(cornerRadius),
        bottomRight: const Radius.circular(cornerRadius),
      ),
    );

  /// Whether the app is drawn with rounded corners.
  static bool cornersOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScreenShape>()?.corners ??
      false;

  /// The app, cut to the rounded screen, with a hairline along its edge so
  /// that the screen reads as an edge even when the walls are dark too.
  static Widget _screen(BuildContext context, Widget child, Size size) {
    final edge = Theme.of(context).colorScheme.outlineVariant;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ClipPath(
          clipper: _ScreenClipper(),
          child: _ScreenShape(corners: true, child: child),
        ),
        IgnorePointer(child: CustomPaint(painter: _ScreenEdge(edge, size))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < minWidth) {
          if (width < minCorneredWidth) return child;
          return ColoredBox(
            color: ChatColors.of(context).bezel,
            child: _screen(context, child, Size(width, constraints.maxHeight)),
          );
        }
        final size = Size(screenWidth, constraints.maxHeight);
        return ColoredBox(
          color: ChatColors.of(context).bezel,
          child: Center(
            child: SizedBox.fromSize(
              size: size,
              // The app measures itself against the screen, not against the
              // window around it: a bubble may not grow wider than a phone.
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: size),
                child: _screen(context, child, size),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tells the widgets inside [RoundedWindow] that the screen has corners.
class _ScreenShape extends InheritedWidget {
  const _ScreenShape({required this.corners, required super.child});

  final bool corners;

  @override
  bool updateShouldNotify(_ScreenShape oldWidget) =>
      oldWidget.corners != corners;
}

/// The hairline along the screen's edge.
class _ScreenEdge extends CustomPainter {
  const _ScreenEdge(this.color, this.size);

  final Color color;

  /// The size of the screen, which is not always the size of the painter.
  final Size size;

  static const double _width = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    // Half the stroke falls outside the screen, where the clip hides it.
    canvas.drawPath(
      RoundedWindow.screenClip(this.size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ScreenEdge oldDelegate) =>
      oldDelegate.color != color || oldDelegate.size != size;
}

/// Cuts the screen to the shape of [RoundedWindow.screenClip].
class _ScreenClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => RoundedWindow.screenClip(size);

  @override
  bool shouldReclip(_ScreenClipper oldClipper) => false;
}
