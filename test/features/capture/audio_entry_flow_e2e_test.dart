import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/url_builder.dart';
import 'package:cerne/features/capture/domain/services/audio_transcriber.dart';
import 'package:cerne/features/capture/domain/services/mic_recorder.dart';
import 'package:cerne/features/capture/presentation/cubit/audio_entry_cubit.dart';

import '../../support/fake_path_provider_platform.dart';

/// Only the transport boundary is faked (`HttpClientAdapter`), same
/// convention as `capture_flow_e2e_test.dart`'s own adapter for
/// `TextEntryCubit`.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<({int statusCode, Map<String, dynamic> body})> _queue = [];

  void queueJsonResponse(int statusCode, Map<String, dynamic> body) {
    _queue.add((statusCode: statusCode, body: body));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_queue.isEmpty) {
      throw StateError(
        'No queued response for ${options.method} ${options.path}',
      );
    }
    final next = _queue.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(next.body),
      next.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A fixed-outcome `MicRecorder` test double — `audio_entry_cubit_test.dart`
/// already covers every recording/permission branch against a mocktail
/// mock; this one only needs to get the real, DI-resolved `AudioEntryCubit`
/// from `AudioIdle` into `AudioTranscribed` so this suite's own two tests
/// can exercise the save() leg's real network + Hive pipeline, same as
/// `capture_flow_e2e_test.dart` does for `TextEntryCubit`.
class _FakeMicRecorder implements MicRecorder {
  _FakeMicRecorder(this.recordingPath);

  final String recordingPath;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<MicRecording?> stop() async =>
      MicRecording(path: recordingPath, durationSeconds: 7);

  @override
  Future<void> cancel() async {}

  @override
  Stream<double> get amplitudeStream => const Stream.empty();
}

/// A fixed-text `AudioTranscriber` test double — never the real
/// `whisper_ggml`-backed implementation (Never, `audio_entry_cubit_test.
/// dart`'s own doc comment: "no automated test exercises the real
/// `record`/`whisper_ggml` native plugins").
class _FakeAudioTranscriber implements AudioTranscriber {
  @override
  Future<String?> transcribe(String audioPath) async => 'Hoje foi um bom dia.';
}

/// End-to-end coverage for spec-3-2's save() leg — complements rather than
/// duplicates `audio_entry_cubit_test.dart` (mocked `MicRecorder`/
/// `AudioTranscriber` *and* mocked `EntriesRepository`, covers every cubit
/// state transition) by driving the real, DI-resolved `AudioEntryCubit`
/// through the real `EntriesRepositoryImpl` -> `EntriesRemoteDataSource` ->
/// `ApiClient` -> `Dio` (both real interceptors attached) -> a real
/// `entries` Hive box, exactly like `capture_flow_e2e_test.dart` already
/// proves for `TextEntryCubit`.
///
/// Only three things are faked: the transport boundary (`HttpClientAdapter`,
/// same as the text-entry suite), the native plugins (secure storage,
/// path_provider), and — per the "Never" boundary above — `MicRecorder`/
/// `AudioTranscriber` themselves, swapped into the real `sl` container
/// *before* `AudioEntryCubit` is ever resolved, so the real `record`/
/// `whisper_ggml` singletons `capture_injection.dart` would otherwise
/// register are never built, let alone exercised.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final fakeNativeStorage = <String, String>{};

  Future<dynamic> handleSecureStorageCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>;
    switch (call.method) {
      case 'write':
        fakeNativeStorage[args['key'] as String] = args['value'] as String;
        return null;
      case 'read':
        return fakeNativeStorage[args['key'] as String];
      case 'delete':
        fakeNativeStorage.remove(args['key'] as String);
        return null;
      case 'containsKey':
        return fakeNativeStorage.containsKey(args['key'] as String);
      default:
        return null;
    }
  }

  late FakePathProviderPlatform fakePathProvider;
  late _FakeHttpClientAdapter adapter;
  late File recordingFile;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, handleSecureStorageCall);
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;

    await resetCoreDependencies();
    await setupCoreDependencies();

    // Swap only the transport boundary on the real, DI-resolved Dio
    // instance — both real interceptors (header + retry) stay attached.
    adapter = _FakeHttpClientAdapter();
    sl<Dio>().httpClientAdapter = adapter;

    // `entries-create` is a bearer-required operation — seed a user access
    // token through the real AccessTokenProvider (backed by the faked
    // secure storage channel above) so the real header interceptor has one
    // to send.
    await sl<AccessTokenProvider>().saveAccessToken('e2e-test-access-token');

    // A real file on disk — `AudioEntryCubit.save()` deletes it on a
    // successful save (best-effort), so the happy-path test below can
    // assert that cleanup genuinely happened.
    recordingFile = File(
      '${Directory.systemTemp.path}/audio_entry_flow_e2e_${DateTime.now().microsecondsSinceEpoch}.wav',
    )..writeAsBytesSync([0]);

    // Registered *before* `sl<AudioEntryCubit>()` is ever resolved below,
    // so the real `record_pkg.AudioRecorder`/`WhisperController` singletons
    // `registerCaptureFeature()` wired are never built.
    sl.unregister<MicRecorder>();
    sl.registerLazySingleton<MicRecorder>(
      () => _FakeMicRecorder(recordingFile.path),
    );
    sl.unregister<AudioTranscriber>();
    sl.registerLazySingleton<AudioTranscriber>(_FakeAudioTranscriber.new);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    fakeNativeStorage.clear();
    await Hive.close();
    await resetCoreDependencies();
    await fakePathProvider.cleanUp();
    if (recordingFile.existsSync()) {
      recordingFile.deleteSync();
    }
  });

  Future<void> waitUntilDeleted(File file) async {
    for (var i = 0; i < 50 && file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'happy path: driving the real, DI-resolved AudioEntryCubit through '
    'startRecording() + stopRecording() (fake MicRecorder/AudioTranscriber) '
    'then save() fires a genuine POST to entries-create with the right '
    'URL/headers/body (source: audio, mediaDurationSeconds), emits '
    'AudioSaved, the entry really lands in the real entries Hive box, and '
    'the temp recording file is deleted',
    () async {
      adapter.queueJsonResponse(200, {
        'data': {
          'id': 'e2e-audio-entry-1',
          'content': 'Hoje foi um bom dia.',
          'source': 'audio',
          'chatMessageId': null,
          'occurredAt': '2026-01-01T00:00:00Z',
          'serverRevision': 1,
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
          'mediaDurationSeconds': 7,
        },
      });

      // The exact factory resolution `placeholder_screens.dart`'s "+"
      // control performs (Boundaries: a fresh instance per "+" tap).
      final cubit = sl<AudioEntryCubit>();
      addTearDown(cubit.close);

      await cubit.startRecording();
      await cubit.stopRecording();

      expect(cubit.state, isA<AudioTranscribed>());
      expect((cubit.state as AudioTranscribed).text, 'Hoje foi um bom dia.');

      await cubit.save();

      expect(cubit.state, isA<AudioSaved>());

      // Exactly one real request left through the fake transport, built
      // by the real UrlBuilder/HeaderInterceptor, not a mock of ApiClient.
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single;
      expect(sent.path, sl<UrlBuilder>().build('entries-create'));
      expect(sent.data, {
        'content': 'Hoje foi um bom dia.',
        'source': 'audio',
        'mediaDurationSeconds': 7,
      });
      expect(sent.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
      expect(sent.headers['Authorization'], 'Bearer e2e-test-access-token');

      // The real write-through happened against the real Hive box.
      final box = sl<Box<Map>>();
      final stored = box.get('e2e-audio-entry-1');
      expect(stored, isNotNull);
      expect(stored!['content'], 'Hoje foi um bom dia.');
      expect(stored['source'], 'audio');
      expect(stored['mediaDurationSeconds'], 7);

      // Best-effort cleanup of the temp recording file on a successful
      // save (`AudioEntryCubit.save()`'s `_deleteRecordingFile`).
      await waitUntilDeleted(recordingFile);
      expect(recordingFile.existsSync(), isFalse);
    },
  );

  test(
    'failure path: a non-retryable backend error (VALIDATION_ERROR) '
    'surfaces through the real pipeline as AudioError carrying '
    "Failure.message verbatim, fires exactly one request (no retry — "
    "VALIDATION_ERROR isn't one of the 6 retryable codes), never writes to "
    'the real entries Hive box, and preserves the recording file for a '
    'retried save()',
    () async {
      adapter.queueJsonResponse(400, {
        'code': 'VALIDATION_ERROR',
        'message': 'Conteúdo inválido.',
        'retryable': false,
      });

      final cubit = sl<AudioEntryCubit>();
      addTearDown(cubit.close);

      await cubit.startRecording();
      await cubit.stopRecording();
      await cubit.save();

      expect(cubit.state, isA<AudioError>());
      final errorState = cubit.state as AudioError;
      expect(errorState.message, 'Conteúdo inválido.');
      expect(errorState.text, 'Hoje foi um bom dia.');
      expect(errorState.path, recordingFile.path);
      expect(adapter.requests, hasLength(1));

      final box = sl<Box<Map>>();
      expect(box.values, isEmpty);

      // A save failure preserves the file for a retried Salvar tap — never
      // deleted on this path (`AudioEntryCubit.save()` only deletes on
      // success).
      expect(recordingFile.existsSync(), isTrue);
    },
  );
}
