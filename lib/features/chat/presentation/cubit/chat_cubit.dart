import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_session.dart';
import '../../domain/entities/chat_stream_event.dart';
import '../../domain/repositories/chat_repository.dart';
import 'chat_state.dart';

/// Drives `ChatScreen` — a DI `lazySingleton` (Code Map, mirroring
/// `MeusRegistrosCubit`): long-lived, so returning to Home/Chat within the
/// same app session never re-bootstraps the session/history it already
/// loaded (`init()`'s own no-op guard below).
class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._repository) : super(const ChatBootstrapLoading());

  final ChatRepository _repository;

  StreamSubscription<Either<Failure, ChatStreamEvent>>? _sendSubscription;

  /// The in-flight [sendMessage]'s own completer, if any — [close] must
  /// complete it itself, since cancelling [_sendSubscription] never fires
  /// `onDone`/`onError` (review fix: `cancel()` alone left `sendMessage()`'s
  /// returned `Future` permanently unresolved when the cubit closed mid-send).
  Completer<void>? _sendCompleter;

  /// Monotonic counter behind every locally generated [ChatUiMessage.id]
  /// (Code Map) — never the server's own message id (see `ChatStreamEvent`'s
  /// own doc on why `message_created`'s id goes unused here).
  int _localIdCounter = 0;

  /// Whether a send is actively in flight right now — tracked locally
  /// rather than by scanning [ChatState.messages] for a persisted
  /// `streaming` status, since a message loaded from history/cache can
  /// legitimately carry that same status (e.g. one left over from an
  /// earlier dropped response, the I/O matrix's own scenario) without a
  /// send actually being in progress; scanning for it would permanently
  /// disable the composer in that case.
  bool _isSending = false;

  /// An in-flight bootstrap, if any — reused by a concurrent `init()` call
  /// instead of starting a second bootstrap, so two near-simultaneous
  /// callers (e.g. two mounts before the first resolves) never both
  /// observe "no sessions" and both call `createSession()` (Boundaries:
  /// "silently ensure *one* Chat Session exists").
  Future<void>? _initFuture;

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
          final mostRecent = [...fetchedSessions]..sort(
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
    return messagesResult.match((failure) => left(failure), (messages) {
      if (!isClosed) {
        emit(
          ChatReady(
            sessionId: sessionId,
            messages: messages.map(_fromDomain).toList(),
            sessions: current.sessions,
            restoreScrollOffset: _scrollOffsets[sessionId],
          ),
        );
      }
      return right(unit);
    });
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
    return result.match((failure) => left(failure), (session) {
      if (!isClosed) {
        emit(
          ChatReady(
            sessionId: session.id,
            messages: const [],
            sessions: [session, ...current.sessions],
          ),
        );
      }
      return right(unit);
    });
  }

  ChatUiMessage _fromDomain(ChatMessage message) => ChatUiMessage(
    id: message.id,
    role: message.role,
    content: message.content,
    status: message.status,
  );

  /// Boundaries: optimistic user bubble, then subscribes to
  /// `ChatRepository.sendMessage`'s own stream, appending tokens as they
  /// arrive and finalizing/failing the AI bubble on `done`/any `Left` —
  /// the bubble's own [ChatUiMessage.content] is never cleared on failure
  /// (I/O matrix), only its [ChatUiMessage.status] changes.
  ///
  /// A no-op while [state] isn't [ChatReady] (bootstrap still in flight
  /// or failed — the composer is disabled in that case anyway), while
  /// [content] is blank once trimmed, or while [_isSending] is already
  /// true — this story never races two concurrent sends against the one
  /// in-memory session (Boundaries: no offline lock/composer-disable UI
  /// of its own exists yet, Story 6.3's job, so this guard is the one
  /// thing standing in for it here). Deliberately not keyed off any
  /// loaded message's persisted `streaming` status — a message restored
  /// from history/cache can legitimately carry that status without a
  /// send actually being in flight (I/O matrix: mid-stream drop).
  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final current = state;
    if (current is! ChatReady) {
      return;
    }
    if (_isSending) {
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

    await _sendSubscription?.cancel();
    final completer = Completer<void>();
    _sendCompleter = completer;
    _sendSubscription = _repository
        .sendMessage(current.sessionId, trimmed)
        .listen(
          (event) {
            event.match(
              (failure) => _markFailed(aiMessage.id),
              (streamEvent) => _applyStreamEvent(aiMessage.id, streamEvent),
            );
          },
          onError: (Object _, StackTrace _) {
            // RNF09: no exception escapes the cubit — a stream-level
            // error (shouldn't happen, `ChatRemoteDataSource.sendMessage`
            // never lets one through unmapped) still only fails the
            // bubble, never crashes.
            _markFailed(aiMessage.id);
            _finishSending();
            if (!completer.isCompleted) {
              completer.complete();
            }
            _sendCompleter = null;
          },
          onDone: () {
            _finishSending();
            if (!completer.isCompleted) {
              completer.complete();
            }
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

  void _applyStreamEvent(String aiMessageId, ChatStreamEvent event) {
    if (isClosed) {
      return;
    }
    final current = state;
    if (current is! ChatReady) {
      return;
    }
    switch (event) {
      case ChatMessageCreatedEvent():
        // Design Notes: the persisted *user*-message id — no UI-facing
        // use yet in this story (Story 6.3's retry call is the first
        // consumer).
        break;
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

  String _nextLocalId() => 'local-${_localIdCounter++}';

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
    _sendSubscription?.cancel();
    final completer = _sendCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _sendCompleter = null;
    return super.close();
  }
}
