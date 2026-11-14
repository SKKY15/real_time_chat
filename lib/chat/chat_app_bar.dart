import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_controller.dart';
import '../services/providers.dart';
import '../theme/chat_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/brand_mark.dart';
import '../widgets/rounded_window.dart';
import 'chat_controller.dart';

enum _MenuAction { seed, signOut }

/// Title bar of the room: name, who you are, theme switch and overflow menu.
class ChatAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ChatAppBar({super.key});

  static const String roomName = 'Lounge';

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.seed:
        await _seed(context, ref);
      case _MenuAction.signOut:
        await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  Future<void> _seed(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authControllerProvider);
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final seeder = ref.read(demoSeederProvider);
    try {
      final count = await seeder.seed(user);
      if (!context.mounted) return;
      ref.read(chatControllerProvider.notifier).resyncAfterBackfill();
      messenger.showSnackBar(
        SnackBar(content: Text('Added $count sample messages')),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not add the sample messages. '
            'Are the Firestore rules deployed?',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    final name = ref.watch(authControllerProvider.select((user) => user?.name));
    final isDark = theme.brightness == Brightness.dark;
    // Without corners on the screen (a real phone), the bar stays flat; with
    // them, it rounds its own top corners to match.
    final rounded = RoundedWindow.cornersOf(context);
    const flat = BorderRadius.zero;

    return AppBar(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      shape: RoundedRectangleBorder(
        borderRadius: rounded ? RoundedWindow.screenCorners : flat,
        side: BorderSide(color: colors.hairline),
      ),
      title: ClipRRect(
        borderRadius: rounded ? RoundedWindow.screenCorners : flat,
        child: Row(
          children: <Widget>[
            const BrandMark(size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    roomName,
                    style: theme.textTheme.titleMedium?.copyWith(height: 1.2),
                  ),
                  Text(
                    name == null || name.isEmpty
                        ? 'Group chat'
                        : 'You are $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.incomingMeta,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: isDark ? 'Light mode' : 'Dark mode',
          onPressed: () =>
              ref.read(themeModeProvider.notifier).toggle(theme.brightness),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutBack,
            transitionBuilder: (child, animation) => RotationTransition(
              turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              key: ValueKey<bool>(isDark),
            ),
          ),
        ),
        PopupMenuButton<_MenuAction>(
          tooltip: 'More',
          onSelected: (action) => _onMenu(context, ref, action),
          itemBuilder: (context) => const <PopupMenuEntry<_MenuAction>>[
            PopupMenuItem<_MenuAction>(
              value: _MenuAction.seed,
              child: _MenuLabel(
                icon: Icons.auto_awesome_rounded,
                label: 'Add 40 sample messages',
              ),
            ),
            PopupMenuItem<_MenuAction>(
              value: _MenuAction.signOut,
              child: _MenuLabel(icon: Icons.logout_rounded, label: 'Sign out'),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20),
        const SizedBox(width: 14),
        Flexible(child: Text(label)),
      ],
    );
  }
}
