import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../features/account/account_injection.dart';
import '../../features/auth/auth_injection.dart';
import '../../features/capture/capture_injection.dart';
import '../../features/chat/chat_injection.dart';
import '../../features/dashboard/dashboard_injection.dart';
import '../../features/entries/entries_injection.dart';
import '../../features/export/export_injection.dart';
import '../../features/vault/vault_injection.dart';
import '../network/access_token_provider.dart';
import '../network/api_client.dart';
import '../network/header_interceptor.dart';
import '../network/retry_interceptor.dart';
import '../network/url_builder.dart';
import '../session/session_expiry_notifier.dart';

/// The project's single `get_it` instance — exactly one DI container exists
/// (architecture spine). Every feature's `registerXFeature()` registers
/// through this same `sl`, never a second container.
final sl = GetIt.instance;

/// Bootstraps core infrastructure: loads `.env`, then registers
/// `FlutterSecureStorage`, `Dio` (configured with the header + retry
/// interceptors) and `ApiClient` through `sl` — the `dio` +
/// `flutter_secure_storage` + `get_it` integration spike this story proves
/// before anything else is built on top of it.
Future<void> setupCoreDependencies() async {
  await dotenv.load(fileName: '.env');

  final functionsBaseUrl = dotenv.get('FUNCTIONS_BASE_URL');
  final supabaseAnonKey = dotenv.get('SUPABASE_ANON_KEY');

  sl.registerLazySingleton<FlutterSecureStorage>(
    () => const FlutterSecureStorage(),
  );

  sl.registerLazySingleton<AccessTokenProvider>(
    () => SecureStorageAccessTokenProvider(sl<FlutterSecureStorage>()),
  );

  sl.registerLazySingleton<UrlBuilder>(() => UrlBuilder(functionsBaseUrl));

  // Story 1.5 — `dispose:` wires `SessionExpiryNotifier.dispose()` into
  // `get_it`'s own reset lifecycle, same rationale as `SessionRepository`'s
  // own registration below. Registration order here is cosmetic, not
  // load-bearing: `registerLazySingleton` only builds its instance on first
  // `sl<T>()` access, so `ApiClient`'s factory can resolve this dependency
  // correctly regardless of which of the two is registered first.
  sl.registerLazySingleton<SessionExpiryNotifier>(
    () => SessionExpiryNotifierImpl(),
    dispose: (notifier) => notifier.dispose(),
  );

  sl.registerLazySingleton<Dio>(() {
    final dio = Dio(
      BaseOptions(
        // Design note (docs/input is silent on exact numbers): a stalled
        // connection must still fail instead of hanging indefinitely.
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    dio.interceptors.add(
      HeaderInterceptor(
        anonKey: supabaseAnonKey,
        accessTokenProvider: sl<AccessTokenProvider>(),
      ),
    );
    dio.interceptors.add(RetryInterceptor(dio));
    return dio;
  });

  sl.registerLazySingleton<ApiClient>(
    () => ApiClient(
      dio: sl<Dio>(),
      urlBuilder: sl<UrlBuilder>(),
      sessionExpiryNotifier: sl<SessionExpiryNotifier>(),
    ),
  );

  registerAuthFeature();
  registerVaultFeature();
  registerAccountFeature();

  // Story 3.1 — the app's first `hive_ce` usage: `initFlutter()` must
  // complete before `registerEntriesFeature()` opens its box (Code Map).
  await Hive.initFlutter();
  await registerEntriesFeature();
  registerCaptureFeature();
  // spec-6-1 — `registerChatFeature()` opens its own two Hive boxes, same
  // `Hive.initFlutter()`-must-run-first requirement `registerEntriesFeature()`
  // already documents for itself.
  await registerChatFeature();
  // spec-7-1 — no Hive box of its own (AD-15: export jobs are never
  // persisted locally), so unlike the call above this one needs no
  // `Hive.initFlutter()` ordering and isn't `async`.
  registerExportFeature();
  // spec-8-1 — called after `registerEntriesFeature()` above, since
  // `DashboardCubit` depends on the `PendingEntryWriteTracker` that
  // registration provides (Code Map); every registration involved is
  // `registerLazySingleton`, though, so this call order isn't itself
  // load-bearing (review finding, `dashboard_injection.dart`'s own doc
  // comment) — `PendingEntryWriteTracker` is only resolved lazily, on
  // first use. No Hive box of its own either (Boundaries/Never: "cache
  // the aggregate", AD-15 exclusion), so this isn't `async` either.
  registerDashboardFeature();
}

/// Test/teardown helper — resets the single `get_it` instance so each test
/// bootstraps its own clean registrations.
Future<void> resetCoreDependencies() => sl.reset();
