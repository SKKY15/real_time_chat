import 'package:material_ui/material_ui.dart';

import '../models/chat_message.dart';

/// The small delivery indicator of an outgoing message:
/// clock (sending), one check (sent), two checks (seen), alert (failed).
class MessageStatusIcon extends StatelessWidget {
  const MessageStatusIcon({
    super.key,
    required this.status,
    required this.color,
    required this.seenColor,
    required this.failedColor,
  });

  final MessageStatus status;
  final Color color;
  final Color seenColor;
  final Color failedColor;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tint, String label) = switch (status) {
      MessageStatus.sending => (Icons.schedule_rounded, color, 'Sending'),
      MessageStatus.sent => (Icons.check_rounded, color, 'Sent'),
      MessageStatus.seen => (Icons.done_all_rounded, seenColor, 'Seen'),
      MessageStatus.failed => (
        Icons.error_outline_rounded,
        failedColor,
        'Not sent',
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Icon(
        icon,
        key: ValueKey<MessageStatus>(status),
        size: status == MessageStatus.sending ? 13 : 15,
        color: tint,
        semanticLabel: label,
      ),
    );
  }
}
