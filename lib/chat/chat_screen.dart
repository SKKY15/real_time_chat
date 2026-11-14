import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_controller.dart';
import '../services/providers.dart';
import '../theme/chat_colors.dart';
import '../widgets/chat_composer.dart';
import '../widgets/typing_indicator.dart';
import 'chat_app_bar.dart';
import 'chat_controller.dart';
import 'message_list.dart';

/// The room: app bar, message history, typing indicator and input bar.
///
/// The three parts below the app bar are independent widgets with their own
/// providers. Typing (yours or theirs) therefore never rebuilds the list,
/// and a new message never rebuilds the input bar.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      appBar: ChatAppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: _History()),
          TypingIndicator(),
          ChatComposer(),
        ],
      ),
    );
  }
}

enum _HistoryView { loading, error, empty, messages }

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(
      chatControllerProvider.select((state) {
        if (state.messages.isNotEmpty) return _HistoryView.messages;
        if (state.error != null) return _HistoryView.error;
        return state.isLoading ? _HistoryView.loading : _HistoryView.empty;
      }),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: switch (view) {
        _HistoryView.loading => const Center(
          key: ValueKey<_HistoryView>(_HistoryView.loading),
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        _HistoryView.error => const _ErrorView(
          key: ValueKey<_HistoryView>(_HistoryView.error),
        ),
        _HistoryView.empty => const _EmptyView(
          key: ValueKey<_HistoryView>(_HistoryView.empty),
        ),
        _HistoryView.messages => const MessageList(
          key: ValueKey<_HistoryView>(_HistoryView.messages),
        ),
      },
    );
  }
}

class _EmptyView extends ConsumerStatefulWidget {
  const _EmptyView({super.key});

  @override
  ConsumerState<_EmptyView> createState() => _EmptyViewState();
}

class _EmptyViewState extends ConsumerState<_EmptyView> {
  bool _seeding = false;

  Future<void> _seed() async {
    final user = ref.read(authControllerProvider);
    if (user == null || _seeding) return;
    final messenger = ScaffoldMessenger.of(context);
    final seeder = ref.read(demoSeederProvider);
    setState(() => _seeding = true);
    try {
      await seeder.seed(user);
      if (mounted) {
        ref.read(chatControllerProvider.notifier).resyncAfterBackfill();
      }
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not add the sample messages. '
            'Are the Firestore rules deployed?',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon: Icons.waving_hand_rounded,
      title: 'No messages yet',
      text: 'Say hi, or fill the room with a sample conversation.',
      action: FilledButton.icon(
        onPressed: _seeding ? null : _seed,
        icon: _seeding
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_circle_outline_rounded, size: 18),
        label: const Text('Add 40 sample messages'),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CenteredMessage(
      icon: Icons.cloud_off_rounded,
      title: "Couldn't load the chat",
      text:
          'Check your connection, and make sure Cloud Firestore is enabled '
          'and the security rules from firestore.rules are published.',
      action: FilledButton(
        onPressed: () => ref.read(chatControllerProvider.notifier).reload(),
        child: const Text('Try again'),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChatColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent,
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(icon, size: 30, color: colors.onAccent),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.incomingMeta,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            action,
          ],
        ),
      ),
    );
  }
}
