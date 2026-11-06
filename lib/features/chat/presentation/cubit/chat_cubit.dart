import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/isolated_side_effect.dart';
import '../../../entries/domain/entities/entry.dart';
import '../../../entries/domain/usecases/save_chat_message_as_entry_use_case.dart';
import '../../domain/entities/bookmark_state.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_session.dart';
import '../../domain/entities/chat_stream_event.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/services/connectivity_watcher.dart';
import 'chat_state.dart';

/// Drives `ChatScreen` — a DI `lazySingleton` (Code Map, mirroring
/// `MeusRegistrosCubit`): long-lived, so returning to Home/Chat within the
/// same app session never re-bootstraps the session/history it already
/// loaded (`init()`'s own no-op guard below).
class ChatCubit extends Cubit<ChatState> {
  ChatCubit(
    this._repository,
    this._connectivityWatcher,
    this._saveChatMessageAsEntryUseCase,
  ) : super(const ChatBootstrapLoading()) {
    // spec-6-3 — subscribes immediately (not gated on bootstrap), so the
    // very first connectivity read is never missed while a slow
    // `init()` is still in flight; `_handleConnectivityChange` itself is
    // a no-op against anything but `ChatReady` until bootstrap resolves,
    // `_isOffline` still being tracked below so a later `ChatReady`
    // (bootstrap, `switchSession`, `startNewSession`) picks up whatever
    // the device's status already was.
    _connectivitySubscription = _connectivityWatcher.watch().listen(
      _handleConnectivityChange,
      onError: (Object _, StackTrace _) {
        // RNF09: a connectivity-watch error (e.g. the platform channel
        // being unavailable — no device/simulator exists yet, AGENTS.md)
        // must never escape the cubit; `_isOffline` simply keeps
        // whatever value it last had (`false` if this is the very first
        // read) instead of crashing.
      },
    );
  }

  final ChatRepository _repository;
  final ConnectivityWatcher _connectivityWatcher;

  /// spec-6-4 (RF10) — the shared use case AGENTS.md's RF10 rule requires;
  /// never `EntriesRepository`, never anything under `entries/data/`/
  /// `entries/presentation/` (Boundaries).
  final SaveChatMessageAsEntryUseCase _saveChatMessageAsEntryUseCase;

  StreamSubscription<bool>? _connectivitySubscription;

  StreamSubscription<Either<Failure, ChatStreamEvent>>? _sendSubscription;

  /// The in-flight [sendMessage]/[retryMessage]'s own completer, if any —
  /// [close] must complete it itself, since cancelling [_sendSubscription]
  /// alone never fires `onDone`/`onError` (review fix: `cancel()` alone
  /// left `sendMessage()`'s returned `Future` permanently unresolved when
  /// the cubit closed mid-send).
  Completer<void>? _sendCompleter;

  /// Monotonic counter behind every locally generated [ChatUiMessage.id]
  /// (Code Map) — never the server's own message id (see `ChatStreamEvent`'s
  /// own doc on why `message_created`'s id goes unused here).
  int _localIdCounter = 0;

  /// Whether a send/retry is actively in flight right now — tracked
  /// locally rather than by scanning [ChatState.messages] for a persisted
  /// `streaming` status, since a message loaded from history/cache can
  /// legitimately carry that same status (e.g. one left over from an
  /// earlier dropped response, the I/O matrix's own scenario) without a
  /// send actually being in progress; scanning for it would permanently
  /// disable the composer in that case. [retryMessage] reuses this exact
  /// guard verbatim (Boundaries: "a second retry while one is in flight —
  /// reuses `_isSending` verbatim"), so a retry and a send can never race
  /// each other either.
  bool _isSending = false;

  /// An in-flight bootstrap, if any — reused by a concurrent `init()` call
  /// instead of starting a second bootstrap, so two near-simultaneous
  /// callers (e.g. two mounts before the first resolves) never both
  /// observe "no sessions" and both call `createSession()` (Boundaries:
  /// "silently ensure *one* Chat Session exists").
  Future<void>? _initFuture;

  /// spec-6-3 — the device's last known online/offline status, as
  /// reported by [_connectivityWatcher], `true` meaning offline. Tracked
  /// independently of [ChatState] (unlike `_isSending`'s own UI-facing
  /// twin, [ChatReady.isOffline]) so a status learned before bootstrap
  /// resolves — or while the active session is being switched, neither of
  /// which touches this field — is never lost; every place that emits a
  /// fresh [ChatReady] (`_bootstrap`, [switchSession], [startNewSession])
  /// carries it forward explicitly.
  bool _isOffline = false;

  /// Boundaries: "Scroll-offset restore is in-memory only, keyed by
  /// `sessionId`, on `ChatCubit` (never Hive) — survives session switches
  /// within one app run, resets on restart." Lives on this long-lived
  /// `lazySingleton` cubit itself (Design Notes), never on [ChatReady] —
  /// a state value would otherwise have to be threaded through every
  /// unrelated `copyWith` call just to avoid losing it.
  final Map<String, double> _scrollOffsets = {};

  /// Boundaries: "On opening Home/Chat, silently ensure one Chat Session
  /// exists (reuse the most recent from `chat-sessions-list`, else
  /// `chat-sessions-create` with no title)". A no-op once already
  /// [ChatReady] — `ChatScreen.initState()` calls this unconditionally on
  /// every mount, but a `lazySingleton` cubit may already be bootstrapped
  /// from an earlier visit.
  Future<void> init() {
    if (state is ChatReady || isClosed) {
      return Future.value();
    }
    return _initFuture ??= _bootstrap().whenComplete(() => _initFuture = null);
  }

  Future<void> _bootstrap() async {
    emit(const ChatBootstrapLoading());

    final sessionsResult = await _repository.listSessions();
    if (isClosed) {
      return;
    }
    // Captured by the closures below so the resulting [ChatReady] can
    // carry every known session (Code Map: "capture resolved sessions
    // into the emitted ChatReady"), not just the one picked to reuse.
    List<ChatSession> sessions = const [];
    final Either<Failure, ChatSession> sessionResult = await sessionsResult
        .match((failure) async => left(failure), (fetchedSessions) async {
          if (fetchedSessions.isEmpty) {
            final createResult = await _repository.createSession();
            return createResult.match((failure) => left(failure), (session) {
              sessions = [session];
              return right(session);
            });
          }
          sessions = fetchedSessions;
          // "reuse the most recent" — defensively re-sorts rather than
          // trusting `listSessions()`'s own ordering (its offline-cache
          // fallback already sorts `updatedAt` desc, but the live
          // server response's own ordering isn't documented either
          // way). `tryParse` (never `parse`) — same crash-safe pattern as
          // `AppDrawer`'s own session sort (review finding "Crash risk in
          // the new `_ConversasSection` sort"): a malformed `updatedAt`
          // must never crash bootstrap itself, so it falls back to the
          // epoch and simply sorts last instead of throwing.
          final mostRecent = [...fetchedSessions]
            ..sort(
              (a, b) => (DateTime.tryParse(b.updatedAt) ?? DateTime(0))
                  .compareTo(DateTime.tryParse(a.updatedAt) ?? DateTime(0)),
            );
          return right(mostRecent.first);
        });
    if (isClosed) {
      return;
    }

    await sessionResult.match(
      (failure) async {
        if (!isClosed) {
          emit(ChatBootstrapError(failure));
        }
      },
      (session) async {
        final messagesResult = await _repository.listMessages(session.id);
        if (isClosed) {
          return;
        }
        messagesResult.match(
          (failure) => emit(ChatBootstrapError(failure)),
          (messages) => emit(
            ChatReady(
              sessionId: session.id,
              messages: messages.map(_fromDomain).toList(),
              sessions: sessions,
              isOffline: _isOffline,
            ),
          ),
        );
      },
    );
  }

  /// Boundaries: "Scroll-offset restore is in-memory only, keyed by
  /// `sessionId`" — `ChatScreen`'s own `ScrollController` listener calls
  /// this on every scroll update, so whichever offset a session was last
  /// left at is always the one [switchSession] hands back when that
  /// session becomes active again.
  void recordScrollOffset(String sessionId, double offset) {
    _scrollOffsets[sessionId] = offset;
  }

  /// I/O matrix: "Switch session"/"Switch to already-active session" —
  /// a no-op [Right] when [sessionId] is already [ChatReady.sessionId]
  /// (the drawer still closes, nothing reloads/re-fetches); otherwise
  /// fetches that session's own history via `listMessages` (reused as-is,
  /// Code Map) and makes it active, handing [ChatReady.restoreScrollOffset]
  /// whatever [recordScrollOffset] last captured for it (`null` if this
  /// session was never scrolled in this app run — `ChatScreen`'s own cue
  /// to jump to the bottom instead). A no-op while bootstrap hasn't
  /// resolved yet, same guard shape as [sendMessage].
  Future<Either<Failure, Unit>> switchSession(String sessionId) async {
    final current = state;
    if (current is! ChatReady) {
      return right(unit);
    }
    if (sessionId == current.sessionId) {
      return right(unit);
    }
    // Review finding: "Cross-session stream leakage" — an AI response
    // still streaming into the *old* session must never be left running
    // once we switch away from it; its orphaned subscription's
    // `onData`/`onDone` would otherwise go on to mutate whichever session
    // becomes active next.
    await _cancelInFlightSend();
    final messagesResult = await _repository.listMessages(sessionId);
    if (isClosed) {
      return right(unit);
    }
    return messagesResult.match(
      (failure) {
        // Review fix: `_cancelInFlightSend()` above only resets the
        // internal `_isSending` guard, not the `ChatReady.isSending` the
        // composer gates on (`canSend = ... && !state.isSending`) — on a
        // failed switch we're staying on `current`, so its stale
        // `isSending: true` must be flipped back here or the composer
        // would stay disabled for the rest of the app run.
        if (!isClosed && current.isSending) {
          emit(current.copyWith(isSending: false));
        }
        return left(failure);
      },
      (messages) {
        if (!isClosed) {
          emit(
            ChatReady(
              sessionId: sessionId,
              messages: messages.map(_fromDomain).toList(),
              sessions: current.sessions,
              restoreScrollOffset: _scrollOffsets[sessionId],
              isOffline: _isOffline,
            ),
          );
        }
        return right(unit);
      },
    );
  }

  /// I/O matrix: "New session online"/"New session offline" — calls
  /// `createSession()` (reused as-is, Code Map; already blocked offline
  /// at the repository level, Boundaries). On any [Left] (including
  /// [Failure.networkOffline]), the current session is left completely
  /// untouched — no state is emitted at all, only the [Failure] is handed
  /// back for `AppDrawer` to surface as a transient `SnackBar`
  /// (Boundaries). On success, the new session opens empty and becomes
  /// active, prepended to [ChatReady.sessions].
  Future<Either<Failure, Unit>> startNewSession() async {
    final current = state;
    if (current is! ChatReady) {
      return right(unit);
    }
    // Review finding: "Cross-session stream leakage" — same rationale as
    // [switchSession]'s own cancellation above; a brand new session is
    // never the same session as [current], so this always needs to run
    // (unlike [switchSession], there's no same-session no-op branch to
    // skip it for).
    await _cancelInFlightSend();
    final result = await _repository.createSession();
    if (isClosed) {
      return right(unit);
    }
    return result.match(
      (failure) {
        // Review fix: same stuck-`isSending` risk as [switchSession] — a
        // failed `createSession()` leaves `current` active, so its stale
        // `isSending: true` (left behind by `_cancelInFlightSend()`
        // above, which never emits) must be flipped back here.
        if (!isClosed && current.isSending) {
          emit(current.copyWith(isSending: false));
        }
        return left(failure);
      },
      (session) {
        if (!isClosed) {
          emit(
            ChatReady(
              sessionId: session.id,
              messages: const [],
              sessions: [session, ...current.sessions],
              isOffline: _isOffline,
            ),
          );
        }
        return right(unit);
      },
    );
  }

  ChatUiMessage _fromDomain(ChatMessage message) => ChatUiMessage(
    id: message.id,
    role: message.role,
    content: message.content,
    status: message.status,
    // spec-6-3 — every message reloaded from `chat-messages-list`/the
    // offline cache already has a persisted server id (unlike a message
    // created locally mid-session, which only gains one once/if
    // `message_created` arrives, Design Notes); [retryMessage] reads this
    // off the *user* message immediately preceding a `failed` AI bubble.
    serverId: message.id,
    createdAt: message.createdAt,
  );

  /// Boundaries: optimistic user bubble, then subscribes to
  /// `ChatRepository.sendMessage`'s own stream, appending tokens as they
  /// arrive and finalizing/failing the AI bubble on `done`/any `Left` —
  /// the bubble's own [ChatUiMessage.content] is never cleared on failure
  /// (I/O matrix), only its [ChatUiMessage.status] changes.
  ///
  /// A no-op while [state] isn't [ChatReady] (bootstrap still in flight
  /// or failed — the composer is disabled in that case anyway), while
  /// [content] is blank once trimmed, while [_isSending] is already
  /// true — this story never races two concurrent sends against the one
  /// in-memory session — or while [ChatReady.isOffline] (review finding:
  /// the offline lock was UI-only via `_ChatComposer.canSend`, but nothing
  /// stopped a direct `sendMessage` caller from firing a real network call
  /// while the offline banner's own "novas mensagens bloqueadas" copy says
  /// otherwise). Deliberately not keyed off any loaded message's
  /// persisted `streaming` status — a message restored from history/cache
  /// can legitimately carry that status without a send actually being in
  /// flight (I/O matrix: mid-stream drop).
  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final current = state;
    if (current is! ChatReady) {
      return;
    }
    if (_isSending || current.isOffline) {
      return;
    }
    _isSending = true;

    final userMessage = ChatUiMessage(
      id: _nextLocalId(),
      role: ChatMessageRole.user,
      content: trimmed,
      status: ChatMessageStatus.complete,
    );
    final aiMessage = ChatUiMessage(
      id: _nextLocalId(),
      role: ChatMessageRole.assistant,
      content: '',
      status: ChatMessageStatus.streaming,
    );
    emit(
      current.copyWith(
        messages: [...current.messages, userMessage, aiMessage],
        isSending: true,
      ),
    );

    await _consumeStream(
      _repository.sendMessage(current.sessionId, trimmed),
      userMessageId: userMessage.id,
      aiMessageId: aiMessage.id,
    );
  }

  /// spec-6-3 — Boundaries: "Retry resets the *same* bubble (id,
  /// position) to `streaming`/empty, then reuses `_applyStreamEvent`/
  /// `_markFailed` unchanged — never a second bubble, never a duplicate
  /// question." [aiMessageId] must identify an existing `failed` AI
  /// bubble; anything else (not found, not `failed`, no preceding user
  /// message — shouldn't structurally happen) is a silent no-op, same
  /// defensive shape [sendMessage]'s own guards use.
  ///
  /// Keyed by the preceding user message's [ChatUiMessage.serverId]
  /// (Boundaries: "keyed by the user message's persisted id") — calls
  /// `ChatRepository.retryMessage` when it's known, or falls back to a
  /// full [ChatRepository.sendMessage] resend of that same user content
  /// into this exact AI bubble slot when it's `null` (I/O matrix: "Tap
  /// retry, no `serverId`" — the stream dropped before `message_created`
  /// ever arrived, so the backend never actually persisted the question;
  /// Boundaries: "Never calling `chat-messages-retry` with no `serverId`").
  /// Reuses [_isSending] verbatim (Boundaries: "A second retry while one
  /// is in flight"), so this is a no-op while a send/retry is already in
  /// flight — and, like [sendMessage] (review finding), a no-op while
  /// [ChatReady.isOffline] too: a failed bubble's retry tap is a separate
  /// affordance from the composer, not covered by `_ChatComposer.canSend`
  /// alone, so it needs this exact same guard to honor the offline banner.
  Future<void> retryMessage(String aiMessageId) async {
    final current = state;
    if (current is! ChatReady) {
      return;
    }
    if (_isSending || current.isOffline) {
      return;
    }
    final messages = current.messages;
    final aiIndex = messages.indexWhere((message) => message.id == aiMessageId);
    // Review finding: defensively checks `role` too, even though only an
    // assistant message ever reaches `failed` status today — matches this
    // guard clause's own already-defensive shape (`aiIndex == -1`, a
    // not-found/structurally-impossible case).
    if (aiIndex == -1 ||
        messages[aiIndex].role != ChatMessageRole.assistant ||
        messages[aiIndex].status != ChatMessageStatus.failed) {
      return;
    }
    ChatUiMessage? userMessage;
    for (var i = aiIndex - 1; i >= 0; i--) {
      if (messages[i].role == ChatMessageRole.user) {
        userMessage = messages[i];
        break;
      }
    }
    if (userMessage == null) {
      return;
    }

    _isSending = true;
    emit(
      current.copyWith(
        messages: [
          for (final message in current.messages)
            if (message.id == aiMessageId)
              message.copyWith(content: '', status: ChatMessageStatus.streaming)
            else
              message,
        ],
        isSending: true,
      ),
    );

    final serverId = userMessage.serverId;
    final stream = serverId == null
        ? _repository.sendMessage(current.sessionId, userMessage.content)
        : _repository.retryMessage(current.sessionId, serverId);
    await _consumeStream(
      stream,
      userMessageId: userMessage.id,
      aiMessageId: aiMessageId,
    );
  }

  /// Shared by [sendMessage]/[retryMessage] (Code Map: "extract shared ...
  /// helper" extends to this subscribe-and-wait shape too, not just
  /// `ChatRemoteDataSource`'s own SSE buffering) — subscribes to [stream],
  /// routing every emission through [_applyStreamEvent]/[_markFailed], and
  /// resolves once the stream ends (`done`, an in-band error, or a
  /// stream-level error), clearing [_isSending]/[ChatReady.isSending]
  /// either way via [_finishSending].
  Future<void> _consumeStream(
    Stream<Either<Failure, ChatStreamEvent>> stream, {
    required String userMessageId,
    required String aiMessageId,
  }) async {
    await _sendSubscription?.cancel();
    final completer = Completer<void>();
    _sendCompleter = completer;
    _sendSubscription = stream.listen(
      (event) {
        event.match(
          (failure) => _markFailed(aiMessageId),
          (streamEvent) =>
              _applyStreamEvent(userMessageId, aiMessageId, streamEvent),
        );
      },
      onError: (Object _, StackTrace _) {
        // RNF09: no exception escapes the cubit — a stream-level error
        // (shouldn't happen, `ChatRemoteDataSource` never lets one through
        // unmapped) still only fails the bubble, never crashes.
        _markFailed(aiMessageId);
        _finishSending();
        if (!completer.isCompleted) {
          completer.complete();
        }
        // Review finding: a stale, already-done subscription reference
        // left on `_sendSubscription` made a *later* send/retry's own
        // `await _sendSubscription?.cancel()` above hang indefinitely in
        // practice (observed via a widget test driving two sends back to
        // back) — cleared here (and in the `onDone` branch below)
        // exactly where this stream's own lifecycle actually ends,
        // rather than relying on cancelling an already-finished
        // subscription being an instant no-op.
        _sendSubscription = null;
        _sendCompleter = null;
      },
      onDone: () {
        _finishSending();
        if (!completer.isCompleted) {
          completer.complete();
        }
        _sendSubscription = null;
        _sendCompleter = null;
      },
      cancelOnError: false,
    );
    await completer.future;
  }

  /// Clears both the internal re-entrancy guard and the UI-facing
  /// [ChatReady.isSending] signal once a send's stream has ended (`done`,
  /// an in-band error, or a stream-level error) — the single place both
  /// flip back together.
  void _finishSending() {
    _isSending = false;
    if (isClosed) {
      return;
    }
    final current = state;
    if (current is ChatReady) {
      emit(current.copyWith(isSending: false));
    }
  }

  void _applyStreamEvent(
    String userMessageId,
    String aiMessageId,
    ChatStreamEvent event,
  ) {
    if (isClosed) {
      return;
    }
    final current = state;
    if (current is! ChatReady) {
      return;
    }
    switch (event) {
      case ChatMessageCreatedEvent(userMessageId: final serverId):
        // spec-6-3 — Design Notes: "the persisted *user*-message id" is
        // now this story's first consumer, captured onto the matching
        // local user bubble by id so a later `retryMessage` call (on the
        // AI bubble this same send produces) has a non-null `serverId` to
        // key `chat-messages-retry` off of.
        emit(
          current.copyWith(
            messages: [
              for (final message in current.messages)
                if (message.id == userMessageId)
                  message.copyWith(serverId: serverId)
                else
                  message,
            ],
          ),
        );
      case ChatTokenEvent(delta: final delta):
        emit(
          current.copyWith(
            messages: [
              for (final message in current.messages)
                if (message.id == aiMessageId)
                  message.copyWith(content: message.content + delta)
                else
                  message,
            ],
          ),
        );
      case ChatDoneEvent():
        emit(
          current.copyWith(
            messages: [
              for (final message in current.messages)
                if (message.id == aiMessageId)
                  message.copyWith(status: ChatMessageStatus.complete)
                else
                  message,
            ],
          ),
        );
    }
  }

  /// I/O matrix: "Mid-stream drop"/"In-band `error` event" — marks the one
  /// bubble `failed`, by id, leaving its already-streamed-in text exactly
  /// as-is (never cleared, Boundaries).
  void _markFailed(String aiMessageId) {
    if (isClosed) {
      return;
    }
    final current = state;
    if (current is! ChatReady) {
      return;
    }
    emit(
      current.copyWith(
        messages: [
          for (final message in current.messages)
            if (message.id == aiMessageId)
              message.copyWith(status: ChatMessageStatus.failed)
            else
              message,
        ],
      ),
    );
  }

  /// spec-6-4 (RF10) — Boundaries: the bookmark affordance exists only on
  /// [ChatMessageRole.user] bubbles; tapping it turns that exact message
  /// into a journal Entry (`source: EntrySource.chat`) through
  /// [_saveChatMessageAsEntryUseCase] only — never `EntriesRepository`
  /// directly (AGENTS.md's RF10 rule). A no-op (I/O & Edge-Case Matrix)
  /// when: [state] isn't [ChatReady]; [messageId] isn't found; its role
  /// isn't [ChatMessageRole.user]; its [ChatUiMessage.serverId] is still
  /// `null` (mirrors [retryMessage]'s own guard — the backend id a save
  /// sends as `chatMessageId`, Boundaries); its [ChatUiMessage.
  /// bookmarkState] is already [BookmarkSaved] (client-side no-op — a
  /// repeat save is itself idempotent at the backend, Boundaries) or
  /// already [BookmarkSaving] (re-entrancy guard, scoped to this one
  /// message — [_isSending] stays scoped to send/retry only, never shared
  /// with this guard).
  Future<void> bookmarkMessage(String messageId) async {
    final current = state;
    if (current is! ChatReady) {
      return;
    }
    final index = current.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index == -1) {
      return;
    }
    final message = current.messages[index];
    final serverId = message.serverId;
    if (message.role != ChatMessageRole.user ||
        serverId == null ||
        message.bookmarkState is BookmarkSaved ||
        message.bookmarkState is BookmarkSaving) {
      return;
    }

    // Boundaries: both of this method's own emit() calls check isClosed
    // first — not just the one after the await below.
    if (isClosed) {
      return;
    }
    emit(
      current.copyWith(
        messages: [
          for (final existing in current.messages)
            if (existing.id == messageId)
              existing.copyWith(bookmarkState: const BookmarkState.saving())
            else
              existing,
        ],
      ),
    );

    final sideEffectResult = await isolatedSideEffect(
      () => _saveChatMessageAsEntry(
        content: message.content,
        chatMessageId: serverId,
      ),
    );
    // Flattens isolatedSideEffect's own outer Either (Left only on a
    // thrown exception, mapped to malformedResponse — I/O matrix: "Side-
    // effect throws") with the use case's own inner Either (Left on a
    // normal, non-thrown save failure — I/O matrix: "Save fails") into
    // one plain Either<Failure, Entry>, so both scenarios flip the bubble
    // to the same retryable error state via the one match() below.
    final result = sideEffectResult.match(
      (failure) => left(failure),
      (inner) => inner,
    );

    if (isClosed) {
      return;
    }
    final latest = state;
    if (latest is! ChatReady) {
      return;
    }
    emit(
      latest.copyWith(
        messages: [
          for (final existing in latest.messages)
            if (existing.id == messageId)
              existing.copyWith(
                bookmarkState: result.match(
                  (failure) => BookmarkState.error(failure),
                  (_) => const BookmarkState.saved(),
                ),
              )
            else
              existing,
        ],
      ),
    );
  }

  /// [bookmarkMessage]'s own save call — forwards to
  /// [_saveChatMessageAsEntryUseCase] verbatim, wrapped by
  /// [isolatedSideEffect] at the call site above (never here) so a
  /// synchronous throw from the use case itself is still caught.
  Future<Either<Failure, Entry>> _saveChatMessageAsEntry({
    required String content,
    required String chatMessageId,
  }) => _saveChatMessageAsEntryUseCase(
    content: content,
    chatMessageId: chatMessageId,
  );

  String _nextLocalId() => 'local-${_localIdCounter++}';

  /// spec-6-3 — [_connectivityWatcher]'s own listener: [isOnline] `true`
  /// means the device currently has connectivity. Always updates
  /// [_isOffline] (even outside [ChatReady] — see [_isOffline]'s own doc),
  /// but only *emits* when already [ChatReady] and the value actually
  /// changed, so an unrelated repeated emission of the same status (e.g.
  /// a plugin re-announcing "still online") never triggers a spurious
  /// rebuild.
  void _handleConnectivityChange(bool isOnline) {
    _isOffline = !isOnline;
    if (isClosed) {
      return;
    }
    final current = state;
    if (current is ChatReady && current.isOffline != _isOffline) {
      emit(current.copyWith(isOffline: _isOffline));
    }
  }

  /// Review finding: "Cross-session stream leakage" — [switchSession]/
  /// [startNewSession] call this before touching anything else whenever
  /// they're about to make a *different* session active, so a response
  /// still streaming into the session being left behind can never go on
  /// to mutate the one that replaces it. Exactly [close]'s own cleanup
  /// below (cancel the subscription, resolve the stranded [sendMessage]
  /// caller, clear the re-entrancy guard), just without closing the cubit
  /// itself — a no-op when nothing is actually in flight.
  Future<void> _cancelInFlightSend() async {
    if (!_isSending) {
      return;
    }
    await _sendSubscription?.cancel();
    _sendSubscription = null;
    final completer = _sendCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _sendCompleter = null;
    _isSending = false;
  }

  @override
  Future<void> close() {
    _connectivitySubscription?.cancel();
    _sendSubscription?.cancel();
    final completer = _sendCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _sendCompleter = null;
    return super.close();
  }
}
