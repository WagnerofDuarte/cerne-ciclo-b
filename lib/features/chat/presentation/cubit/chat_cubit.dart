import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/isolated_side_effect.dart';
import '../../../entries/domain/entities/entry.dart';
import '../../../entries/domain/usecases/save_chat_message_as_entry_use_case.dart';
import '../../domain/entities/bookmark_state.dart';
import '../../domain/entities/chat_insight.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_session.dart';
import '../../domain/entities/chat_stream_event.dart';
import '../../domain/insight_trigger_config.dart';
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
    this._saveChatMessageAsEntryUseCase, {
    // spec-6-5 Design Notes: "the inactivity Duration is constructor-
    // overridable purely for test speed (no fake_async dependency exists
    // in this project)" — production never passes this, so the default
    // (the real 2-minute constant) is always what runs; no
    // `chat_injection.dart` change needed.
    Duration insightInactivityTimeout = defaultInsightInactivityTimeout,
  }) : _insightTimeout = insightInactivityTimeout,
       super(const ChatBootstrapLoading()) {
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

  /// Review fix (round 2) — [bookmarkMessage]'s own save outcome, keyed
  /// by the message's `serverId` (never the in-session [ChatUiMessage.id],
  /// which is only a local id until the server confirms it, Design Notes)
  /// so a save that resolves *after* the user has switched/started a
  /// session — [switchSession]/[startNewSession] replace [ChatReady.
  /// messages] wholesale and never cancel a bookmark save in flight,
  /// unlike [_cancelInFlightSend] for send/retry — is never silently
  /// dropped. [_fromDomain] applies it when a session's history is
  /// (re)loaded; same in-memory-only, never-persisted-across-restarts
  /// lifetime as [_scrollOffsets] above (Boundaries).
  final Map<String, BookmarkState> _bookmarkStateByServerId = {};

  /// spec-6-5 — the per-session trigger-window timeout racing
  /// [insightMessageCountThreshold] (Boundaries); overridable only via
  /// the constructor's own test seam (Design Notes).
  final Duration _insightTimeout;

  /// spec-6-5 — user messages sent via [sendMessage] only (never
  /// [retryMessage], Boundaries) since the current trigger window
  /// opened. Reset to `0` every time a window closes, by either trigger.
  int _insightMessagesSinceWindowStart = 0;

  /// spec-6-5 — the current window's own inactivity side of the race;
  /// cancelled/restarted on every [sendMessage] call and every window
  /// close (Boundaries) — a single field, never a per-session map,
  /// because only one session is ever active/racing at a time
  /// ([switchSession]/[startNewSession] always reopen a fresh window for
  /// whichever session becomes active, Boundaries: "never let the
  /// counter/timer leak across sessions").
  Timer? _insightInactivityTimer;

  /// spec-6-5 — the current window's own client-generated key, echoed to
  /// `chat-insight-create` as `triggerKey` (Design Notes: "the contract
  /// only requires minLength: 1 with no documented semantics beyond
  /// echoing it back").
  String _insightTriggerKey = '';

  /// spec-6-5 — monotonic counter behind every freshly generated
  /// [_insightTriggerKey], mirrors [_localIdCounter]/[_nextLocalId].
  int _insightWindowCounter = 0;

  /// Review fix: a monotonic counter bumped once per [_fireInsightTrigger]
  /// call, so [_applyInsightResult] can tell whether the result it just
  /// received still belongs to the most recently fired request. A window
  /// reopens (and can fire again) immediately after the previous one
  /// fires, before that previous call's own response has necessarily
  /// arrived — without this guard, two overlapping in-flight calls for
  /// the *same* session could resolve out of order, letting a stale
  /// (older) result overwrite a newer `activeInsight`, or resurrect one
  /// the user already dismissed. Unlike [_insightTriggerKey] (which
  /// identifies *which window* a request was for for the backend's own
  /// idempotency), this identifies *recency* across overlapping requests
  /// for the cubit's own purposes — the backend is never told about it.
  int _insightRequestSeq = 0;

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
          (messages) {
            // spec-6-5 — opens this cubit's very first trigger window,
            // tied to the session this bootstrap settled on.
            _resetInsightWindow(session.id);
            emit(
              ChatReady(
                sessionId: session.id,
                messages: messages.map(_fromDomain).toList(),
                sessions: sessions,
                isOffline: _isOffline,
              ),
            );
          },
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
          // spec-6-5 — reopens a fresh trigger window for the session
          // becoming active, so the previous session's own window
          // (counter/timer) never leaks across the switch (Boundaries).
          _resetInsightWindow(sessionId);
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
          // spec-6-5 — same rationale as [switchSession] above: a brand
          // new session always needs its own fresh trigger window.
          _resetInsightWindow(session.id);
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
    // Review fix (round 2) — re-applies a bookmark save's outcome that
    // resolved while this message wasn't part of the live `ChatReady`
    // (session switched away mid-save); `idle` default when nothing was
    // ever recorded for this `serverId`.
    bookmarkState:
        _bookmarkStateByServerId[message.id] ?? const BookmarkState.idle(),
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

    // spec-6-5 — counts only a genuine sendMessage() call (never
    // retryMessage, Boundaries: "a counter ... never retryMessage").
    // Whichever of the two trigger conditions is satisfied first wins
    // the race for this window; reaching the threshold here fires
    // immediately rather than waiting for the inactivity timer to also
    // elapse.
    _insightMessagesSinceWindowStart++;
    if (_insightMessagesSinceWindowStart >= insightMessageCountThreshold) {
      _fireInsightTrigger(current.sessionId, InsightTriggerType.messageCount);
    } else {
      // Counter/key untouched (Code Map) — only the inactivity side of
      // the race restarts, so the window itself stays open.
      _restartInsightInactivityTimer(current.sessionId);
    }

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
    _bookmarkStateByServerId[serverId] = const BookmarkState.saving();
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

    final resolvedState = result.match(
      (failure) => BookmarkState.error(failure),
      (_) => const BookmarkState.saved(),
    );
    // Review fix (round 2) — written through to the serverId-keyed map
    // unconditionally (even if the live [ChatReady] below has since moved
    // on to a different session), so the outcome is never lost; re-
    // entering any session carrying this message picks it back up via
    // [_fromDomain].
    _bookmarkStateByServerId[serverId] = resolvedState;

    if (isClosed) {
      return;
    }
    final latest = state;
    if (latest is! ChatReady) {
      return;
    }
    // Matched by `serverId`, not the in-session `messageId` — the latter
    // is stale once [switchSession]/[startNewSession] reloads this exact
    // session's history mid-save, which re-derives every message's own
    // `id` from the server (`_fromDomain`) instead of keeping the local
    // id this call started with.
    final stillVisible = latest.messages.any(
      (existing) => existing.serverId == serverId,
    );
    if (!stillVisible) {
      return;
    }
    emit(
      latest.copyWith(
        messages: [
          for (final existing in latest.messages)
            if (existing.serverId == serverId)
              existing.copyWith(bookmarkState: resolvedState)
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

  /// spec-6-5 — opens a fresh trigger window for [sessionId]: zeroes the
  /// message counter, generates a new [_insightTriggerKey] (mirrors
  /// [_nextLocalId]'s own counter-based shape), then restarts the
  /// inactivity side of the race via [_restartInsightInactivityTimer].
  /// Called from every one of the 3 existing direct `ChatReady(...)`
  /// constructions ([_bootstrap]/[switchSession]/[startNewSession]) and
  /// from [_fireInsightTrigger] itself, immediately after firing
  /// (Boundaries: "resets the counter ... before the network call
  /// resolves, so the window closes structurally and the other
  /// condition can never also fire for it").
  void _resetInsightWindow(String sessionId) {
    _insightMessagesSinceWindowStart = 0;
    _insightTriggerKey = 'insight-${_insightWindowCounter++}';
    _restartInsightInactivityTimer(sessionId);
  }

  /// spec-6-5 — [sendMessage]'s own "else" branch (below threshold):
  /// cancels/restarts the inactivity timer alone, leaving the message
  /// counter/[_insightTriggerKey] untouched (Code Map) — also the tail
  /// end of [_resetInsightWindow] above, which touches all three.
  void _restartInsightInactivityTimer(String sessionId) {
    _insightInactivityTimer?.cancel();
    _insightInactivityTimer = Timer(_insightTimeout, () {
      _fireInsightTrigger(sessionId, InsightTriggerType.inactivity);
    });
  }

  /// spec-6-5 — fires whichever trigger condition won the race
  /// ([triggerType]): captures the current [_insightTriggerKey], reopens
  /// the *next* window immediately via [_resetInsightWindow] (Boundaries:
  /// "before the network call resolves"), then calls
  /// `ChatRepository.generateInsight` through [isolatedSideEffect],
  /// **unawaited** (Boundaries: "never await the insight
  /// isolatedSideEffect call" — this story's first unawaited caller, per
  /// the epic's own Technical Decisions). The result, whenever it
  /// resolves, is routed through [_applyInsightResult].
  void _fireInsightTrigger(String sessionId, InsightTriggerType triggerType) {
    final triggerKey = _insightTriggerKey;
    // Review fix: captured *before* the call resolves, so a later-fired
    // request (which bumps this same counter again) can be told apart
    // from this one when both are still in flight.
    final requestSeq = ++_insightRequestSeq;
    _resetInsightWindow(sessionId);
    unawaited(
      isolatedSideEffect(
        () => _generateInsight(
          sessionId,
          triggerType: triggerType,
          triggerKey: triggerKey,
        ),
      ).then((result) => _applyInsightResult(sessionId, requestSeq, result)),
    );
  }

  /// [_fireInsightTrigger]'s own call — forwards to
  /// [ChatRepository.generateInsight] verbatim, wrapped by
  /// [isolatedSideEffect] at the call site above (never here), same
  /// double-`Either` shape [_saveChatMessageAsEntry] already uses for
  /// [bookmarkMessage].
  Future<Either<Failure, ChatInsight?>> _generateInsight(
    String sessionId, {
    required InsightTriggerType triggerType,
    required String triggerKey,
  }) => _repository.generateInsight(
    sessionId,
    triggerType: triggerType,
    triggerKey: triggerKey,
  );

  /// Flattens [isolatedSideEffect]'s own outer `Either` (`Left` only on a
  /// thrown exception) with [ChatRepository.generateInsight]'s own inner
  /// `Either` (`Left` on a transport failure; `Right(null)` on a
  /// successful call whose `status` wasn't `'ready'`) into one plain
  /// `Either<Failure, ChatInsight?>` — same flattening shape
  /// [bookmarkMessage] already uses for its own side effect. Any `Left`,
  /// or a `null` insight either way, is a fully silent no-op (Boundaries:
  /// "no card, no overlay, no retry affordance"). On a real insight,
  /// guards [isClosed], that [requestSeq] is still the *most recently
  /// fired* request (review fix: discards a stale result from a request
  /// a later one has since superseded, so it can never overwrite a newer
  /// `activeInsight` or resurrect one the user already dismissed), and
  /// that [state] is still [ChatReady] for this exact [sessionId] — an
  /// insight resolving after [switchSession]/[startNewSession] moved away
  /// is dropped (Boundaries/I/O matrix: "Session switched mid-flight").
  void _applyInsightResult(
    String sessionId,
    int requestSeq,
    Either<Failure, Either<Failure, ChatInsight?>> result,
  ) {
    final flattened = result.match(
      (failure) => left(failure),
      (inner) => inner,
    );
    final insight = flattened.match((_) => null, (insight) => insight);
    if (insight == null || isClosed || requestSeq != _insightRequestSeq) {
      return;
    }
    final current = state;
    if (current is! ChatReady || current.sessionId != sessionId) {
      return;
    }
    emit(current.copyWith(activeInsight: insight));
  }

  /// spec-6-5 — Boundaries: clears [ChatReady.activeInsight] via a direct
  /// `ChatReady(...)` construction, every other field carried forward
  /// unchanged — `copyWith`'s own `??` pattern can never express "set to
  /// null" (same reason [switchSession]/[startNewSession]/[_bootstrap]
  /// already build a fresh `ChatReady` directly instead of through
  /// `copyWith` whenever a field needs to go to `null`/be replaced
  /// wholesale). Never calls the backend — no dismiss endpoint exists in
  /// the contract (Boundaries) — and never touches any other field,
  /// including scroll position (Acceptance Criteria). A no-op while
  /// [state] isn't [ChatReady], or while [ChatReady.activeInsight] is
  /// already `null` (I/O matrix: "Dismiss with none active").
  void dismissInsight() {
    if (isClosed) {
      return;
    }
    final current = state;
    if (current is! ChatReady || current.activeInsight == null) {
      return;
    }
    emit(
      ChatReady(
        sessionId: current.sessionId,
        messages: current.messages,
        sessions: current.sessions,
        isSending: current.isSending,
        restoreScrollOffset: current.restoreScrollOffset,
        isOffline: current.isOffline,
      ),
    );
  }

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
    // spec-6-5 — a closed cubit must never let a pending trigger fire
    // into a dead instance.
    _insightInactivityTimer?.cancel();
    final completer = _sendCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _sendCompleter = null;
    return super.close();
  }
}
