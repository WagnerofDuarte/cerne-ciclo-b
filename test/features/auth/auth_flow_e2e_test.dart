import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/url_builder.dart';
import 'package:cerne/core/resource.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/auth/presentation/cubit/auth_cubit.dart';

import '../../support/fake_path_provider_platform.dart';

/// Same transport-boundary-only fake every other `*_flow_e2e_test.dart`
/// uses (`capture_flow_e2e_test.dart`, `chat_flow_e2e_test.dart`, ...).
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

/// `auth-signup`/`auth-login`'s own response `data` shape
/// (`AuthResponseDto.fromJson`) — mirrors `auth_repository_impl_test.dart`'s
/// own fixture.
Map<String, dynamic> _authResponseJson({
  required String userId,
  required String email,
  required String accessToken,
  required String refreshToken,
}) => {
  'data': {
    'session': {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresIn': 3600,
      'expiresAt': 1999999999,
      'tokenType': 'bearer',
    },
    'user': {'id': userId, 'email': email},
  },
};

/// End-to-end coverage for spec-1-3's account creation/login flow, driven
/// through the real production object graph `sl` resolves for Tela 0.1a —
/// the exact `AuthCubit` instance `AuthScreen` would get, wired to the real
/// `AuthRepositoryImpl` -> `AuthRemoteDataSource` -> `ApiClient` -> `Dio`
/// (both real interceptors attached) -> the real `flutter_secure_storage`
/// channel, plus the real `SessionRepository` singleton `submit()`'s
/// success branch calls into (Story 1.6's `markAuthenticated()` boundary).
/// Only the transport boundary and the native plugins (secure storage,
/// path_provider) are faked — no device/simulator/CI exists yet
/// (AGENTS.md).
///
/// Complements rather than duplicates `auth_cubit_test.dart` (a fake
/// `AuthRepository`/`SessionRepository`) and `auth_repository_impl_test.dart`
/// / `auth_remote_data_source_test.dart` (a mocked `ApiClient`): none of
/// them proves a real `auth-signup`/`auth-login` POST — built by the real
/// `UrlBuilder`, carrying the real anon-key-as-bearer header
/// `HeaderInterceptor.anonKeyOnlyFunctions` applies to exactly these two
/// functions (AGENTS.md) — actually lands the session pair in the real
/// secure-storage channel and flips the real `SessionRepository.
/// statusStream` to `authenticated`, all in one `submit()` call.
///
/// Driven directly against `AuthCubit`'s own public API (`emailChanged`/
/// `passwordChanged`/`submit`), not through `tester.tap`/`pumpAndSettle` —
/// same rationale `capture_flow_e2e_test.dart` documents: `submit()` awaits
/// genuine async I/O (a real Dio round trip over a faked transport, a real
/// secure-storage channel write), which `pumpAndSettle` isn't guaranteed to
/// wait for.
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
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    fakeNativeStorage.clear();
    await Hive.close();
    await resetCoreDependencies();
    await fakePathProvider.cleanUp();
  });

  test('happy path: signUp mode -> submit() fires a genuine POST to '
      'auth-signup carrying the anon key as both apikey and Authorization '
      'bearer (never a user token — this function has security: [] in '
      'the contract), persists the session pair to the real secure-'
      'storage channel, flips the real SessionRepository.statusStream to '
      'authenticated BEFORE AuthCubit emits its own success state, and '
      'clears the typed password', () async {
    adapter.queueJsonResponse(
      200,
      _authResponseJson(
        userId: 'user-1',
        email: 'wagner@cerne.app',
        accessToken: 'e2e-access-token',
        refreshToken: 'e2e-refresh-token',
      ),
    );

    final sessionRepository = sl<SessionRepository>();
    final statuses = <SessionStatus>[];
    final subscription = sessionRepository.statusStream.listen(statuses.add);
    expect(sessionRepository.currentStatus, isNull);

    final cubit = sl<AuthCubit>();
    cubit.toggleMode();
    cubit.emailChanged('wagner@cerne.app');
    cubit.passwordChanged('segredo123');

    await cubit.submit();

    expect(cubit.state.status, isA<ResourceData<Unit>>());
    expect(cubit.state.password, '');
    expect(cubit.state.formError, isNull);

    expect(adapter.requests, hasLength(1));
    final sent = adapter.requests.single;
    expect(sent.path, sl<UrlBuilder>().build('auth-signup'));
    expect(sent.data, {'email': 'wagner@cerne.app', 'password': 'segredo123'});
    expect(sent.headers['apikey'], dotenv.get('SUPABASE_ANON_KEY'));
    expect(
      sent.headers['Authorization'],
      'Bearer ${dotenv.get('SUPABASE_ANON_KEY')}',
    );

    // The real write-through happened against the real secure-storage
    // channel (AccessTokenProvider.saveSession's own two writes).
    final accessTokenProvider = sl<AccessTokenProvider>();
    expect(await accessTokenProvider.readAccessToken(), 'e2e-access-token');
    expect(await accessTokenProvider.readRefreshToken(), 'e2e-refresh-token');

    // Story 1.6 boundary: markAuthenticated() ran before submit() even
    // resolved, so the real SessionRepository singleton already reflects
    // authenticated by the time this await returns.
    expect(sessionRepository.currentStatus, SessionStatus.authenticated);
    expect(statuses, [SessionStatus.authenticated]);

    await subscription.cancel();
  });

  test('happy path: login mode -> submit() fires a genuine POST to '
      'auth-login (same anon-key-as-bearer header policy as auth-signup) '
      'and persists the same session pair through the real pipeline', () async {
    adapter.queueJsonResponse(
      200,
      _authResponseJson(
        userId: 'user-2',
        email: 'outra@cerne.app',
        accessToken: 'login-access-token',
        refreshToken: 'login-refresh-token',
      ),
    );

    final cubit = sl<AuthCubit>();
    // AuthState starts in AuthMode.login (default) — no toggleMode() call.
    cubit.emailChanged('outra@cerne.app');
    cubit.passwordChanged('outrasenha');

    await cubit.submit();

    expect(cubit.state.status, isA<ResourceData<Unit>>());

    final sent = adapter.requests.single;
    expect(sent.path, sl<UrlBuilder>().build('auth-login'));
    expect(sent.headers['Authorization'], 'Bearer ${dotenv.get('SUPABASE_ANON_KEY')}');

    final accessTokenProvider = sl<AccessTokenProvider>();
    expect(await accessTokenProvider.readAccessToken(), 'login-access-token');
    expect(
      sl<SessionRepository>().currentStatus,
      SessionStatus.authenticated,
    );
  });

  test('email is trimmed before it ever reaches the real transport — '
      'stray leading/trailing whitespace must never risk a spurious '
      'AUTH_INVALID', () async {
    adapter.queueJsonResponse(
      200,
      _authResponseJson(
        userId: 'user-3',
        email: 'trim@cerne.app',
        accessToken: 'trim-access-token',
        refreshToken: 'trim-refresh-token',
      ),
    );

    final cubit = sl<AuthCubit>();
    cubit.emailChanged('  trim@cerne.app  ');
    cubit.passwordChanged('segredo123');

    await cubit.submit();

    final sent = adapter.requests.single;
    expect(sent.data, {'email': 'trim@cerne.app', 'password': 'segredo123'});
  });

  test('failure path: a non-retryable AUTH_INVALID surfaces as formError '
      'carrying Failure.message verbatim, status returns to idle, never '
      'persists a session to the real secure-storage channel, and never '
      'flips the real SessionRepository.statusStream', () async {
    adapter.queueJsonResponse(401, {
      'code': 'AUTH_INVALID',
      'message': 'E-mail ou senha incorretos.',
      'retryable': false,
    });

    final sessionRepository = sl<SessionRepository>();
    final cubit = sl<AuthCubit>();
    cubit.emailChanged('wagner@cerne.app');
    cubit.passwordChanged('senhaerrada');

    await cubit.submit();

    expect(cubit.state.formError, 'E-mail ou senha incorretos.');
    expect(cubit.state.status, isA<ResourceIdle<Unit>>());
    expect(adapter.requests, hasLength(1));

    final accessTokenProvider = sl<AccessTokenProvider>();
    expect(await accessTokenProvider.readAccessToken(), isNull);
    expect(await accessTokenProvider.readRefreshToken(), isNull);
    expect(sessionRepository.currentStatus, isNull);
  });
}
