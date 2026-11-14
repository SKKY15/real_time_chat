import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../chat/chat_screen.dart';
import 'auth_controller.dart';
import 'username_screen.dart';

/// Shows the username prompt until the user has joined, then the chat.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasJoined = ref.watch(
      authControllerProvider.select((user) => user != null && user.hasName),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: hasJoined
          ? const ChatScreen(key: ValueKey<String>('chat'))
          : const UsernameScreen(key: ValueKey<String>('join')),
    );
  }
}
