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
import 'package:cerne/features/chat/presentation/screens/chat_screen.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

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
  final List<String> sendMessageCalls = [];
  StreamController<Either<Failure, ChatStreamEvent>>? lastSendController;

  @override
  Future<Either<Failure, List<ChatSession>>> listSessions() async =>
      listSessionsResult;

  @override
  Future<Either<Failure, ChatSession>> createSession() async => right(_session);

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
    _FakeChatRepository repository,
  ) async {
    final cubit = ChatCubit(repository);
    addTearDown(cubit.close);
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
      await tester.tap(find.byIcon(Icons.send));
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
      await tester.tap(find.byIcon(Icons.send));
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
}
