import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/header_interceptor.dart';
import 'package:cerne/core/network/retry_interceptor.dart';
import 'package:cerne/features/account/domain/repositories/account_settings_repository.dart';
import 'package:cerne/features/account/presentation/cubit/account_settings_cubit.dart';
import 'package:cerne/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:cerne/features/capture/domain/services/audio_transcriber.dart';
import 'package:cerne/features/capture/domain/services/mic_recorder.dart';
import 'package:cerne/features/capture/presentation/cubit/audio_entry_cubit.dart';
import 'package:cerne/features/capture/presentation/cubit/text_entry_cubit.dart';
import 'package:cerne/features/chat/chat_injection.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_cubit.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/entries/presentation/cubit/entries_search_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/entry_detail_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:cerne/features/export/presentation/cubit/export_job_cubit.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';

import '../../support/fake_path_provider_platform.dart';

/// AC4 — proves the `dio` + `flutter_secure_storage` + `get_it` integration
/// spike works together in one bootstrap, before anything else is built on
/// top of it (architecture spine's Deferred note).
///
/// No device/simulator/CI exists yet to run a true platform-channel
/// integration test (AGENTS.md's "Running and verifying" TODO), so the
/// native secure-storage channel is faked with an in-memory store here —
/// the test still exercises the *real* `FlutterSecureStorage` instance
/// resolved from the single DI container, round-tripping a write/read
/// through it exactly as AC4 requires.
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

  // Review finding: `record_pkg.AudioRecorder`'s constructor itself (not
  // just a later method call) immediately invokes this native channel —
  // `registerLazySingleton<record_pkg.AudioRecorder>(AudioRecorder.new)`
  // in `capture_injection.dart` throws `MissingPluginException` under
  // `flutter test` without this, same rationale as the secure-storage
  // channel above (no device/simulator exists yet, AGENTS.md). Nothing
  // in this file's tests actually records audio, so every method just
  // returns `null`, mirroring the secure-storage fake's own `default`.
  const recordChannel = MethodChannel('com.llfbandit.record/messages');

  // spec-6-3 — `ChatCubit`'s own constructor subscribes to
  // `ConnectivityWatcher.watch()` immediately, and `registerChatFeature()`
  // wires it to the real `connectivity_plus`-backed `ConnectivityPlusWatcher`
  // (`Connectivity()`); this test force-resolves the real `ChatCubit` below
  // (`sl<ChatCubit>()`), which would otherwise hit these two platform
  // channels with nothing registered to answer them — same rationale as
  // `recordChannel` above. The event channel is faked via its own
  // `MethodChannel` wrapper (its `listen`/`cancel` invocations use the same
  // method-call wire format), acknowledging every call with `null` since no
  // test here drives an actual connectivity change.
  const connectivityMethodChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  const connectivityEventChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );

  late FakePathProviderPlatform fakePathProvider;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secureStorageChannel,
          handleSecureStorageCall,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          connectivityMethodChannel,
          (call) async => call.method == 'check' ? <String>['wifi'] : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityEventChannel, (_) async => null);
    // Story 3.1 — `setupCoreDependencies()` now also calls
    // `Hive.initFlutter()` (transitively via `hive_ce_flutter`), which
    // asks `path_provider` for the documents directory; faked the same
    // way the secure-storage channel above is.
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;

    await resetCoreDependencies();
    await setupCoreDependencies();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityMethodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityEventChannel, null);
    fakeNativeStorage.clear();
    // Closes the `entries` Hive box opened above — `resetCoreDependencies()`
    // only resets `get_it`'s registrations, not Hive's own global box
    // registry, and `Hive.openBox` silently returns the already-open box
    // (ignoring a new path) if it isn't closed first.
    await Hive.close();
    await resetCoreDependencies();
    // Review finding: without this, every test run leaks one orphaned
    // temp folder onto the dev machine/CI runner (`FakePathProviderPlatform`
    // creates real disk directories, not an in-memory fake).
    await fakePathProvider.cleanUp();
  });

  test('exactly one get_it instance resolves Dio + FlutterSecureStorage + ApiClient', () {
    expect(sl.isRegistered<Dio>(), isTrue);
    expect(sl.isRegistered<FlutterSecureStorage>(), isTrue);
    expect(sl.isRegistered<ApiClient>(), isTrue);

    // `dio` is configured through the container: both interceptors
    // (header + retry, AD-4/AD-5) are attached to the resolved instance,
    // alongside dio's own built-in default interceptor.
    final dio = sl<Dio>();
    expect(dio.interceptors.whereType<HeaderInterceptor>(), hasLength(1));
    expect(dio.interceptors.whereType<RetryInterceptor>(), hasLength(1));

    // Resolving twice returns the same singleton — one container, one Dio.
    expect(sl<Dio>(), same(dio));
  });

  test('setupCoreDependencies also wires the auth feature (Story 1.3) — a '
      'broken registration/dependency cycle must surface here, not only at '
      'real app launch (no device/CI exists yet to catch that otherwise)', () {
    expect(sl.isRegistered<AuthRemoteDataSource>(), isTrue);
    expect(sl.isRegistered<AuthRepository>(), isTrue);
    expect(sl.isRegistered<AuthCubit>(), isTrue);

    // Actually resolves the whole chain (AuthCubit -> AuthRepository ->
    // AuthRemoteDataSource/AccessTokenProvider -> ApiClient/Dio) rather
    // than just checking the registration exists — `get_it`'s
    // `registerLazySingleton` only evaluates its factory on first
    // resolution.
    expect(() => sl<AuthCubit>(), returnsNormally);
  });

  test('setupCoreDependencies also wires the vault feature (spec-2-1, AD-14) — '
      'a broken registration (bad factory, missing LocalAuthentication '
      "dependency, broken dispose:) must surface here, not only at real app "
      'launch (no device/CI exists yet to catch that otherwise)', () {
    expect(sl.isRegistered<VaultRepository>(), isTrue);

    // Actually resolves VaultRepository -> VaultRepositoryImpl(
    // localAuthentication: sl<LocalAuthentication>()) rather than just
    // checking the registration exists. This only constructs the
    // LocalAuthentication() instance and stores it — it never calls any
    // of its methods, so no platform-channel mock is needed here (same
    // reasoning that already applies to AuthCubit's forced resolution
    // above).
    expect(() => sl<VaultRepository>(), returnsNormally);
  });

  test('setupCoreDependencies also wires the account feature (spec-2-4) — a '
      'broken registration/dependency cycle must surface here, not only at '
      'real app launch (no device/CI exists yet to catch that otherwise)', () {
    expect(sl.isRegistered<AccountSettingsRepository>(), isTrue);
    expect(sl.isRegistered<AccountSettingsCubit>(), isTrue);

    // Actually resolves the whole chain (AccountSettingsCubit ->
    // AccountSettingsRepository -> AccountRemoteDataSource -> ApiClient/
    // Dio) rather than just checking the registration exists — same
    // rationale as `AuthCubit`'s own forced resolution above.
    expect(() => sl<AccountSettingsCubit>(), returnsNormally);
  });

  test(
    'setupCoreDependencies also wires the entries + capture features '
    '(spec-3-1) — a broken registration/dependency cycle (including the '
    'Hive box open) must surface here, not only at real app launch',
    () async {
      expect(sl.isRegistered<EntriesRepository>(), isTrue);

      // Actually resolves the whole chain (EntriesRepository ->
      // EntriesRemoteDataSource/Box<Map> -> ApiClient/Dio) rather than
      // just checking the registration exists — same rationale as
      // `AuthCubit`'s own forced resolution above.
      expect(() => sl<EntriesRepository>(), returnsNormally);

      // spec-4-2 — the shared `PendingEntryWriteTracker`, resolved by
      // both `MeusRegistrosCubit` below and `registerCaptureFeature()`'s
      // own cubit factories; a broken registration order (it depends on
      // `EntriesRepository`, registered just above) must surface here.
      expect(sl.isRegistered<PendingEntryWriteTracker>(), isTrue);
      expect(() => sl<PendingEntryWriteTracker>(), returnsNormally);

      // spec-4-1 — `MeusRegistrosCubit` is a `lazySingleton` (same
      // rationale as `AccountSettingsCubit` above), not a factory.
      expect(sl.isRegistered<MeusRegistrosCubit>(), isTrue);
      expect(() => sl<MeusRegistrosCubit>(), returnsNormally);

      // spec-5-1 — `EntriesSearchCubit` is also a `lazySingleton`, same
      // rationale as `MeusRegistrosCubit` directly above.
      expect(sl.isRegistered<EntriesSearchCubit>(), isTrue);
      expect(() => sl<EntriesSearchCubit>(), returnsNormally);

      // spec-4-4 — `EntryDetailCubit` is a `factory` (reaches into
      // `SessionRepository` too, registered by the `auth` feature) — a
      // broken registration must surface here, not only at real app
      // launch navigating to `/meus-registros/:id` (review finding).
      expect(sl.isRegistered<EntryDetailCubit>(), isTrue);
      expect(() => sl<EntryDetailCubit>(), returnsNormally);

      // `TextEntryCubit` is a factory (Boundaries: "Modal open resets"),
      // not a singleton — resolving it twice must return two distinct,
      // independently closable instances.
      final first = sl<TextEntryCubit>();
      final second = sl<TextEntryCubit>();
      expect(first, isNot(same(second)));
      await first.close();
      await second.close();
    },
  );

  test(
    'setupCoreDependencies also wires spec-3-2\'s audio-capture bindings '
    '(review finding: the original diff never extended this test for the '
    'new registrations, so a broken real DI wiring — e.g. a constructor-'
    'argument-order mistake in AudioEntryCubit(...) — would only surface '
    'at real app launch, which has no automated check yet, AGENTS.md)',
    () async {
      expect(sl.isRegistered<MicRecorder>(), isTrue);
      expect(sl.isRegistered<AudioTranscriber>(), isTrue);
      expect(() => sl<MicRecorder>(), returnsNormally);
      expect(() => sl<AudioTranscriber>(), returnsNormally);

      // `AudioEntryCubit` is a factory, same rationale as `TextEntryCubit`
      // above — resolving it twice must return two distinct,
      // independently closable instances.
      final firstAudio = sl<AudioEntryCubit>();
      final secondAudio = sl<AudioEntryCubit>();
      expect(firstAudio, isNot(same(secondAudio)));
      await firstAudio.close();
      await secondAudio.close();
    },
  );

  test('setupCoreDependencies also wires the chat feature (spec-6-1) — a '
      'broken registration/dependency cycle (including the two Hive boxes) '
      'must surface here, not only at real app launch (review finding: no '
      'test anywhere else resolves the real registered graph — the feature '
      'unit tests inject fakes straight into constructors, and the '
      'navigation tests unregister-and-replace ChatCubit before ever '
      'resolving it)', () {
    expect(sl.isRegistered<ChatRepository>(), isTrue);

    // Actually resolves the whole chain (ChatCubit -> ChatRepository ->
    // ChatRemoteDataSource/Box<Map> -> ApiClient/Dio) rather than just
    // checking the registration exists — same rationale as every other
    // forced resolution above.
    expect(() => sl<ChatCubit>(), returnsNormally);

    // The two `Box<Map>` singletons are disambiguated only by
    // `instanceName` (same static type) — resolving each by its own
    // name and checking `Box.name` against it catches a swapped-
    // argument mistake in `registerChatFeature()` that `fvm flutter
    // analyze` cannot (review finding's own demonstration).
    final sessionsBox = sl<Box<Map>>(instanceName: chatSessionsBoxName);
    final messagesBox = sl<Box<Map>>(instanceName: chatMessagesBoxName);
    expect(sessionsBox.name, chatSessionsBoxName);
    expect(messagesBox.name, chatMessagesBoxName);
    expect(sessionsBox, isNot(same(messagesBox)));
  });

  test('setupCoreDependencies also wires the export feature (spec-7-1) — a '
      'broken registration/dependency cycle must surface here, not only at '
      'real app launch (review finding: no other test resolves the real '
      'registered graph — the cubit/data-source unit tests inject fakes '
      'straight into constructors, and the screen widget tests override '
      'ExportJobCubit before ever resolving it)', () async {
    expect(sl.isRegistered<ExportRepository>(), isTrue);

    // `ExportJobCubit` is a `registerFactory` (Code Map: one-shot-cubit
    // precedent), not a singleton — resolving it twice must return two
    // distinct, independently closable instances, same rationale as
    // `TextEntryCubit`'s own forced resolution above.
    final first = sl<ExportJobCubit>();
    final second = sl<ExportJobCubit>();
    expect(first, isNot(same(second)));
    await first.close();
    await second.close();
  });

  test(
    'secure storage read/write round-trips through the DI-resolved instance',
    () async {
      final storage = sl<FlutterSecureStorage>();

      await storage.write(key: 'spike_test_key', value: 'spike_test_value');
      final value = await storage.read(key: 'spike_test_key');

      expect(value, 'spike_test_value');
    },
  );
}
