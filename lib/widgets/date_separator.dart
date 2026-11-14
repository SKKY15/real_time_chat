import 'package:material_ui/material_ui.dart';

import '../theme/chat_colors.dart';
import '../utils/date_labels.dart';

/// Centered pill above the first message of a day: "Today", "Yesterday", …
class DateSeparator extends StatelessWidget {
  const DateSeparator({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Center(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.pill,
            shape: const StadiumBorder(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              DateLabels.day(date),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.onPill, letterSpacing: 0.1),
            ),
          ),
        ),
      ),
    );
  }
}
