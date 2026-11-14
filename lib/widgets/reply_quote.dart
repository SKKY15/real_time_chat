import 'package:material_ui/material_ui.dart';

import '../models/reply_preview.dart';
import '../utils/text_direction.dart';

/// The quoted message shown at the top of a reply bubble. Tapping it jumps
/// to the original message.
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({
    super.key,
    required this.reply,
    required this.bar,
    required this.nameColor,
    required this.background,
    required this.textColor,
    this.onTap,
  });

  final ReplyPreview reply;

  /// Color of the stripe along the start of the quote.
  final Color bar;
  final Color nameColor;
  final Color background;
  final Color textColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasText = reply.text.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            border: Border(left: BorderSide(color: bar, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 6, 10, 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  reply.senderName.isEmpty ? 'Message' : reply.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(color: nameColor),
                ),
                const SizedBox(height: 1),
                Text(
                  hasText ? reply.text : 'Message',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: directionOf(reply.text),
                  style: textTheme.bodySmall?.copyWith(
                    color: textColor.withValues(alpha: 0.85),
                    fontStyle: hasText ? FontStyle.normal : FontStyle.italic,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
