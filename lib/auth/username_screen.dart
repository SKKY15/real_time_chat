import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../services/auth_service.dart';
import '../theme/chat_colors.dart';
import '../widgets/brand_mark.dart';
import 'auth_controller.dart';

/// First screen: pick a name and join. Signing in is anonymous, so a second
/// phone is in the room within seconds.
class UsernameScreen extends ConsumerStatefulWidget {
  const UsernameScreen({super.key});

  @override
  ConsumerState<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends ConsumerState<UsernameScreen> {
  final TextEditingController _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill the name of a user who is signed in but has not finished
    // joining (or wants to pick a different name).
    _name.text = ref.read(authControllerProvider)?.name ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).join(name);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AuthService.describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    const fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide.none,
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: BrandMark(size: 84)),
                  const SizedBox(height: 28),
                  Text(
                    'Join the conversation',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick a name and you are in. No account needed.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.incomingMeta,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    enabled: !_busy,
                    maxLength: AuthService.maxNameLength,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _join(),
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17),
                    decoration: InputDecoration(
                      hintText: 'Your name',
                      counterText: '',
                      errorText: _error,
                      errorMaxLines: 3,
                      filled: true,
                      fillColor: colors.incoming,
                      prefixIcon: const Icon(Icons.person_rounded),
                      border: fieldBorder,
                      enabledBorder: fieldBorder,
                      disabledBorder: fieldBorder,
                      focusedBorder: fieldBorder.copyWith(
                        borderSide: BorderSide(
                          color: scheme.primary,
                          width: 1.6,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _name,
                    builder: (context, value, _) {
                      final canJoin = value.text.trim().isNotEmpty && !_busy;
                      return FilledButton(
                        onPressed: canJoin ? _join : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                          textStyle: theme.textTheme.titleMedium,
                        ),
                        child: _busy
                            ? SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: scheme.primary,
                                ),
                              )
                            : const Text('Join chat'),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
