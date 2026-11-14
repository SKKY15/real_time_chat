import 'dart:async';

import '../services/chat_repository.dart';
import 'message_store.dart';

/// Keeps a [MessageStore] in sync with the room.
///
/// Loading strategy:
///
///  1. **Latest window** – a live query on the newest [pageSize] messages
///     (`limit(30)`). It answers from the local cache first, so the list is
///     on screen instantly.
///  2. **Anchor** – once the server has confirmed that window, it is swapped
///     for a live query bounded by its oldest message instead of by a limit.
///     New messages then extend the query instead of pushing older ones out,
///     so everything that is loaded keeps receiving edits, deletes and read
///     receipts.
///  3. **Older pages** – every "load more" attaches one live query for the
///     next [pageSize] older messages. Messages are only ever soft-deleted and
///     `createdAt` never changes, so those windows are stable.
///
/// Plain Dart: no Flutter, Riverpod or Firebase imports.
class MessageFeed {
  MessageFeed({
    required this._repository,
    required this.store,
    required this.onChanged,
    this.onError,
    this.pageSize = 30,
  });

  final ChatRepository _repository;
  final MessageStore store;
  final int pageSize;

  /// Called whenever [store] or one of the flags below changed.
  final void Function() onChanged;

  /// Called for errors that do not stop the feed (for example a failed page).
  final void Function(Object error, StackTrace stackTrace)? onError;

  StreamSubscription<MessageBatch>? _latestSub;
  StreamSubscription<MessageBatch>? _anchoredSub;
  final List<StreamSubscription<MessageBatch>> _pageSubs =
      <StreamSubscription<MessageBatch>>[];

  Object? _headCursor;
  Object? _pageCursor;
  Completer<void>? _pageLoad;

  bool _disposed = false;
  bool _anchored = false;
  bool _watchesWholeRoom = false;
  bool _isLoading = true;
  bool _hasMore = true;
  Object? _error;

  /// `true` until the first snapshot (cached or not) has arrived.
  bool get isLoading => _isLoading;

  /// `true` while an older page is being fetched.
  bool get isLoadingMore => _pageLoad != null;

  /// Whether older messages may exist beyond what is loaded.
  bool get hasMore => _hasMore;

  /// Error of the main query, if it failed (for example missing permissions).
  Object? get error => _error;

  /// Whether the live query covers the entire room. If it does, even
  /// messages written with a timestamp in the past arrive on their own.
  bool get watchesWholeRoom => _watchesWholeRoom;

  /// Starts listening. Safe to call again after an error to retry.
  void start() {
    if (_disposed) return;
    _cancelAll();
    _anchored = false;
    _watchesWholeRoom = false;
    _isLoading = true;
    _error = null;
    _latestSub = _repository
        .watchLatest(pageSize)
        .listen(_onLatest, onError: _onFatalError);
  }

  void dispose() {
    _disposed = true;
    _cancelAll();
  }

  /// Loads the next page of older messages. Completes when the page has
  /// arrived (or failed); concurrent calls share the same request.
  Future<void> loadMore() {
    final running = _pageLoad;
    if (running != null) return running.future;
    final cursor = _pageCursor;
    if (_disposed || !_hasMore || cursor == null) return Future<void>.value();

    final completer = Completer<void>();
    _pageLoad = completer;
    onChanged();

    void settle() {
      if (identical(_pageLoad, completer)) _pageLoad = null;
      if (!completer.isCompleted) completer.complete();
    }

    late final StreamSubscription<MessageBatch> sub;
    sub = _repository
        .watchOlder(cursor, pageSize)
        .listen(
          (batch) {
            store
              ..upsert(batch.messages)
              ..remove(batch.removedIds);
            final isFull = batch.messages.length >= pageSize;
            // A short page read from the cache says nothing about the
            // server, so keep waiting for the confirmed result.
            if (!completer.isCompleted && (isFull || !batch.isFromCache)) {
              _pageCursor = batch.oldestCursor ?? cursor;
              _hasMore = isFull;
              settle();
            }
            onChanged();
          },
          onError: (Object error, StackTrace stackTrace) {
            _pageSubs.remove(sub);
            unawaited(sub.cancel());
            settle();
            onError?.call(error, stackTrace);
            onChanged();
          },
        );
    _pageSubs.add(sub);
    return completer.future;
  }

  /// Loads older pages until [messageId] is available. Returns whether the
  /// message is loaded afterwards.
  Future<bool> ensureLoaded(
    String messageId, {
    int maxPages = 10,
    Duration pageTimeout = const Duration(seconds: 8),
  }) async {
    for (var page = 0; page < maxPages; page++) {
      if (store.contains(messageId)) return true;
      if (_disposed || !_hasMore || _pageCursor == null) return false;
      var timedOut = false;
      await loadMore().timeout(
        pageTimeout,
        onTimeout: () {
          timedOut = true;
        },
      );
      if (timedOut) break;
    }
    return store.contains(messageId);
  }

  void _onLatest(MessageBatch batch) {
    if (_disposed) return;
    final hadMessages = store.hasRemoteMessages;

    if (batch.isFromCache) {
      // Cached (or offline) result: show it and keep everything that scrolls
      // out of the window, it is still part of the contiguous history.
      store.upsert(batch.messages);
      _removeGone(batch, confirmed: false);
      if (!_anchored) {
        _headCursor ??= batch.oldestCursor;
        _pageCursor ??= batch.oldestCursor;
      }
    } else if (!_anchored) {
      // First answer confirmed by the server.
      final overlapsCache = batch.messages.any(
        (message) => !message.hasPendingWrites && store.hasRemote(message.id),
      );
      if (hadMessages && !overlapsCache) {
        // The cached history is too old to connect to the newest messages.
        // Showing both would leave a hole in between, so start over.
        _cancelPages();
        store.resetRemote(batch.messages);
        _headCursor = batch.oldestCursor;
        _pageCursor = batch.oldestCursor;
        _hasMore = batch.messages.length >= pageSize;
      } else {
        store.upsert(batch.messages);
        _removeGone(batch, confirmed: true);
        _headCursor ??= batch.oldestCursor;
        _pageCursor ??= batch.oldestCursor;
        if (!hadMessages) _hasMore = batch.messages.length >= pageSize;
      }
      _anchor();
    } else {
      // Anchored already; the bounded query is about to take over.
      store.upsert(batch.messages, announce: true);
      _removeGone(batch, confirmed: true);
    }

    _isLoading = false;
    onChanged();
  }

  /// Handles ids that left the sliding "latest" window.
  ///
  /// Most of them were merely pushed out by newer messages and must stay. Two
  /// kinds are really gone: local writes the server rejected (they never got
  /// a server timestamp) and, once the server has confirmed the window,
  /// messages that are newer than its oldest entry and still missing.
  void _removeGone(MessageBatch batch, {required bool confirmed}) {
    if (batch.removedIds.isEmpty) return;
    final oldest = batch.messages.isEmpty ? null : batch.messages.last;
    final gone = <String>[];
    for (final id in batch.removedIds) {
      final message = store[id];
      if (message == null) continue;
      if (!message.hasServerTimestamp) {
        gone.add(id);
      } else if (confirmed &&
          oldest != null &&
          oldest.hasServerTimestamp &&
          message.createdAt.isAfter(oldest.createdAt)) {
        gone.add(id);
      }
    }
    store.remove(gone);
  }

  /// Replaces the sliding `limit` window with a query that is bounded by the
  /// oldest message of the head, so loaded messages never fall out of it.
  ///
  /// When the server has confirmed that nothing older exists, the bound is
  /// dropped and the whole (small) room is watched.
  void _anchor() {
    _anchored = true;
    _watchesWholeRoom = !_hasMore || _headCursor == null;
    final cursor = _watchesWholeRoom ? null : _headCursor;
    var first = true;
    _anchoredSub = _repository.watchSince(cursor).listen((batch) {
      if (_disposed) return;
      if (first) {
        first = false;
        unawaited(_latestSub?.cancel());
        _latestSub = null;
      }
      store
        ..upsert(batch.messages, announce: true)
        ..remove(batch.removedIds);
      onChanged();
    }, onError: _onFatalError);
  }

  void _onFatalError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    _error = error;
    _isLoading = false;
    onChanged();
  }

  void _cancelPages() {
    for (final sub in _pageSubs) {
      unawaited(sub.cancel());
    }
    _pageSubs.clear();
    final running = _pageLoad;
    _pageLoad = null;
    if (running != null && !running.isCompleted) running.complete();
  }

  void _cancelAll() {
    unawaited(_latestSub?.cancel());
    unawaited(_anchoredSub?.cancel());
    _latestSub = null;
    _anchoredSub = null;
    _cancelPages();
  }
}
