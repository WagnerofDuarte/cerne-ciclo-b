import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/retry_interceptor.dart';
import 'package:cerne/core/network/url_builder.dart';
import 'package:cerne/features/account/domain/repositories/account_settings_repository.dart';
import 'package:cerne/features/account/presentation/cubit/account_settings_cubit.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/chat/chat_injection.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same shape as `dashboard_flow_e2e_test.dart`'s/`export_flow_e2e_test.
/// dart`'s own fake — only the transport boundary is faked, everything
/// above it (URL building, both real interceptors, `ApiClient`'s mapping,
/// `AccountSettingsDto`'s decode) is the genuine production wiring.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<({int statusCode, Map<String, dynamic> body})> _queue = [];

  void queueJsonResponse(int statusCode, Map<String, dynamic> body) {
    _queue.add((statusCode: statusCode, body: body));
  }

  void queueErrorResponse(String code, String message) {
    final status = switch (code) {
      'VALIDATION_ERROR' => 400,
      'NETWORK_TIMEOUT' => 504,
      _ => 500,
    };
    queueJsonResponse(status, {
      'code': code,
      'message': message,
      'retryable': RetryInterceptor.retryableCodes.contains(code),
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

/// `account-settings-update`'s own `data` shape (`openapi.yaml:1764-1803`)
/// — same fixture precedent `account_remote_data_source_test.dart`'s own
/// `_settingsBody` already sets; `persona`/`id`/etc. are present (the
/// contract's own `required` list) but undecoded by `AccountSettingsDto`
/// (Code Map).
Map<String, dynamic> _settingsJson({
  bool biometricEnabled = true,
  String displayName = 'Alguém',
  String email = 'a@b.com',
}) => {
  'data': {
    'id': 'u1',
    'email': email,
    'displayName': displayName,
    'persona': 'empatico',
    'biometricEnabled': biometricEnabled,
    'serverRevision': 1,
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  },
};

/// End-to-end coverage for Story 2.4's biometric toggle plus spec-8-3's
/// profile-name editing, driven through the real production object graph
/// `sl` resolves for `AccountSettingsScreen`/`app_router.dart` — the real
/// `AccountSettingsRepositoryImpl` through `AccountRemoteDataSource`,
/// `ApiClient` and `Dio` (both real interceptors attached) down to this
/// faked transport boundary only. No device/simulator/CI exists yet
/// (AGENTS.md).
///
/// Complements rather than duplicates existing coverage:
/// `account_settings_repository_impl_test.dart` already proves every I/O-
/// matrix transition (including the generation guards) against a *mocked*
/// `AccountRemoteDataSource` (no real URL building, headers, retry policy
/// or DTO decoding involved), and `account_remote_data_source_test.dart`
/// proves the DTO mapping against a *mocked* `ApiClient`. Neither drives a
/// real `account-settings-update` round trip — real URL building, real
/// headers, the real `RetryInterceptor` policy, the real
/// `AccountSettingsDto.fromJson()` mapping off a real decoded JSON payload
/// — nor proves that `setDisplayName`'s "the response's echo wins, not the
/// locally-sent name" review patch actually survives a real backend-side
/// normalization.
///
/// Driven directly against `AccountSettingsRepository`'s own public API,
/// not through `tester.tap`/`pumpAndSettle`: each call awaits a genuine
/// async `dio` round trip, same rationale `dashboard_flow_e2e_test.dart`
/// already documents for its own cubits.
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
    // setupCoreDependencies() also wires the entries feature, which opens a
    // Hive box (via Hive.initFlutter()) eagerly at registration time, not
    // lazily on first resolution — same rationale `dashboard_flow_e2e_test.
    // dart`'s own setUp already gives, even though this suite never touches
    // entries itself.
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;

    await resetCoreDependencies();
    await setupCoreDependencies();

    adapter = _FakeHttpClientAdapter();
    sl<Dio>().httpClientAdapter = adapter;

    // account-settings-update is a bearer-required operation — seed a user
    // access token through the real AccessTokenProvider so the real header
    // interceptor has one to send.
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

  test(
    'happy path: fetchBiometricEnabled() fires a genuine PATCH to '
    'account-settings-update with an empty body and real headers, decoding '
    'a real JSON payload into biometricEnabled/displayName/email '
    '(Boundaries: "called empty to read")',
    () async {
      adapter.queueJsonResponse(
        200,
        _settingsJson(
          biometricEnabled: false,
          displayName: 'Ana Silva',
          email: 'ana@example.com',
        ),
      );

      final repository = sl<AccountSettingsRepository>();
      final result = await repository.fetchBiometricEnabled();

      expect(result.isRight(), isTrue);
      expect(repository.currentBiometricEnabled, isFalse);
      expect(repository.currentDisplayName, 'Ana Silva');
      expect(repository.currentEmail, 'ana@example.com');

      final request = adapter.requests.single;
      expect(request.path, sl<UrlBuilder>().build('account-settings-update'));
      expect(request.method, 'PATCH');
      expect(request.data, <String, dynamic>{});
      expect(request.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
      expect(request.headers['Authorization'], 'Bearer e2e-test-access-token');
    },
  );

  test(
    'setBiometricEnabled(true) fires a genuine PATCH to '
    'account-settings-update with exactly {"biometricEnabled": true} and '
    'real headers',
    () async {
      adapter.queueJsonResponse(200, _settingsJson(biometricEnabled: true));

      final repository = sl<AccountSettingsRepository>();
      final result = await repository.setBiometricEnabled(true);

      expect(result.isRight(), isTrue);
      expect(repository.currentBiometricEnabled, isTrue);

      final request = adapter.requests.single;
      expect(request.path, sl<UrlBuilder>().build('account-settings-update'));
      expect(request.data, {'biometricEnabled': true});
      expect(request.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
      expect(request.headers['Authorization'], 'Bearer e2e-test-access-token');
    },
  );

  group('spec-8-3 — setDisplayName', () {
    test(
      'happy path: fires a genuine PATCH to account-settings-update with '
      'exactly {"displayName": name} and real headers, setting '
      'currentDisplayName from the real decoded response',
      () async {
        adapter.queueJsonResponse(
          200,
          _settingsJson(displayName: 'Ana Souza'),
        );

        final repository = sl<AccountSettingsRepository>();
        final result = await repository.setDisplayName('Ana Souza');

        expect(result.isRight(), isTrue);
        expect(repository.currentDisplayName, 'Ana Souza');

        final request = adapter.requests.single;
        expect(
          request.path,
          sl<UrlBuilder>().build('account-settings-update'),
        );
        expect(request.data, {'displayName': 'Ana Souza'});
        expect(request.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
        expect(
          request.headers['Authorization'],
          'Bearer e2e-test-access-token',
        );
      },
    );

    test(
      'code-review patch, proved for real: when the backend\'s own echoed '
      'displayName differs from the locally-sent name (e.g. server-side '
      'trimming/normalization), currentDisplayName takes the response\'s '
      'value, never the locally-sent one',
      () async {
        // Sends "  Ana Souza  " but the backend echoes back a normalized,
        // trimmed value — the real decode path, not a hand-written fake,
        // is what currentDisplayName must reflect.
        adapter.queueJsonResponse(
          200,
          _settingsJson(displayName: 'Ana Souza'),
        );

        final repository = sl<AccountSettingsRepository>();
        await repository.setDisplayName('  Ana Souza  ');

        expect(repository.currentDisplayName, 'Ana Souza');
      },
    );

    test(
      'a non-retryable VALIDATION_ERROR (e.g. a name over the contract\'s '
      '80-char maxLength) maps through the real Failure.fromCode pipeline '
      'to a Left(Validation) — exactly one request left, no '
      'RetryInterceptor retry',
      () async {
        adapter.queueErrorResponse('VALIDATION_ERROR', 'nome muito longo');

        final repository = sl<AccountSettingsRepository>();
        final result = await repository.setDisplayName('A' * 81);

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<Validation>()),
          (_) => fail('expected Left'),
        );
        expect(adapter.requests, hasLength(1));
      },
    );

    test(
      'a retryable NETWORK_TIMEOUT exhausts the real RetryInterceptor\'s '
      'retries (1 + maxRetries requests, same policy the dashboard/export '
      'e2e suites already prove for their own functions) before surfacing '
      'as a Left',
      () async {
        for (var i = 0; i <= RetryInterceptor.maxRetries; i++) {
          adapter.queueErrorResponse('NETWORK_TIMEOUT', 'Tempo esgotado');
        }

        final repository = sl<AccountSettingsRepository>();
        final result = await repository.setDisplayName('Ana Souza');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<NetworkTimeout>()),
          (_) => fail('expected Left'),
        );
        expect(adapter.requests, hasLength(1 + RetryInterceptor.maxRetries));
      },
    );

    test(
      'a response missing a required field (e.g. "email") maps through the '
      'real AccountRemoteDataSource try/catch and AccountSettingsDto\'s '
      'generated fromJson to a Left(MalformedResponse), never a crash — '
      'the local decode-failure path, not Failure.fromCode',
      () async {
        adapter.queueJsonResponse(200, {
          'data': {
            'id': 'u1',
            'displayName': 'Ana Souza',
            // 'email' deliberately omitted.
            'persona': 'empatico',
            'biometricEnabled': true,
            'serverRevision': 1,
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
          },
        });

        final repository = sl<AccountSettingsRepository>();
        final result = await repository.setDisplayName('Ana Souza');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<MalformedResponse>()),
          (_) => fail('expected Left'),
        );
      },
    );
  });

  // Story 8.4 — closes spec-8-4-logout.md's own deferred Review Finding:
  // "No real-DI (sl<...>-resolved) e2e test exists yet for the logout
  // orchestration end-to-end ... revisit there [this file] or as a
  // follow-up." The existing fakes-based router test
  // (`pumpWithLogoutFakesAndVaultGate` in `account_settings_screen_test.
  // dart`) already proves the lock-before-redirect widget-tree ordering;
  // this group instead drives the real `sl`-resolved `AccountSettingsCubit`
  // directly (same "call the public API, not tester.tap" rationale this
  // file's own doc gives), proving the genuine `auth-logout` POST, real
  // headers, and the real cross-repository cache-clear orchestration all
  // fire together.
  group('Story 8.4 — logout', () {
    test(
      'happy path: logout() locks the vault synchronously (before the '
      'queued backend response ever resolves), fires a genuine POST to '
      'auth-logout with real headers, clears the stored session, flips '
      'SessionStatus to unauthenticated, and empties both the entries '
      'and chat Hive boxes',
      () async {
        adapter.queueJsonResponse(200, {
          'data': {'ok': true},
        });

        final vaultRepository = sl<VaultRepository>();
        final sessionRepository = sl<SessionRepository>();
        final entriesBox = sl<Box<Map>>();
        final chatSessionsBox = sl<Box<Map>>(
          instanceName: chatSessionsBoxName,
        );
        final chatMessagesBox = sl<Box<Map>>(
          instanceName: chatMessagesBoxName,
        );

        // Seed the state logout must actually change: an unlocked vault,
        // an authenticated session, and non-empty caches in every box —
        // first-ever submitPin() unlocks unconditionally (VaultRepository
        // doc), markAuthenticated() is the same sync in-memory flip a real
        // login already triggers.
        await vaultRepository.submitPin('1234');
        sessionRepository.markAuthenticated();
        await entriesBox.put('e1', {'id': 'e1'});
        await chatSessionsBox.put('s1', {'id': 's1'});
        await chatMessagesBox.put('m1', {'id': 'm1'});

        expect(vaultRepository.currentStatus, VaultStatus.unlocked);
        expect(sessionRepository.currentStatus, SessionStatus.authenticated);

        final cubit = sl<AccountSettingsCubit>();
        final logoutFuture = cubit.logout();

        // Boundaries: VaultRepository.lock() fires synchronously, BEFORE
        // the await on SessionRepository.logout() — true the instant
        // control returns here, before the queued network response has
        // had any chance to resolve.
        expect(vaultRepository.currentStatus, VaultStatus.locked);

        await logoutFuture;

        final request = adapter.requests.single;
        expect(request.path, sl<UrlBuilder>().build('auth-logout'));
        expect(request.method, 'POST');
        expect(request.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
        expect(
          request.headers['Authorization'],
          'Bearer e2e-test-access-token',
        );

        expect(await sl<AccessTokenProvider>().readAccessToken(), isNull);
        expect(sessionRepository.currentStatus, SessionStatus.unauthenticated);
        expect(entriesBox.isEmpty, isTrue);
        expect(chatSessionsBox.isEmpty, isTrue);
        expect(chatMessagesBox.isEmpty, isTrue);
        expect(cubit.state.isLoggingOut, isFalse);
      },
    );

    test(
      'backend failure (auth-logout returns a non-retryable error): the '
      'local session still clears, the vault still locks, both caches '
      'still empty, and isLoggingOut still resets — no error ever '
      'surfaced (Boundaries: "local session already ended regardless" / '
      '"Never: surfacing a backend-logout-failure error")',
      () async {
        adapter.queueErrorResponse('VALIDATION_ERROR', 'ignored');

        final vaultRepository = sl<VaultRepository>();
        final sessionRepository = sl<SessionRepository>();
        final entriesBox = sl<Box<Map>>();
        final chatSessionsBox = sl<Box<Map>>(
          instanceName: chatSessionsBoxName,
        );

        await vaultRepository.submitPin('1234');
        sessionRepository.markAuthenticated();
        await entriesBox.put('e1', {'id': 'e1'});
        await chatSessionsBox.put('s1', {'id': 's1'});

        final cubit = sl<AccountSettingsCubit>();
        await cubit.logout();

        expect(vaultRepository.currentStatus, VaultStatus.locked);
        expect(sessionRepository.currentStatus, SessionStatus.unauthenticated);
        expect(await sl<AccessTokenProvider>().readAccessToken(), isNull);
        expect(entriesBox.isEmpty, isTrue);
        expect(chatSessionsBox.isEmpty, isTrue);
        expect(cubit.state.isLoggingOut, isFalse);
        expect(cubit.state.errorMessage, isNull);
        expect(cubit.state.nameErrorMessage, isNull);
      },
    );

    test(
      'double-tap: calling logout() again while the first call is still '
      'in flight no-ops — exactly one auth-logout request fires '
      '(I/O matrix: "Double-tap Sair -> second tap no-ops")',
      () async {
        adapter.queueJsonResponse(200, {
          'data': {'ok': true},
        });

        final cubit = sl<AccountSettingsCubit>();
        final first = cubit.logout();
        final second = cubit.logout();

        await Future.wait([first, second]);

        expect(adapter.requests, hasLength(1));
      },
    );
  });
}
