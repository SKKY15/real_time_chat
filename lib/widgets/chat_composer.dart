import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_controller.dart';
import '../chat/chat_controller.dart';
import '../chat/composer_controller.dart';
import '../chat/typing_tracker.dart';
import '../models/app_user.dart';
import '../services/chat_repository.dart';
import '../services/providers.dart';
import '../theme/chat_colors.dart';
import '../utils/text_direction.dart';
import 'composer_banner.dart';
import 'send_button.dart';

/// The input bar: reply / edit banner, text field and send button.
///
/// Everything that changes while typing (the text, the enabled state of the
/// send button, the typing signal) is kept inside this widget, so typing
/// never rebuilds the message list.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key});

  /// Longest message that can be typed. The Firestore security rules allow
  /// more, which leaves room for characters made of several code points.
  static const int maxMessageLength = 2000;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ValueNotifier<bool> _canSend = ValueNotifier<bool>(false);

  /// Whether the draft is written right to left (Arabic, Hebrew, ...).
  final ValueNotifier<bool> _isRightToLeft = ValueNotifier<bool>(false);

  late final AnimationController _sendPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final TypingSignal _typing = TypingSignal(
    onPing: _announceTyping,
    onStop: _clearTyping,
  );

  // Captured up front: `ref` must not be used while the widget is disposed,
  // which is exactly when the typing document has to be cleared.
  late final ChatRepository _repository;
  AppUser? _user;

  String _lastText = '';
  String _draftBeforeEdit = '';

  @override
  void initState() {
    super.initState();
    _repository = ref.read(chatRepositoryProvider);
    _text.addListener(_onTextChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typing.dispose();
    _sendPulse.dispose();
    _text.dispose();
    _focus.dispose();
    _canSend.dispose();
    _isRightToLeft.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nobody should see "typing…" for an app that is in the background.
    if (state != AppLifecycleState.resumed) _typing.stop();
  }

  void _onTextChanged() {
    final text = _text.text;
    if (text == _lastText) return; // selection or composing change only
    _lastText = text;
    _canSend.value = text.trim().isNotEmpty;
    _isRightToLeft.value = isRightToLeft(text);
    if (ref.read(composerProvider).isEditing) {
      _typing.stop();
    } else {
      _typing.input(text);
    }
  }

  void _announceTyping() {
    final user = _user;
    if (user == null) return;
    unawaited(_repository.setTyping(user).catchError(_ignore));
  }

  void _clearTyping() {
    final user = _user;
    if (user == null) return;
    unawaited(_repository.clearTyping(user.uid).catchError(_ignore));
  }

  /// The typing indicator is best effort: failures are not worth surfacing.
  static void _ignore(Object error) {}

  void _onComposerChanged(ComposerState? previous, ComposerState next) {
    final editing = next.editing;
    final wasEditing = previous?.editing;
    if (editing != null && editing.id != wasEditing?.id) {
      // Entering edit mode: park the draft and load the message text.
      if (wasEditing == null) _draftBeforeEdit = _text.text;
      _text.value = TextEditingValue(
        text: editing.text,
        selection: TextSelection.collapsed(offset: editing.text.length),
      );
      _focus.requestFocus();
    } else if (editing == null && wasEditing != null) {
      // Leaving edit mode (saved or cancelled): bring the draft back.
      _text.value = TextEditingValue(
        text: _draftBeforeEdit,
        selection: TextSelection.collapsed(offset: _draftBeforeEdit.length),
      );
      _draftBeforeEdit = '';
    }
    if (next.replyTo != null && next.replyTo?.id != previous?.replyTo?.id) {
      _focus.requestFocus();
    }
  }

  void _submit() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final composer = ref.read(composerProvider);
    final chat = ref.read(chatControllerProvider.notifier);
    final editing = composer.editing;

    HapticFeedback.lightImpact();
    _sendPulse.forward(from: 0);
    _typing.stop();

    if (editing != null) {
      unawaited(chat.edit(editing, text).catchError(_onEditFailed));
      ref.read(composerProvider.notifier).clear();
    } else {
      unawaited(chat.send(text, replyTo: composer.replyTo));
      _text.clear();
      ref.read(composerProvider.notifier).clear();
    }
  }

  void _cancelBanner() => ref.read(composerProvider.notifier).clear();

  void _onEditFailed(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not save the edit. Please try again.'),
      ),
    );
  }

  ComposerBannerData? _bannerFor(ComposerState composer) {
    final editing = composer.editing;
    if (editing != null) {
      return ComposerBannerData(
        icon: Icons.edit_rounded,
        title: 'Edit message',
        text: editing.text,
      );
    }
    final replyTo = composer.replyTo;
    if (replyTo != null) {
      final isMine = replyTo.senderId == _user?.uid;
      return ComposerBannerData(
        icon: Icons.reply_rounded,
        title: isMine ? 'Reply to yourself' : 'Reply to ${replyTo.senderName}',
        text: replyTo.text.replaceAll('\n', ' '),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    _user = ref.watch(authControllerProvider);
    final composer = ref.watch(composerProvider);
    ref.listen<ComposerState>(composerProvider, _onComposerChanged);

    final theme = Theme.of(context);
    final colors = ChatColors.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ComposerBanner(data: _bannerFor(composer), onClose: _cancelBanner),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.inputFill,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(22),
                        ),
                      ),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isRightToLeft,
                        builder: (context, rightToLeft, _) => TextField(
                          controller: _text,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textCapitalization: TextCapitalization.sentences,
                          textDirection: rightToLeft ? TextDirection.rtl : null,
                          inputFormatters: <TextInputFormatter>[
                            LengthLimitingTextInputFormatter(
                              ChatComposer.maxMessageLength,
                            ),
                          ],
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 15.5,
                            height: 1.3,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Message',
                            hintStyle: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 15.5,
                              height: 1.3,
                              color: colors.incomingMeta,
                            ),
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: _canSend,
                    builder: (context, canSend, _) => SendButton(
                      enabled: canSend,
                      isEditing: composer.isEditing,
                      pulse: _sendPulse,
                      onPressed: _submit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
