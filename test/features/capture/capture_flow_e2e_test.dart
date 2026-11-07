import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/url_builder.dart';
import 'package:cerne/features/capture/presentation/cubit/text_entry_cubit.dart';

import '../../support/fake_path_provider_platform.dart';

/// Only the transport boundary is faked (`HttpClientAdapter`), same as
/// `network_pipeline_integration_test.dart` — everything above it (URL
/// building, both real interceptors, `ApiClient`'s mapping) and below it
/// (real `hive_ce` write-through) is the genuine production wiring.
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

/// End-to-end coverage for spec-3-1's capture flow, driven through the
/// real production object graph `sl` resolves for the Insertion Modal —
/// the exact `TextEntryCubit` instance `InsertionModal.show` would get
/// (`placeholder_screens.dart`'s "+" control), wired to the real
/// `EntriesRepositoryImpl` -> `EntriesRemoteDataSource` -> `ApiClient` ->
/// `Dio` (both real interceptors attached) -> a real `entries` Hive box.
/// Only the transport boundary and the native plugins (secure storage,
/// path_provider) are faked — no device/simulator/CI exists yet
/// (AGENTS.md) to do otherwise.
///
/// This complements rather than duplicates this story's existing tests:
/// `insertion_modal_test.dart`/`text_entry_cubit_test.dart` already prove
/// the UI/state-machine behavior against a fake `EntriesRepository`,
/// `entries_repository_impl_integration_test.dart` already proves the
/// real Hive write-through against a *mocked* datasource, and
/// `bootstrap_integration_test.dart` only proves the DI graph *resolves*
/// without ever exercising a save through it. None of them drives the
/// real cubit through the real network + real disk pipeline together in
/// one save, the way the app actually does on a "+" tap -> Salvar.
///
/// Driven directly against the cubit's own public API (`updateText`/
/// `save()`), not through `tester.tap`/`pumpAndSettle` on the widget tree:
/// `save()` here awaits genuine async I/O (a real Dio round trip, a real
/// Hive disk write), and `WidgetTester.pumpAndSettle()` only waits for
/// scheduled frames under the fake-async test clock — it isn't guaranteed
/// to wait for that I/O, and `runAsync` isn't a safe mix with tap/pump
/// (confirmed while drafting this suite: wrapping the tap in `runAsync`
/// broke platform-channel mocking and the request never even fired). A
/// plain `test()` driving the cubit directly sidesteps the whole fake-async
/// zone question, exactly like the other integration tests above already
/// do for their own real-I/O assertions.
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

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secureStorageChannel,
          handleSecureStorageCall,
        );
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;

    await resetCoreDependencies();
    await setupCoreDependencies();

    // Swap only the transport boundary on the real, DI-resolved Dio
    // instance — both real interceptors (header + retry) stay attached.
    adapter = _FakeHttpClientAdapter();
    sl<Dio>().httpClientAdapter = adapter;

    // `entries-create` is a bearer-required operation (not in
    // HeaderInterceptor.anonKeyOnlyFunctions) — seed a user access token
    // through the real AccessTokenProvider (backed by the faked secure
    // storage channel above) so the real header interceptor has one to
    // send.
    await sl<AccessTokenProvider>().saveAccessToken('e2e-test-access-token');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    fakeNativeStorage.clear();
    await Hive.close();
    await resetCoreDependencies();
    await fakePathProvider.cleanUp();
  });

  test('happy path: driving the real, DI-resolved TextEntryCubit through '
      'updateText + save() fires a genuine POST to entries-create with the '
      'right URL/headers/body, emits TextEntrySaved, and the entry really '
      'lands in the real entries Hive box', () async {
    adapter.queueJsonResponse(200, {
      'data': {
        'id': 'e2e-entry-1',
        'content': 'Hoje foi um bom dia.',
        'source': 'manual',
        'chatMessageId': null,
        'occurredAt': '2026-01-01T00:00:00Z',
        'serverRevision': 1,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      },
    });

    // The exact factory resolution `placeholder_screens.dart`'s "+"
    // control performs (Boundaries: a fresh instance per "+" tap).
    final cubit = sl<TextEntryCubit>();
    addTearDown(cubit.close);

    cubit.updateText('Hoje foi um bom dia.');
    await cubit.save();

    expect(cubit.state, isA<TextEntrySaved>());

    // Exactly one real request left through the fake transport, built
    // by the real UrlBuilder/HeaderInterceptor, not a mock of ApiClient.
    expect(adapter.requests, hasLength(1));
    final sent = adapter.requests.single;
    expect(sent.path, sl<UrlBuilder>().build('entries-create'));
    expect(sent.data, {'content': 'Hoje foi um bom dia.', 'source': 'manual'});
    expect(sent.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
    expect(sent.headers['Authorization'], 'Bearer e2e-test-access-token');

    // The real write-through happened against the real Hive box.
    final box = sl<Box<Map>>();
    final stored = box.get('e2e-entry-1');
    expect(stored, isNotNull);
    expect(stored!['content'], 'Hoje foi um bom dia.');
    expect(stored['source'], 'manual');
  });

  test('failure path: a non-retryable backend error (VALIDATION_ERROR) '
      'surfaces through the real pipeline as TextEntryError carrying '
      "Failure.message verbatim, fires exactly one request (no retry — "
      "VALIDATION_ERROR isn't one of the 6 retryable codes), and never "
      'writes to the real entries Hive box', () async {
    adapter.queueJsonResponse(400, {
      'code': 'VALIDATION_ERROR',
      'message': 'Conteúdo inválido.',
      'retryable': false,
    });

    final cubit = sl<TextEntryCubit>();
    addTearDown(cubit.close);

    cubit.updateText('Hoje foi um bom dia.');
    await cubit.save();

    expect(cubit.state, isA<TextEntryError>());
    expect((cubit.state as TextEntryError).message, 'Conteúdo inválido.');
    expect(adapter.requests, hasLength(1));

    final box = sl<Box<Map>>();
    expect(box.values, isEmpty);
  });
}
