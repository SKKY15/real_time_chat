import 'package:material_ui/material_ui.dart';

import '../theme/chat_colors.dart';

/// The app's mark: one of my own bubbles, caught while typing.
///
/// A rounded square in the accent color, with the pointed corner of an
/// outgoing bubble and three dots inside.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final round = Radius.circular(size * 0.36);
    final dot = size * 0.13;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.accent,
          borderRadius: BorderRadius.only(
            topLeft: round,
            topRight: round,
            bottomLeft: round,
            bottomRight: Radius.circular(size * 0.1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: dot * 0.3),
                child: SizedBox.square(
                  dimension: dot,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.onAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
