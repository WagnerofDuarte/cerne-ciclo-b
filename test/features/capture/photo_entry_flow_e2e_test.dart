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
import 'package:cerne/features/capture/domain/services/photo_picker.dart';
import 'package:cerne/features/capture/presentation/cubit/photo_entry_cubit.dart';

import '../../support/fake_path_provider_platform.dart';

/// Only the transport boundary is faked (`HttpClientAdapter`), same
/// convention as `capture_flow_e2e_test.dart`'s/`audio_entry_flow_e2e_test.
/// dart`'s own adapter.
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

/// A fixed-outcome `PhotoPicker` test double — `photo_entry_cubit_test.
/// dart` already covers every pick/cancel branch against a mocktail mock;
/// this one only needs to get the real, DI-resolved `PhotoEntryCubit` from
/// `PhotoIdle` into `PhotoProcessing` with a real file on disk, so this
/// suite's own tests can exercise the real `media-ocr`/`entries-create`
/// network pipeline, same as `audio_entry_flow_e2e_test.dart` does for
/// `AudioEntryCubit`'s `MicRecorder`/`AudioTranscriber`. Swapped into the
/// real `sl` container *before* `PhotoEntryCubit` is ever resolved, so the
/// real `image_picker`-backed `ImagePickerPhotoPicker` singleton
/// `capture_injection.dart` would otherwise register — and the native
/// `image_picker` plugin behind it — is never built, let alone exercised
/// (no device/simulator exists yet, AGENTS.md).
class _FakePhotoPicker implements PhotoPicker {
  _FakePhotoPicker(this.path, this.mimeType);

  final String path;
  final String mimeType;

  @override
  Future<PickedPhoto?> pickFromCamera() async =>
      PickedPhoto(path: path, mimeType: mimeType);

  @override
  Future<PickedPhoto?> pickFromGallery() async =>
      PickedPhoto(path: path, mimeType: mimeType);
}

/// End-to-end coverage for spec-3-3's pick -> OCR -> save pipeline —
/// complements rather than duplicates `photo_entry_cubit_test.dart`
/// (mocked `PhotoPicker`/`MediaRepository`/`EntriesRepository`, covers
/// every cubit state transition) by driving the real, DI-resolved
/// `PhotoEntryCubit` through the real `MediaRepositoryImpl` ->
/// `MediaRemoteDataSource` -> `ApiClient` -> `Dio` (both real interceptors
/// attached) for OCR, and through the real `EntriesRepositoryImpl` ->
/// `EntriesRemoteDataSource` -> `ApiClient` -> `Dio` -> a real `entries`
/// Hive box for the save, exactly like `capture_flow_e2e_test.dart`/
/// `audio_entry_flow_e2e_test.dart` already prove for `TextEntryCubit`/
/// `AudioEntryCubit`.
///
/// Only three things are faked: the transport boundary
/// (`HttpClientAdapter`, same as the sibling suites), the native plugins
/// (secure storage, path_provider), and `PhotoPicker` itself (per the
/// "Never" boundary above — no automated test exercises the real
/// `image_picker` native plugin).
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
  late File photoFile;
  late Uint8List photoBytes;

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

    // Both `media-ocr` and `entries-create` are bearer-required
    // operations — seed a user access token through the real
    // AccessTokenProvider (backed by the faked secure storage channel
    // above) so the real header interceptor has one to send.
    await sl<AccessTokenProvider>().saveAccessToken('e2e-test-access-token');

    // A real file on disk — `PhotoEntryCubit` deletes it once it's done
    // with it (success or abandonment), so the tests below can assert
    // that cleanup genuinely happened (or didn't, on a save failure).
    photoBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01]);
    photoFile = File(
      '${Directory.systemTemp.path}/photo_entry_flow_e2e_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync(photoBytes);

    // Registered *before* `sl<PhotoEntryCubit>()` is ever resolved below,
    // so the real `image_picker`-backed singleton `registerCaptureFeature()`
    // wired is never built.
    sl.unregister<PhotoPicker>();
    sl.registerLazySingleton<PhotoPicker>(
      () => _FakePhotoPicker(photoFile.path, 'image/jpeg'),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    fakeNativeStorage.clear();
    await Hive.close();
    await resetCoreDependencies();
    await fakePathProvider.cleanUp();
    if (photoFile.existsSync()) {
      photoFile.deleteSync();
    }
  });

  Future<void> waitUntilDeleted(File file) async {
    for (var i = 0; i < 50 && file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'happy path: driving the real, DI-resolved PhotoEntryCubit through '
    'pickFromCamera() (fake PhotoPicker) fires a genuine POST to media-ocr '
    'with the base64-encoded image, then save() fires a genuine POST to '
    'entries-create with the right URL/headers/body (source: photo), '
    'emits PhotoSaved, the entry really lands in the real entries Hive '
    'box, and the temp photo file is deleted',
    () async {
      adapter.queueJsonResponse(200, {
        'data': {'text': 'Reunião às 10h.', 'confidence': 'high'},
      });
      adapter.queueJsonResponse(200, {
        'data': {
          'id': 'e2e-photo-entry-1',
          'content': 'Reunião às 10h.',
          'source': 'photo',
          'chatMessageId': null,
          'occurredAt': '2026-01-01T00:00:00Z',
          'serverRevision': 1,
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
        },
      });

      // The exact factory resolution `placeholder_screens.dart`'s "+"
      // control performs (Boundaries: a fresh instance per "+" tap).
      final cubit = sl<PhotoEntryCubit>();
      addTearDown(cubit.close);

      await cubit.pickFromCamera();

      expect(cubit.state, isA<PhotoRecognized>());
      expect((cubit.state as PhotoRecognized).text, 'Reunião às 10h.');

      await cubit.save();

      expect(cubit.state, isA<PhotoSaved>());

      // Exactly two real requests left through the fake transport, built
      // by the real UrlBuilder/HeaderInterceptor, not a mock of ApiClient.
      expect(adapter.requests, hasLength(2));

      final ocrRequest = adapter.requests[0];
      expect(ocrRequest.path, sl<UrlBuilder>().build('media-ocr'));
      expect(ocrRequest.data, {
        'image': base64Encode(photoBytes),
        'mimeType': 'image/jpeg',
      });
      expect(ocrRequest.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
      expect(
        ocrRequest.headers['Authorization'],
        'Bearer e2e-test-access-token',
      );

      final createRequest = adapter.requests[1];
      expect(createRequest.path, sl<UrlBuilder>().build('entries-create'));
      expect(createRequest.data, {
        'content': 'Reunião às 10h.',
        'source': 'photo',
      });
      expect(createRequest.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
      expect(
        createRequest.headers['Authorization'],
        'Bearer e2e-test-access-token',
      );

      // The real write-through happened against the real Hive box.
      final box = sl<Box<Map>>();
      final stored = box.get('e2e-photo-entry-1');
      expect(stored, isNotNull);
      expect(stored!['content'], 'Reunião às 10h.');
      expect(stored['source'], 'photo');

      // Best-effort cleanup of the temp photo file on a successful save
      // (`PhotoEntryCubit._save()`'s `_deletePickedFile`).
      await waitUntilDeleted(photoFile);
      expect(photoFile.existsSync(), isFalse);
    },
  );

  test(
    'OCR_NO_TEXT recovery path: a real media-ocr failure surfaces as '
    'PhotoError(kind: ocrNoText), and saveWithoutText() then fires a '
    'genuine second POST to entries-create with the fixed placeholder '
    'content, emits PhotoSaved, the placeholder entry really lands in '
    'the real entries Hive box, and the temp photo file is deleted',
    () async {
      adapter.queueJsonResponse(400, {
        'code': 'OCR_NO_TEXT',
        'message': 'Não foi possível reconhecer texto na imagem.',
        'retryable': false,
      });
      adapter.queueJsonResponse(200, {
        'data': {
          'id': 'e2e-photo-entry-2',
          'content': 'Registro fotográfico (sem texto reconhecido)',
          'source': 'photo',
          'chatMessageId': null,
          'occurredAt': '2026-01-01T00:00:00Z',
          'serverRevision': 1,
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
        },
      });

      final cubit = sl<PhotoEntryCubit>();
      addTearDown(cubit.close);

      await cubit.pickFromCamera();

      expect(cubit.state, isA<PhotoError>());
      final errorState = cubit.state as PhotoError;
      expect(errorState.kind, PhotoErrorKind.ocrNoText);
      expect(errorState.message, 'Não foi possível reconhecer texto na imagem.');
      expect(errorState.text, isNull);

      await cubit.saveWithoutText();

      expect(cubit.state, isA<PhotoSaved>());
      expect(adapter.requests, hasLength(2));

      final createRequest = adapter.requests[1];
      expect(createRequest.path, sl<UrlBuilder>().build('entries-create'));
      expect(createRequest.data, {
        'content': 'Registro fotográfico (sem texto reconhecido)',
        'source': 'photo',
      });

      final box = sl<Box<Map>>();
      final stored = box.get('e2e-photo-entry-2');
      expect(stored, isNotNull);
      expect(stored!['content'], 'Registro fotográfico (sem texto reconhecido)');

      await waitUntilDeleted(photoFile);
      expect(photoFile.existsSync(), isFalse);
    },
  );

  test(
    'save failure path: OCR succeeds but a non-retryable backend error '
    '(VALIDATION_ERROR) on the real entries-create call surfaces as '
    'PhotoError(kind: generic) carrying Failure.message verbatim, fires '
    'exactly two requests (no retry), never writes to the real entries '
    'Hive box, and preserves the photo file for a retried save()',
    () async {
      adapter.queueJsonResponse(200, {
        'data': {'text': 'Reunião às 10h.', 'confidence': 'high'},
      });
      adapter.queueJsonResponse(400, {
        'code': 'VALIDATION_ERROR',
        'message': 'Conteúdo inválido.',
        'retryable': false,
      });

      final cubit = sl<PhotoEntryCubit>();
      addTearDown(cubit.close);

      await cubit.pickFromCamera();
      await cubit.save();

      expect(cubit.state, isA<PhotoError>());
      final errorState = cubit.state as PhotoError;
      expect(errorState.kind, PhotoErrorKind.generic);
      expect(errorState.message, 'Conteúdo inválido.');
      expect(errorState.text, 'Reunião às 10h.');
      expect(errorState.path, photoFile.path);
      expect(adapter.requests, hasLength(2));

      final box = sl<Box<Map>>();
      expect(box.values, isEmpty);

      // A save failure preserves the file for a retried Salvar tap —
      // never deleted on this path (`PhotoEntryCubit._save()` only
      // deletes on success).
      expect(photoFile.existsSync(), isTrue);
    },
  );
}
