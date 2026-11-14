import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_controller.dart';
import '../models/chat_message.dart';
import '../theme/chat_colors.dart';
import '../widgets/message_row.dart';
import '../widgets/scroll_to_bottom_button.dart';
import 'chat_controller.dart';
import 'composer_controller.dart';
import 'message_layout.dart';
import 'message_menu.dart';

/// The scrolling message history.
///
/// A reversed [ListView.builder]: index 0 is the newest message and sits at
/// the bottom, so
///
///  * new messages appear at the bottom without any scrolling,
///  * older pages are appended at the far end and never move what is on
///    screen,
///  * the list follows the keyboard for free, because it is anchored to the
///    bottom edge.
///
/// Rows are keyed by message id and looked up through
/// `findChildIndexCallback`, which lets Flutter move existing rows (with
/// their state and layers) instead of rebuilding them when a message is
/// inserted.
class MessageList extends ConsumerStatefulWidget {
  const MessageList({super.key});

  @override
  ConsumerState<MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<MessageList>
    with WidgetsBindingObserver {
  /// Up to this distance from the newest message the list counts as being
  /// "at the bottom": it follows new messages and hides the jump button.
  static const double _pinnedExtent = 120;

  /// Older messages are requested this far before the top is reached.
  static const double _loadMoreExtent = 600;

  static const ValueKey<String> _historyKey = ValueKey<String>('__history__');

  final ScrollController _scroll = ScrollController();
  final ValueNotifier<bool> _showJumpButton = ValueNotifier<bool>(false);
  final MessageRowRegistry _registry = MessageRowRegistry();
  late final MessageRowActions _actions = MessageRowActions(
    shouldAnimateIn: _shouldAnimateIn,
    onReply: _reply,
    onOpenMenu: _openMenu,
    onQuoteTap: _showQuoted,
  );

  List<ChatMessage> _messages = const <ChatMessage>[];
  Map<String, int>? _indexById;
  String _userId = '';
  bool _isResumed = true;
  bool _wasPinned = true;
  bool _isRevealing = false;

  ChatController get _chat => ref.read(chatControllerProvider.notifier);

  bool get _isPinned =>
      !_scroll.hasClients || _scroll.position.pixels <= _pinnedExtent;

  bool get _isScrolling =>
      _scroll.hasClients && _scroll.position.isScrollingNotifier.value;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _isResumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    // The messages that are already there when the list appears never go
    // through the change listener, so handle them once after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markSeenIfReading();
      _loadMoreIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _showJumpButton.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isResumed = state == AppLifecycleState.resumed;
    if (_isResumed) _markSeenIfReading();
  }

  // ---------------------------------------------------------------- scrolling

  void _onScroll() {
    final pinned = _isPinned;
    _showJumpButton.value = !pinned;
    // While the user reads older history, incoming messages are held back
    // (and counted on the jump button) so nothing moves under their finger.
    _chat.setPinned(pinned);
    if (pinned && !_wasPinned) _markSeenIfReading();
    _wasPinned = pinned;
    _loadMoreIfNeeded();
  }

  void _loadMoreIfNeeded() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    if (position.extentAfter < _loadMoreExtent) unawaited(_chat.loadMore());
  }

  void _markSeenIfReading() {
    if (_isResumed && _isPinned) _chat.markSeen();
  }

  /// Brings the newest message into view.
  void _scrollToLatest() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels <= 0) return;
    // From far away, skip most of the distance: animating across hundreds of
    // rows would build every one of them on the way.
    final runway = position.viewportDimension * 1.5;
    if (position.pixels > runway) _scroll.jumpTo(runway);
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onMessagesChanged(List<ChatMessage>? previous, List<ChatMessage> next) {
    _markSeenIfReading();

    var follow = false;
    final newest = next.isEmpty ? null : next.first;
    final previousNewest = previous == null || previous.isEmpty
        ? null
        : previous.first;
    if (newest != null && newest.id != previousNewest?.id) {
      final justSentByMe =
          newest.senderId == _userId && !newest.hasServerTimestamp;
      // Always return to the bottom after sending. Otherwise follow the
      // conversation only when resting near the bottom: a finger on the
      // list (or a fling) keeps control.
      follow = justSentByMe || (_isPinned && !_isScrolling);
    }

    // Runs after the frame that builds the new rows, and outside of this
    // provider notification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (follow) _scrollToLatest();
      // A conversation shorter than the screen cannot be scrolled, so the
      // scroll listener alone would never ask for the next page.
      _loadMoreIfNeeded();
    });
  }

  // ------------------------------------------------------------------ actions

  bool _shouldAnimateIn(String messageId) => _chat.consumeFresh(messageId);

  void _reply(ChatMessage message) {
    ref.read(composerProvider.notifier).reply(_latest(message));
  }

  Future<void> _openMenu(
    ChatMessage message,
    Rect bubbleRect,
    Offset globalPosition,
  ) async {
    unawaited(HapticFeedback.selectionClick());
    final action = await showMessageMenu(
      context: context,
      bubbleRect: bubbleRect,
      globalPosition: globalPosition,
      message: message,
      isMine: message.senderId == _userId,
    );
    if (action == null || !mounted) return;

    // The message may have changed while the menu was open.
    final current = _latest(message);
    switch (action) {
      case MessageAction.reply:
        ref.read(composerProvider.notifier).reply(current);
      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: current.text));
        _showNotice('Message copied');
      case MessageAction.edit:
        if (current.deleted) return;
        ref.read(composerProvider.notifier).edit(current);
      case MessageAction.delete:
        unawaited(HapticFeedback.mediumImpact());
        // The input bar must not keep editing a message that is gone.
        if (ref.read(composerProvider).editing?.id == current.id) {
          ref.read(composerProvider.notifier).clear();
        }
        unawaited(_chat.delete(current).catchError(_onDeleteFailed));
      case MessageAction.retry:
        unawaited(_chat.retry(current.id));
      case MessageAction.discard:
        _chat.discard(current.id);
    }
  }

  void _onDeleteFailed(Object error) {
    _showNotice('Could not delete the message. Please try again.');
  }

  void _showNotice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  ChatMessage _latest(ChatMessage message) {
    final index = _indexOf(message.id);
    return index == null ? message : _messages[index];
  }

  // ------------------------------------------------- jump to a quoted message

  /// Scrolls to the message a reply quotes and flashes it. Loads older pages
  /// first when the original is not on the device yet.
  Future<void> _showQuoted(String messageId) async {
    if (_isRevealing) return;
    _isRevealing = true;
    unawaited(HapticFeedback.selectionClick());
    try {
      if (_indexOf(messageId) == null) {
        final loaded = await _chat.ensureLoaded(messageId);
        if (!mounted) return;
        // Give the list one frame to pick up the new page.
        if (loaded) await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      if (_indexOf(messageId) == null) {
        _showNotice('The original message is not available');
        return;
      }
      await _reveal(messageId);
    } finally {
      _isRevealing = false;
    }
  }

  Future<void> _reveal(String messageId) async {
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted || !_scroll.hasClients) return;

      final rowContext = _registry.contextOf(messageId);
      if (rowContext != null && rowContext.mounted) {
        await Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        if (mounted) _registry.flash(messageId);
        return;
      }

      // The row is outside the built range, where offsets are only estimates.
      // Step towards it by "rows to go × average row height" and look again;
      // every step is measured from rows that really exist, so this closes in
      // within a few frames.
      final index = _indexOf(messageId);
      final built = _builtRange();
      if (index == null || built == null) return;
      final (lowest, highest) = built;
      final rowsToGo = index > highest ? index - highest : index - lowest;
      final position = _scroll.position;
      final averageExtent =
          (position.maxScrollExtent + position.viewportDimension) /
          (_messages.length + 1);
      final target = (position.pixels + rowsToGo * averageExtent).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() < 1) return;
      _scroll.jumpTo(target);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Lowest and highest list index among the rows that are currently built.
  (int, int)? _builtRange() {
    int? lowest;
    int? highest;
    for (final id in _registry.builtIds) {
      final index = _indexOf(id);
      if (index == null) continue;
      lowest = lowest == null ? index : math.min(lowest, index);
      highest = highest == null ? index : math.max(highest, index);
    }
    return lowest == null || highest == null ? null : (lowest, highest);
  }

  // ------------------------------------------------------------------ building

  int? _indexOf(String messageId) {
    final index = _indexById ??= <String, int>{
      for (var i = 0; i < _messages.length; i++) _messages[i].id: i,
    };
    return index[messageId];
  }

  int? _findChildIndex(Key key) {
    if (key == _historyKey) return _messages.length;
    return key is ValueKey<String> ? _indexOf(key.value) : null;
  }

  Widget _buildItem(BuildContext context, int index) {
    final messages = _messages;
    if (index >= messages.length) return const _HistoryHeader(key: _historyKey);
    final message = messages[index];
    return MessageRow(
      key: ValueKey<String>(message.id),
      message: message,
      layout: MessageLayout.at(messages, index),
      isMine: message.senderId == _userId,
      registry: _registry,
      actions: _actions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final messagesOf = chatControllerProvider.select((state) => state.messages);
    final messages = ref.watch(messagesOf);
    ref.listen<List<ChatMessage>>(messagesOf, _onMessagesChanged);
    _userId =
        ref.watch(authControllerProvider.select((user) => user?.uid)) ?? '';
    if (!identical(messages, _messages)) {
      _messages = messages;
      _indexById = null;
    }

    final platform = Theme.of(context).platform;
    final bounces =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            // iOS bounce where it is native, clamping (with the stretch
            // overscroll effect) on Android.
            physics: bounces
                ? const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  )
                : const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            addAutomaticKeepAlives: false,
            itemCount: messages.length + 1,
            findChildIndexCallback: _findChildIndex,
            itemBuilder: _buildItem,
          ),
        ),
        Positioned(
          right: 12,
          bottom: 10,
          child: ValueListenableBuilder<bool>(
            valueListenable: _showJumpButton,
            builder: (context, visible, _) => Consumer(
              builder: (context, ref, _) {
                final unread = ref.watch(
                  chatControllerProvider.select((state) => state.unreadCount),
                );
                return ScrollToBottomButton(
                  visible: visible,
                  unreadCount: unread,
                  onPressed: _scrollToLatest,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Last entry of the list (visually the top): a spinner while an older page
/// loads, and a small marker once the beginning of the room is reached.
class _HistoryHeader extends ConsumerWidget {
  const _HistoryHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (isLoadingMore, hasMore) = ref.watch(
      chatControllerProvider.select(
        (state) => (state.isLoadingMore, state.hasMore),
      ),
    );
    if (hasMore) {
      return SizedBox(
        height: 44,
        child: Center(
          child: isLoadingMore
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
      );
    }

    final colors = ChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.forum_rounded, size: 26, color: colors.onPill),
          const SizedBox(height: 6),
          Text(
            'This is the beginning of the conversation',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onPill),
          ),
        ],
      ),
    );
  }
}
