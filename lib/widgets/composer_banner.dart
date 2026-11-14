import 'package:material_ui/material_ui.dart';

import '../theme/chat_colors.dart';
import '../utils/text_direction.dart';
import 'vertical_reveal.dart';

/// What the bar above the text field shows: the message being replied to or
/// the message being edited.
@immutable
class ComposerBannerData {
  const ComposerBannerData({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ComposerBannerData &&
      other.icon == icon &&
      other.title == title &&
      other.text == text;

  @override
  int get hashCode => Object.hash(icon, title, text);
}

/// Reply / edit preview above the text field.
///
/// Slides open when [data] is set and closes when it becomes `null`. The
/// last content stays visible while the bar closes.
class ComposerBanner extends StatefulWidget {
  const ComposerBanner({super.key, required this.data, required this.onClose});

  final ComposerBannerData? data;
  final VoidCallback onClose;

  @override
  State<ComposerBanner> createState() => _ComposerBannerState();
}

class _ComposerBannerState extends State<ComposerBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
    value: widget.data == null ? 0 : 1,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Content to show, kept while the bar animates shut.
  late ComposerBannerData? _shown = widget.data;

  @override
  void didUpdateWidget(ComposerBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final data = widget.data;
    if (data != null) {
      _shown = data;
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return VerticalReveal(
      factor: _curve,
      child: FadeTransition(
        opacity: _curve,
        child: shown == null
            ? const SizedBox(width: double.infinity)
            : _BannerContent(data: shown, onClose: widget.onClose),
      ),
    );
  }
}

class _BannerContent extends StatelessWidget {
  const _BannerContent({required this.data, required this.onClose});

  final ComposerBannerData data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 0),
      child: Row(
        children: <Widget>[
          Icon(data.icon, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  data.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: directionOf(data.text),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.incomingMeta,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Cancel',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: colors.incomingMeta,
            ),
          ),
        ],
      ),
    );
  }
}
