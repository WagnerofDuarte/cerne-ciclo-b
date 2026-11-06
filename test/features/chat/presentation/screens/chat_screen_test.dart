import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/widgets/app_drawer.dart';
import 'package:cerne/features/capture/domain/repositories/media_repository.dart';
import 'package:cerne/features/capture/domain/services/audio_transcriber.dart';
import 'package:cerne/features/capture/domain/services/mic_recorder.dart';
import 'package:cerne/features/capture/domain/services/photo_picker.dart';
import 'package:cerne/features/capture/presentation/cubit/audio_entry_cubit.dart';
import 'package:cerne/features/capture/presentation/cubit/photo_entry_cubit.dart';
import 'package:cerne/features/capture/presentation/cubit/text_entry_cubit.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_cubit.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_state.dart';
import 'package:cerne/features/chat/presentation/screens/chat_screen.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

import '../../../../support/fake_connectivity_watcher.dart';

const _session = ChatSession(
  id: 's1',
  title: '',
  persona: ChatPersona.analitico,
  userMessageCount: 0,
  lastUserMessageAt: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// A controllable fake — lets each test drive bootstrap success/failure
/// and inspect [sendMessageCalls] without a mocking framework, same
/// pattern `chat_cubit_test.dart`'s own fake already uses.
class _FakeChatRepository implements ChatRepository {
  Either<Failure, List<ChatSession>> listSessionsResult = right([_session]);
  Either<Failure, List<ChatMessage>> listMessagesResult = right(const []);
  Either<Failure, ChatSession> createSessionResult = right(_session);
  final List<String> sendMessageCalls = [];
  StreamController<Either<Failure, ChatStreamEvent>>? lastSendController;
  final List<String> retryMessageCalls = [];
  StreamController<Either<Failure, ChatStreamEvent>>? lastRetryController;

  @override
  Future<Either<Failure, List<ChatSession>>> listSessions() async =>
      listSessionsResult;

  @override
  Future<Either<Failure, ChatSession>> createSession() async =>
      createSessionResult;

  @override
  Future<Either<Failure, List<ChatMessage>>> listMessages(
    String sessionId,
  ) async => listMessagesResult;

  @override
  Stream<Either<Failure, ChatStreamEvent>> sendMessage(
    String sessionId,
    String content,
  ) {
    sendMessageCalls.add(content);
    final controller = StreamController<Either<Failure, ChatStreamEvent>>();
    lastSendController = controller;
    return controller.stream;
  }

  @override
  Stream<Either<Failure, ChatStreamEvent>> retryMessage(
    String sessionId,
    String userMessageId,
  ) {
    retryMessageCalls.add(userMessageId);
    final controller = StreamController<Either<Failure, ChatStreamEvent>>();
    lastRetryController = controller;
    return controller.stream;
  }
}

/// Trivial fakes for the "+" control's own three cubits — this suite only
/// asserts the Insertion Modal actually opens on "+", never a real save,
/// same rationale the deleted `HomeChatPlaceholderScreen` test group's own
/// fakes already documented.
class _UnusedPendingEntryWriteTracker implements PendingEntryWriteTracker {
  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<void> retry(String tempId) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Stream<List<PendingEntryWrite>> get pendingWrites => const Stream.empty();

  @override
  Stream<({String tempId, Entry entry})> get confirmedWrites =>
      const Stream.empty();

  @override
  Future<void> dispose() async {}
}

class _UnusedMicRecorder implements MicRecorder {
  @override
  Future<bool> hasPermission() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<void> start() async => throw UnimplementedError('not expected to be called');

  @override
  Future<MicRecording?> stop() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<void> cancel() async => throw UnimplementedError('not expected to be called');

  @override
  Stream<double> get amplitudeStream => const Stream.empty();
}

class _UnusedAudioTranscriber implements AudioTranscriber {
  @override
  Future<String?> transcribe(String audioPath) async =>
      throw UnimplementedError('not expected to be called');
}

class _UnusedPhotoPicker implements PhotoPicker {
  @override
  Future<PickedPhoto?> pickFromCamera() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<PickedPhoto?> pickFromGallery() async =>
      throw UnimplementedError('not expected to be called');
}

class _UnusedMediaRepository implements MediaRepository {
  @override
  Future<Either<Failure, OcrResult>> recognizeText({
    required Uint8List imageBytes,
    required String mimeType,
  }) async => throw UnimplementedError('not expected to be called');
}

void main() {
  setUp(() {
    sl.registerFactory<TextEntryCubit>(
      () => TextEntryCubit(_UnusedPendingEntryWriteTracker()),
    );
    sl.registerFactory<AudioEntryCubit>(
      () => AudioEntryCubit(
        _UnusedMicRecorder(),
        _UnusedAudioTranscriber(),
        _UnusedPendingEntryWriteTracker(),
      ),
    );
    sl.registerFactory<PhotoEntryCubit>(
      () => PhotoEntryCubit(
        _UnusedPhotoPicker(),
        _UnusedMediaRepository(),
        _UnusedPendingEntryWriteTracker(),
      ),
    );
  });

  tearDown(resetCoreDependencies);

  Future<ChatCubit> pumpScreen(
    WidgetTester tester,
    _FakeChatRepository repository, {
    FakeConnectivityWatcher? connectivityWatcher,
  }) async {
    final watcher = connectivityWatcher ?? FakeConnectivityWatcher();
    final cubit = ChatCubit(repository, watcher);
    addTearDown(cubit.close);
    addTearDown(watcher.close);
    await tester.pumpWidget(MaterialApp(home: ChatScreen(cubit: cubit)));
    return cubit;
  }

  testWidgets(
    'dark-green header shows "Cerne"; ☰ opens AppDrawer',
    (tester) async {
      await pumpScreen(tester, _FakeChatRepository());
      await tester.pumpAndSettle();

      expect(find.text('Cerne'), findsOneWidget);
      expect(find.byType(AppDrawer), findsNothing);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.byType(AppDrawer), findsOneWidget);
    },
  );

  testWidgets(
    'settles on the composer enabled once bootstrap resolves (the loading '
    '-> ready transition itself is covered by chat_cubit_test.dart)',
    (tester) async {
      await pumpScreen(tester, _FakeChatRepository());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isTrue);
    },
  );

  testWidgets(
    'a bootstrap failure shows the generic error state, not an infinite '
    'spinner, and the composer stays disabled',
    (tester) async {
      final repository = _FakeChatRepository()
        ..listSessionsResult = left(
          const Failure.networkOffline(message: 'offline'),
        );
      await pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Não foi possível carregar a conversa'), findsOneWidget);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    },
  );

  testWidgets(
    'typing and sending calls ChatCubit.sendMessage and clears the field',
    (tester) async {
      final repository = _FakeChatRepository();
      await pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Olá, tudo bem?');
      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.pump();

      expect(repository.sendMessageCalls, ['Olá, tudo bem?']);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, isEmpty);

      // Finalizes the AI bubble before pumpAndSettle — a bubble left
      // `streaming` keeps its cursor animation ticking forever (by
      // design), which would otherwise hang `pumpAndSettle()`.
      repository.lastSendController?.add(right(const ChatDoneEvent()));
      await repository.lastSendController?.close();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the composer disables while an AI bubble is streaming',
    (tester) async {
      final repository = _FakeChatRepository();
      await pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'oi');
      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);

      repository.lastSendController?.add(right(const ChatDoneEvent()));
      await repository.lastSendController?.close();
      await tester.pumpAndSettle();

      final reEnabledField = tester.widget<TextField>(find.byType(TextField));
      expect(reEnabledField.enabled, isTrue);
    },
  );

  testWidgets(
    'the "+" control opens the Insertion Modal on Texto',
    (tester) async {
      await pumpScreen(tester, _FakeChatRepository());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Texto'), findsOneWidget);
      expect(find.text('Áudio'), findsOneWidget);
      expect(find.text('Foto'), findsOneWidget);
    },
  );

  testWidgets(
    'review finding: a real ChatScreen focuses the composer once '
    'ChatCubit.startNewSession() lands on a new, empty session (AC2 — '
    '"it opens empty, composer focused")',
    (tester) async {
      // A non-empty bootstrap history (the guard this screen's own
      // listener actually uses is `state.messages.isEmpty`, not "brand
      // new session" — Design Notes) so the initial load does *not*
      // itself focus the composer, isolating `startNewSession()`'s own
      // empty-session landing as the thing under test.
      final repository = _FakeChatRepository()
        ..listMessagesResult = right([
          const ChatMessage(
            id: 'm0',
            sessionId: 's1',
            role: ChatMessageRole.user,
            content: 'oi',
            seq: 0,
            status: ChatMessageStatus.complete,
            retryCount: 0,
            createdAt: '2026-01-01T00:00:00Z',
          ),
        ]);
      final cubit = await pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      var textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.focusNode!.hasFocus, isFalse);

      repository.createSessionResult = right(
        const ChatSession(
          id: 's2',
          title: '',
          persona: ChatPersona.analitico,
          userMessageCount: 0,
          lastUserMessageAt: null,
          createdAt: '2026-01-02T00:00:00Z',
          updatedAt: '2026-01-02T00:00:00Z',
        ),
      );

      final result = await cubit.startNewSession();
      await tester.pumpAndSettle();

      expect(result.isRight(), isTrue);
      expect((cubit.state as ChatReady).sessionId, 's2');
      textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'review finding: a real ChatScreen restores the scroll offset it '
    'was left at when switching back to a session, instead of jumping '
    'to the bottom (AC4)',
    (tester) async {
      final manyMessages = List.generate(
        30,
        (i) => ChatMessage(
          id: 'm$i',
          sessionId: 's1',
          role: ChatMessageRole.user,
          content:
              'mensagem numero $i, bem mais longa para garantir altura '
              'suficiente e permitir rolagem dentro da lista de mensagens',
          seq: i,
          status: ChatMessageStatus.complete,
          retryCount: 0,
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
      final repository = _FakeChatRepository()
        ..listMessagesResult = right(manyMessages);
      final cubit = await pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      ScrollController controller() =>
          tester.widget<ListView>(find.byType(ListView)).controller!;

      // Bootstrap jumps to the bottom by default (`_scrollToBottomSoon`)
      // — drag up so this session is left scrolled somewhere in the
      // middle instead, the scenario AC4 actually describes.
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();

      final recordedOffset = controller().position.pixels;
      expect(recordedOffset, greaterThan(0));

      // Switch away to a different, empty session.
      repository.listMessagesResult = right(const []);
      await cubit.switchSession('s2');
      await tester.pumpAndSettle();

      // ... and back, with the same history (and therefore the same
      // scrollable extent) restored.
      repository.listMessagesResult = right(manyMessages);
      await cubit.switchSession('s1');
      await tester.pumpAndSettle();

      expect(controller().position.pixels, closeTo(recordedOffset, 1.0));
    },
  );

  group('spec-6-3 — offline composer lock + banner', () {
    testWidgets(
      'I/O matrix "Goes offline mid-session": the composer disables and '
      'the offline banner appears, while history stays visible',
      (tester) async {
        final watcher = FakeConnectivityWatcher();
        await pumpScreen(
          tester,
          _FakeChatRepository(),
          connectivityWatcher: watcher,
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Sem conexão — histórico disponível, novas mensagens '
            'bloqueadas',
          ),
          findsNothing,
        );
        var textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.enabled, isTrue);

        watcher.emit(false);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Sem conexão — histórico disponível, novas mensagens '
            'bloqueadas',
          ),
          findsOneWidget,
        );
        textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.enabled, isFalse);
        // The "+" stays tappable (Boundaries: never disabled offline).
        expect(
          tester.widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.add),
              matching: find.byType(IconButton),
            ),
          ).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'I/O matrix "Comes back online": the banner disappears and the '
      'composer re-enables automatically',
      (tester) async {
        final watcher = FakeConnectivityWatcher();
        await pumpScreen(
          tester,
          _FakeChatRepository(),
          connectivityWatcher: watcher,
        );
        await tester.pumpAndSettle();

        watcher.emit(false);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );

        watcher.emit(true);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Sem conexão — histórico disponível, novas mensagens '
            'bloqueadas',
          ),
          findsNothing,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
      },
    );
  });

  testWidgets(
    'spec-6-3 — I/O matrix "Tap retry, no serverId": tapping a failed AI '
    'bubble\'s retry copy, when message_created never arrived, falls back '
    'to a sendMessage resend (ChatCubit.retryMessage is still the call '
    'site, keyed off the bubble\'s own id)',
    (tester) async {
      final repository = _FakeChatRepository();
      final cubit = await pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'oi');
      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.pump();

      // A mid-stream drop — same shape `chat_cubit_test.dart`'s own
      // "mid-stream drop" case uses, marking the AI bubble failed.
      repository.lastSendController?.add(
        left(const Failure.networkTimeout(message: 'drop')),
      );
      await repository.lastSendController?.close();
      await tester.pumpAndSettle();

      final failedAiId = (cubit.state as ChatReady).messages[1].id;
      expect(
        find.text('Falha ao gerar resposta — toque para tentar novamente'),
        findsOneWidget,
      );

      await tester.tap(
        find.text('Falha ao gerar resposta — toque para tentar novamente'),
      );
      await tester.pump();

      expect(repository.retryMessageCalls, isEmpty);
      // No serverId was ever captured (message_created never arrived) —
      // the fallback path resends via sendMessage instead.
      expect(repository.sendMessageCalls, ['oi', 'oi']);

      // Finalize the retried bubble before pumpAndSettle — a bubble left
      // `streaming` keeps its cursor animation ticking forever (by
      // design), which would otherwise hang pumpAndSettle().
      repository.lastSendController?.add(right(const ChatDoneEvent()));
      await repository.lastSendController?.close();
      await tester.pumpAndSettle();
      expect((cubit.state as ChatReady).messages[1].id, failedAiId);
    },
  );

  testWidgets(
    'spec-6-3 — I/O matrix "Tap retry, normal": tapping a failed AI '
    'bubble\'s retry copy, when the preceding user message already has a '
    'serverId (message_created arrived before the drop), calls '
    'chat-messages-retry — never the sendMessage fallback — and resolves '
    'the same bubble in place',
    (tester) async {
      final repository = _FakeChatRepository();
      final cubit = await pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'oi');
      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.pump();

      // message_created arrives (capturing the user bubble's own
      // serverId) before the stream drops mid-response.
      repository.lastSendController?.add(
        right(const ChatMessageCreatedEvent('srv-user-1')),
      );
      repository.lastSendController?.add(
        right(const ChatTokenEvent('resposta parcial')),
      );
      repository.lastSendController?.add(
        left(const Failure.networkTimeout(message: 'drop')),
      );
      await repository.lastSendController?.close();
      await tester.pumpAndSettle();

      final ready = cubit.state as ChatReady;
      expect(ready.messages[0].serverId, 'srv-user-1');
      final failedAiId = ready.messages[1].id;
      expect(
        find.text('Falha ao gerar resposta — toque para tentar novamente'),
        findsOneWidget,
      );

      await tester.tap(
        find.text('Falha ao gerar resposta — toque para tentar novamente'),
      );
      await tester.pump();

      // chat-messages-retry was called, keyed by the preceding user
      // message's serverId — never a full sendMessage resend.
      expect(repository.retryMessageCalls, ['srv-user-1']);
      expect(repository.sendMessageCalls, ['oi']);

      // The same bubble (id unchanged) reset to streaming/empty, then
      // filled via the retry's own stream.
      var afterTap = cubit.state as ChatReady;
      expect(afterTap.messages[1].id, failedAiId);
      expect(afterTap.messages[1].content, '');
      expect(afterTap.messages[1].status, ChatMessageStatus.streaming);

      repository.lastRetryController?.add(
        right(const ChatTokenEvent('nova resposta')),
      );
      await tester.pump();
      afterTap = cubit.state as ChatReady;
      expect(afterTap.messages[1].content, 'nova resposta');

      repository.lastRetryController?.add(right(const ChatDoneEvent()));
      await repository.lastRetryController?.close();
      await tester.pumpAndSettle();

      final finalState = cubit.state as ChatReady;
      expect(finalState.messages, hasLength(2));
      expect(finalState.messages[1].id, failedAiId);
      expect(finalState.messages[1].content, 'nova resposta');
      expect(finalState.messages[1].status, ChatMessageStatus.complete);
    },
  );

  testWidgets(
    'spec-6-3 review finding: a rapid double-tap on the retry copy before '
    'the first tap\'s rebuild lands only ever triggers one '
    'chat-messages-retry call (ChatCubit._isSending swallows the second)',
    (tester) async {
      final repository = _FakeChatRepository();
      await pumpScreen(tester, repository);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'oi');
      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.pump();

      repository.lastSendController?.add(
        right(const ChatMessageCreatedEvent('srv-user-1')),
      );
      repository.lastSendController?.add(
        left(const Failure.networkTimeout(message: 'drop')),
      );
      await repository.lastSendController?.close();
      await tester.pumpAndSettle();

      expect(
        find.text('Falha ao gerar resposta — toque para tentar novamente'),
        findsOneWidget,
      );

      // Two taps back-to-back, with no pump in between — mirrors a real
      // double-tap landing before the first one's own rebuild (which
      // would otherwise remove/replace the tapped widget) has a chance
      // to run.
      await tester.tap(
        find.text('Falha ao gerar resposta — toque para tentar novamente'),
      );
      await tester.tap(
        find.text('Falha ao gerar resposta — toque para tentar novamente'),
      );
      await tester.pump();

      expect(repository.retryMessageCalls, ['srv-user-1']);

      repository.lastRetryController?.add(right(const ChatDoneEvent()));
      await repository.lastRetryController?.close();
      await tester.pumpAndSettle();
    },
  );
}
