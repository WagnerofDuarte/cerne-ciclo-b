import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/retry_interceptor.dart';
import 'package:cerne/core/network/url_builder.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_state.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same shape as `entries_list_flow_e2e_test.dart`'s own fake — only the
/// transport boundary is faked, everything above it (URL building, both
/// real interceptors, `ApiClient`'s mapping) and below it (real `hive_ce`
/// write-through) is the genuine production wiring.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<({int statusCode, Map<String, dynamic> body})> _queue = [];

  void queueJsonResponse(int statusCode, Map<String, dynamic> body) {
    _queue.add((statusCode: statusCode, body: body));
  }

  void queueErrorResponse(String code, String message) {
    queueJsonResponse(503, {
      'code': code,
      'message': message,
      'retryable': true,
    });
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

Map<String, dynamic> _entryJson({
  required String id,
  required String content,
  required String source,
  required String occurredAt,
}) => {
  'id': id,
  'content': content,
  'source': source,
  'chatMessageId': null,
  'occurredAt': occurredAt,
  'serverRevision': 1,
  'createdAt': occurredAt,
  'updatedAt': occurredAt,
};

/// End-to-end coverage for spec-4-2's pending-write lifecycle — the
/// counterpart `entries_list_flow_e2e_test.dart` already proves for
/// spec-4-1's `list()` path. Driven directly against the exact
/// `sl<PendingEntryWriteTracker>()`/`sl<MeusRegistrosCubit>()` singleton
/// instances `entries_injection.dart` wires to share one real
/// `EntriesRepositoryImpl` -> `EntriesRemoteDataSource` -> `ApiClient` ->
/// `Dio` (both real interceptors attached) -> a real `entries` Hive box —
/// exactly how a capture cubit's `create()`/the badge's `retry()` reach
/// `MeusRegistrosCubit` in the running app.
///
/// This complements rather than duplicates existing coverage:
/// `pending_entry_write_tracker_test.dart`/`meus_registros_cubit_test.dart`/
/// `meus_registros_screen_test.dart` already prove the tracker and the
/// cubit/UI wiring against fakes. None of them drives a `create()` ->
/// retryable-failure -> manual-`retry()` -> confirmation sequence through
/// the real `RetryInterceptor` + real transport together.
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

    adapter = _FakeHttpClientAdapter();
    sl<Dio>().httpClientAdapter = adapter;

    // `entries-create` is a bearer-required operation — seed a user access
    // token through the real `AccessTokenProvider` (backed by the faked
    // secure storage channel above) so the real header interceptor has one
    // to send.
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

  test('happy path: tracker.create() fires a genuine POST to entries-create, '
      'persists the confirmed entry to the real Hive box, and the real '
      "MeusRegistrosCubit (sharing the tracker) prepends it into its loaded "
      'state via confirmedWrites', () async {
    // Starts the real MeusRegistrosCubit subscribing to the shared
    // tracker's streams before the write is created, same as the running
    // app does ("Meus Registros" mounts and subscribes for its whole
    // lifetime regardless of which screen started the capture).
    final cubit = sl<MeusRegistrosCubit>();
    adapter.queueJsonResponse(200, {
      'data': <Map<String, dynamic>>[],
      'meta': {'nextCursor': null},
    });
    await cubit.loadFirstPage();
    expect(cubit.state, isA<MeusRegistrosEmpty>());

    adapter.queueJsonResponse(200, {
      'data': _entryJson(
        id: 'entry-1',
        content: 'Primeiro registro do dia.',
        source: 'manual',
        occurredAt: '2026-01-02T10:00:00Z',
      ),
    });

    final tracker = sl<PendingEntryWriteTracker>();
    final result = await tracker.create(
      content: 'Primeiro registro do dia.',
      source: EntrySource.manual,
    );
    // The tracker's `confirmedWrites`/`pendingWrites` broadcast
    // controllers notify listeners on their own microtask, one tick
    // after `create()`'s awaited Future resolves — same convention
    // `audio_entry_cubit_test.dart` documents for this exact tracker.
    await Future<void>.delayed(Duration.zero);

    expect(result.isRight(), isTrue);
    final loaded = cubit.state as MeusRegistrosLoaded;
    expect(loaded.entries.map((e) => e.id), ['entry-1']);
    expect(loaded.pendingWrites, isEmpty);

    // Exactly one real request left through the fake transport, built by
    // the real UrlBuilder/HeaderInterceptor, not a mock of ApiClient.
    final createRequest = adapter.requests.last;
    expect(createRequest.path, sl<UrlBuilder>().build('entries-create'));
    expect(createRequest.data, {
      'content': 'Primeiro registro do dia.',
      'source': 'manual',
    });
    expect(createRequest.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
    expect(
      createRequest.headers['Authorization'],
      'Bearer e2e-test-access-token',
    );

    // The real write-through happened against the real Hive box.
    final box = sl<Box<Map>>();
    expect(box.get('entry-1')!['content'], 'Primeiro registro do dia.');
  });

  test('retryable failure then manual retry: create() exhausts the real '
      "RetryInterceptor's retries on a retryable code, surfaces as the "
      "tracker's own failed pending write (visible on MeusRegistrosCubit), "
      'and a later tracker.retry() fires a brand-new genuine POST that '
      'confirms the exact same payload', () async {
    final tracker = sl<PendingEntryWriteTracker>();
    final cubit = sl<MeusRegistrosCubit>();

    // MeusRegistrosCubit only overlays a pending write onto an already-
    // resolved state (Loaded/Empty/Error) — it stays Loading, with no
    // pending write visible, until this resolves at least once.
    adapter.queueJsonResponse(200, {
      'data': <Map<String, dynamic>>[],
      'meta': {'nextCursor': null},
    });
    await cubit.loadFirstPage();
    expect(cubit.state, isA<MeusRegistrosEmpty>());
    final baselineRequestCount = adapter.requests.length;

    // Initial attempt + RetryInterceptor.maxRetries retries, all
    // genuinely retryable (error-taxonomy.md's NETWORK_TIMEOUT) —
    // consumed entirely inside this one tracker.create() call, same as
    // `entries_list_flow_e2e_test.dart`'s offline-fallback case.
    for (var i = 0; i <= RetryInterceptor.maxRetries; i++) {
      adapter.queueErrorResponse('NETWORK_TIMEOUT', 'Tempo esgotado');
    }

    final createResult = await tracker.create(
      content: 'Áudio transcrito com falha de rede.',
      source: EntrySource.audio,
      mediaDurationSeconds: 12,
    );
    await Future<void>.delayed(Duration.zero);

    expect(createResult.isLeft(), isTrue);
    expect(
      adapter.requests,
      hasLength(baselineRequestCount + 1 + RetryInterceptor.maxRetries),
    );

    final failedWrite =
        (cubit.state as MeusRegistrosLoaded).pendingWrites.single;
    final failedStatus = failedWrite.status as PendingEntryWriteFailed;
    expect(failedStatus.failure.retryable, isTrue);
    final tempId = failedWrite.tempId;

    // The manual retry's own single real attempt succeeds this time.
    adapter.queueJsonResponse(200, {
      'data': _entryJson(
        id: 'entry-retried',
        content: 'Áudio transcrito com falha de rede.',
        source: 'audio',
        occurredAt: '2026-01-02T11:00:00Z',
      ),
    });

    await tracker.retry(tempId);
    await Future<void>.delayed(Duration.zero);

    // Exactly one new request beyond the exhausted initial attempt's
    // own 1 + maxRetries — retry() never re-runs the retry budget from
    // scratch, it's a single fresh `create()` replay.
    expect(
      adapter.requests,
      hasLength(baselineRequestCount + 1 + RetryInterceptor.maxRetries + 1),
    );
    final retryRequest = adapter.requests.last;
    expect(retryRequest.data, {
      'content': 'Áudio transcrito com falha de rede.',
      'source': 'audio',
      'mediaDurationSeconds': 12,
    });

    final loaded = cubit.state as MeusRegistrosLoaded;
    expect(loaded.entries.map((e) => e.id), ['entry-retried']);
    expect(loaded.pendingWrites, isEmpty);

    final box = sl<Box<Map>>();
    expect(box.get('entry-retried'), isNotNull);
  });

  test(
    'non-retryable failure blocks retry: create() fails once with a '
    "non-retryable code (no RetryInterceptor retries at all), and the "
    "tracker's own retry() guard is a genuine no-op — it never fires a "
    'second network call, and the failed write stays exactly as it was',
    () async {
      final tracker = sl<PendingEntryWriteTracker>();
      final cubit = sl<MeusRegistrosCubit>();

      adapter.queueJsonResponse(200, {
        'data': <Map<String, dynamic>>[],
        'meta': {'nextCursor': null},
      });
      await cubit.loadFirstPage();
      expect(cubit.state, isA<MeusRegistrosEmpty>());
      final baselineRequestCount = adapter.requests.length;

      adapter.queueJsonResponse(400, {
        'code': 'VALIDATION_ERROR',
        'message': 'Conteúdo vazio.',
        'retryable': false,
      });

      final createResult = await tracker.create(
        content: '',
        source: EntrySource.manual,
      );
      await Future<void>.delayed(Duration.zero);

      expect(createResult.isLeft(), isTrue);
      // A non-retryable code never triggers RetryInterceptor at all.
      expect(adapter.requests, hasLength(baselineRequestCount + 1));

      final failedWrite =
          (cubit.state as MeusRegistrosLoaded).pendingWrites.single;
      final failedStatus = failedWrite.status as PendingEntryWriteFailed;
      expect(failedStatus.failure.retryable, isFalse);

      await tracker.retry(failedWrite.tempId);
      await Future<void>.delayed(Duration.zero);

      // retry()'s own internal `failure.retryable` guard must have blocked
      // this — no new request left through the real transport.
      expect(adapter.requests, hasLength(baselineRequestCount + 1));
      final stillFailed =
          (cubit.state as MeusRegistrosLoaded).pendingWrites.single;
      expect(stillFailed.status, failedWrite.status);
    },
  );
}
