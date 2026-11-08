import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/navigation/app_route_paths.dart';
import 'package:cerne/core/widgets/avatar.dart';
import 'package:cerne/core/widgets/back_arrow_header.dart';
import 'package:cerne/core/widgets/confirmation_dialog.dart';
import 'package:cerne/features/account/domain/repositories/account_settings_repository.dart';
import 'package:cerne/features/account/presentation/cubit/account_settings_cubit.dart';
import 'package:cerne/features/account/presentation/screens/account_settings_screen.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/chat/domain/entities/chat_insight.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';
import 'package:cerne/features/chat/domain/repositories/chat_repository.dart';
import 'package:cerne/features/dashboard/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_narrative_cubit.dart';
import 'package:cerne/features/dashboard/presentation/widgets/dashboard_chart_section.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';

import '../../../../support/intercept_announcements.dart';

/// Same plain (non-mocktail) fake shape as
/// `account_settings_cubit_test.dart`'s own `_FakeAccountSettingsRepository`
/// — this suite needs a scriptable `setBiometricEnabled()` result plus a
/// real stream the cubit (built from this fake, not mocked) actually
/// subscribes to. `biometricEnabledStream` is a plain broadcast stream, not
/// a `Stream.multi` replay wrapper (unlike the production repository) —
/// `AccountSettingsCubit`'s own constructor already reads
/// [currentBiometricEnabled] directly for its initial state, so no replay
/// machinery is needed for a fake with exactly one subscriber.
class _FakeAccountSettingsRepository implements AccountSettingsRepository {
  bool _value = true;
  final _controller = StreamController<bool>.broadcast();

  /// The next `setBiometricEnabled()` call's own result — defaults to a
  /// failure so a test must opt in to the success path explicitly, same
  /// convention as the cubit-level fake.
  Either<Failure, Unit> setBiometricEnabledResult = left(
    const Failure.malformedResponse(message: 'fake: not configured'),
  );

  /// Lets a test hold `setBiometricEnabled()` unresolved, to observe
  /// `state.isSaving` mid-flight (review finding: the `Switch` must
  /// disable itself while a toggle is in flight).
  Completer<void>? setBiometricEnabledGate;

  // spec-8-3 — same "configurable before the screen is pumped" convention
  // `_FakeDashboardRepository`'s own fields already use.
  @override
  String currentDisplayName = '';

  @override
  String currentEmail = '';

  /// The next `setDisplayName()` call's own result — defaults to a failure
  /// so a test must opt in to the success path explicitly, same convention
  /// as [setBiometricEnabledResult].
  Either<Failure, Unit> setDisplayNameResult = left(
    const Failure.malformedResponse(message: 'fake: not configured'),
  );

  /// Lets a test hold `setDisplayName()` unresolved, to observe
  /// `state.isSavingName` mid-flight — same rationale
  /// [setBiometricEnabledGate] already gives for the toggle.
  Completer<void>? setDisplayNameGate;

  int setDisplayNameCallCount = 0;

  /// Review finding — mirrors `AccountSettingsRepositoryImpl.
  /// setDisplayName`'s own "echo wins" behavior: on success,
  /// `currentDisplayName` is set to this value (defaulting to whatever
  /// was actually sent) rather than always just echoing the argument
  /// back unchanged.
  String? setDisplayNameEchoedNameOverride;

  @override
  Future<Either<Failure, Unit>> setDisplayName(String name) async {
    setDisplayNameCallCount += 1;
    final gate = setDisplayNameGate;
    if (gate != null) {
      await gate.future;
    }
    if (setDisplayNameResult.isRight()) {
      currentDisplayName = setDisplayNameEchoedNameOverride ?? name;
    }
    return setDisplayNameResult;
  }

  @override
  bool get currentBiometricEnabled => _value;

  @override
  Stream<bool> get biometricEnabledStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> fetchBiometricEnabled() async => right(unit);

  @override
  Future<Either<Failure, Unit>> setBiometricEnabled(bool enabled) async {
    final gate = setBiometricEnabledGate;
    if (gate != null) {
      await gate.future;
    }
    final previous = _value;
    _emit(enabled);
    final result = setBiometricEnabledResult;
    if (result.isLeft()) {
      _emit(previous);
    }
    return result;
  }

  // Story 8.5 — scriptable like [setBiometricEnabledResult]/
  // [setDisplayNameResult] above: defaults to a failure so a test must
  // opt in to the success path explicitly.
  Either<Failure, Unit> deleteAccountResult = left(
    const Failure.malformedResponse(message: 'fake: not configured'),
  );

  int deleteAccountCallCount = 0;

  /// Lets a test hold `deleteAccount()` unresolved, to observe
  /// `state.isDeletingAccount` mid-flight — same rationale
  /// [setDisplayNameGate] already gives for name saves.
  Completer<void>? deleteAccountGate;

  @override
  Future<Either<Failure, Unit>> deleteAccount() async {
    deleteAccountCallCount += 1;
    final gate = deleteAccountGate;
    if (gate != null) {
      await gate.future;
    }
    return deleteAccountResult;
  }

  @override
  Future<void> dispose() => _controller.close();

  void _emit(bool value) {
    _value = value;
    _controller.add(value);
  }
}

/// Story 8.4 — a plain (non-mocktail) fake [SessionRepository]: this
/// suite's own "Sair" tests only ever call [logout] on it; every other
/// member throws if ever reached (exercised elsewhere, by
/// `session_repository_impl_test.dart`/`auth_cubit_test.dart`).
class _FakeSessionRepository implements SessionRepository {
  int logoutCallCount = 0;
  Completer<void>? logoutGate;
  Either<Failure, Unit> logoutResult = right(unit);

  @override
  SessionStatus? get currentStatus =>
      throw UnimplementedError('not expected to be called');

  @override
  Stream<SessionStatus> get statusStream =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> restoreSession() async =>
      throw UnimplementedError('not expected to be called');

  @override
  void markAuthenticated() =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> logout() async {
    logoutCallCount += 1;
    final gate = logoutGate;
    if (gate != null) {
      await gate.future;
    }
    return logoutResult;
  }

  @override
  Future<void> dispose() async {}
}

/// Story 8.4 — same rationale as [_FakeSessionRepository]: only [lock] is
/// ever expected to be called by this suite.
class _FakeVaultRepository implements VaultRepository {
  // Review finding: [currentStatus]/[statusStream] now carry real state
  // (not `throw UnimplementedError`) — the dedicated "Sair" group's own
  // vault-gated router (below) reads [currentStatus] and listens on
  // [statusStream] to prove the redirect actually fires once [lock] runs,
  // same default-unlocked convention `app_router_test.dart`'s own
  // `_FakeVaultRepository` already uses.
  VaultStatus _status = VaultStatus.unlocked;
  final _controller = StreamController<VaultStatus>.broadcast();

  int lockCallCount = 0;

  @override
  VaultStatus get currentStatus => _status;

  @override
  Stream<VaultStatus> get statusStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> authenticate() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> submitPin(String pin) async =>
      throw UnimplementedError('not expected to be called');

  @override
  void lock() {
    lockCallCount += 1;
    _status = VaultStatus.locked;
    _controller.add(_status);
  }

  @override
  Future<void> dispose() => _controller.close();
}

/// Story 8.4 — same rationale as [_FakeSessionRepository]: only
/// [clearLocalCache] is ever expected to be called by this suite.
class _FakeEntriesRepository implements EntriesRepository {
  int clearLocalCacheCallCount = 0;
  Either<Failure, Unit> clearLocalCacheResult = right(unit);

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
    String? chatMessageId,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Entry>> getById(String id) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, List<Entry>>> search(
    String query, {
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> clearLocalCache() async {
    clearLocalCacheCallCount += 1;
    return clearLocalCacheResult;
  }
}

/// Story 8.4 — same rationale as [_FakeEntriesRepository] above.
class _FakeChatRepository implements ChatRepository {
  int clearLocalCacheCallCount = 0;
  Either<Failure, Unit> clearLocalCacheResult = right(unit);

  @override
  Future<Either<Failure, List<ChatSession>>> listSessions() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, ChatSession>> createSession() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, List<ChatMessage>>> listMessages(
    String sessionId,
  ) async => throw UnimplementedError('not expected to be called');

  @override
  Stream<Either<Failure, ChatStreamEvent>> sendMessage(
    String sessionId,
    String content,
  ) => throw UnimplementedError('not expected to be called');

  @override
  Stream<Either<Failure, ChatStreamEvent>> retryMessage(
    String sessionId,
    String userMessageId,
  ) => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, ChatInsight?>> generateInsight(
    String sessionId, {
    required InsightTriggerType triggerType,
    required String triggerKey,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Unit>> clearLocalCache() async {
    clearLocalCacheCallCount += 1;
    return clearLocalCacheResult;
  }
}

/// Story 8.4 — every pre-existing call site in this file only exercises
/// the biometric toggle / profile-name / dashboard slices, never
/// `AccountSettingsCubit.logout()`, so each one passes a fresh, never-
/// asserted-on quartet through this helper instead of repeating the
/// widened constructor's 4 new positional args inline. A caller that does
/// need to assert on one of them (the dedicated "Sair" group below) builds
/// `AccountSettingsCubit` directly instead.
AccountSettingsCubit _buildAccountSettingsCubit(
  AccountSettingsRepository repository,
) => AccountSettingsCubit(
  repository,
  _FakeSessionRepository(),
  _FakeVaultRepository(),
  _FakeEntriesRepository(),
  _FakeChatRepository(),
);

/// spec-8-1 — a trivial fake [DashboardRepository]: this suite only needs
/// `AccountSettingsScreen.initState`'s own unconditional `dashboardCubit.
/// load()` call to resolve without throwing (`dashboard_cubit_test.dart`/
/// `dashboard_chart_section_test.dart` already cover the chart's own
/// behavior in isolation) — defaults to the zero-entries shape.
class _FakeDashboardRepository implements DashboardRepository {
  Either<Failure, DashboardAggregate> getAggregateResult = right(
    const DashboardAggregate(totalCount: 0, bucketCounts: []),
  );

  /// spec-8-2 — defaults to a harmless success, same rationale
  /// [getAggregateResult] already gives: this suite's own job is the
  /// biometric toggle/chart wiring, not the narrative's own behavior
  /// (`dashboard_chart_section_test.dart`'s job).
  Either<Failure, String> getNarrativeResult = right('');

  /// Review finding: lets a test hold `getAggregate()` unresolved, to
  /// prove the narrative-error announcement gate still fires once the
  /// aggregate *later* resolves to `totalCount > 30` — the two fetches
  /// race independently (Boundaries: "neither awaiting the other"), and
  /// the narrative can resolve to its own error first.
  Completer<void>? aggregateGate;

  @override
  Future<Either<Failure, DashboardAggregate>> getAggregate({
    required String period,
  }) async {
    final gate = aggregateGate;
    if (gate != null) {
      await gate.future;
    }
    return getAggregateResult;
  }

  @override
  Future<Either<Failure, String>> getNarrative({
    required String period,
  }) async => getNarrativeResult;
}

/// A trivial fake `PendingEntryWriteTracker` — this suite never exercises
/// spec-8-1's own `confirmedWrites` recompute path, only that
/// `DashboardCubit`'s constructor subscription resolves without throwing.
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

/// Builds a fresh [DashboardCubit] and registers it for teardown — every
/// test below needs one to satisfy `AccountSettingsScreen`'s widened
/// constructor (spec-8-1), even the ones that otherwise only exercise the
/// biometric toggle. [repository] defaults to a fresh
/// [_FakeDashboardRepository] (the zero-entries shape); a caller that needs
/// to configure [_FakeDashboardRepository.getAggregateResult] *before*
/// `AccountSettingsScreen.initState`'s own `load()` call fires (review
/// finding: proving that call actually happens, not just that it doesn't
/// throw) passes its own instance in instead.
DashboardCubit _buildDashboardCubit({DashboardRepository? repository}) {
  final cubit = DashboardCubit(
    repository ?? _FakeDashboardRepository(),
    _UnusedPendingEntryWriteTracker(),
  );
  addTearDown(() => cubit.close());
  return cubit;
}

/// spec-8-2 — mirrors [_buildDashboardCubit] above for the screen's own
/// second, independent cubit (Code Map).
DashboardNarrativeCubit _buildNarrativeCubit({
  DashboardRepository? repository,
}) {
  final cubit = DashboardNarrativeCubit(
    repository ?? _FakeDashboardRepository(),
    _UnusedPendingEntryWriteTracker(),
  );
  addTearDown(() => cubit.close());
  return cubit;
}

/// `/configuracoes`'s `BackArrowHeader` does `context.go('/')`
/// (`back_arrow_header_test.dart`'s own rationale) — needs a real
/// `GoRouter` ancestor to resolve, hence this minimal two-route wrapper
/// rather than a bare `MaterialApp`.
GoRouter _routerWith(Widget screen) {
  return GoRouter(
    initialLocation: '/configuracoes',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Text('Home')),
      GoRoute(path: '/configuracoes', builder: (context, state) => screen),
    ],
  );
}

/// Story 8.4 (review finding) — wraps a [Stream] as a [Listenable] so
/// `GoRouter`'s own `refreshListenable` re-runs `redirect` on every
/// emission, same minimal purpose as `app_router.dart`'s own (private)
/// `_GoRouterRefreshStream`, just local to this one test group.
class _StreamRefreshListenable extends ChangeNotifier {
  _StreamRefreshListenable(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Story 8.4 (review finding) — the "Sair" group's own router: two routes
/// (`/configuracoes`, `/vault`) plus a minimal AD-14-style gate (`redirect`
/// away from `/configuracoes` whenever [vaultRepository] isn't
/// [VaultStatus.unlocked], re-evaluated on every [VaultRepository.
/// statusStream] emission) — just enough to prove `VaultRepository.lock()`
/// actually drives this router to `/vault`, without pulling in the real
/// `buildAppRouter()`'s full `sl` DI graph (every other route it declares
/// needs cubits this suite has no reason to resolve).
GoRouter _routerWithVaultGate(
  Widget screen,
  VaultRepository vaultRepository,
) {
  return GoRouter(
    initialLocation: AppRoutePaths.configuracoes,
    refreshListenable: _StreamRefreshListenable(vaultRepository.statusStream),
    redirect: (context, state) {
      if (vaultRepository.currentStatus != VaultStatus.unlocked) {
        return state.matchedLocation == AppRoutePaths.vaultLock
            ? null
            : AppRoutePaths.vaultLock;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutePaths.vaultLock,
        builder: (context, state) => const Text('Vault'),
      ),
      GoRoute(path: AppRoutePaths.configuracoes, builder: (context, state) => screen),
    ],
  );
}

/// Builds a fresh [_FakeAccountSettingsRepository] + [AccountSettingsCubit]
/// pair and pumps the real screen around it, registering both for cleanup.
///
/// Deliberately constructed *inside* each `testWidgets` body (via this
/// helper) rather than in a shared `setUp()` — `setUp()`'s callback runs in
/// `package:test`'s own per-test zone, a different zone than the one
/// `TestWidgetsFlutterBinding` establishes for the `testWidgets` callback
/// itself. A `StreamSubscription` (here, `AccountSettingsCubit`'s own
/// subscription to the repository's stream, set up in its constructor)
/// created in that outer zone does not reliably get its pending events
/// flushed by `tester.pump()`'s zone-scoped microtask draining — observed
/// directly: `cubit.state` updated correctly, but the `BlocBuilder`-driven
/// widget never rebuilt, no matter how many `pump()` calls followed.
/// Constructing the cubit here, inside the same zone `tester.pump()`
/// drains, avoids the mismatch entirely.
Future<(_FakeAccountSettingsRepository, AccountSettingsCubit)> _pumpScreen(
  WidgetTester tester,
) async {
  final fakeRepository = _FakeAccountSettingsRepository();
  final cubit = _buildAccountSettingsCubit(fakeRepository);
  addTearDown(() => cubit.close());
  addTearDown(fakeRepository.dispose);

  final router = _routerWith(
    AccountSettingsScreen(
      cubit: cubit,
      dashboardCubit: _buildDashboardCubit(),
      narrativeCubit: _buildNarrativeCubit(),
    ),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));

  return (fakeRepository, cubit);
}

/// spec-8-3 — same shape as [_pumpScreen], but lets a test pre-configure
/// the fake's [_FakeAccountSettingsRepository.currentDisplayName]/
/// [_FakeAccountSettingsRepository.currentEmail] *before* the cubit (and
/// therefore its initial state) is constructed — needed because
/// `AccountSettingsCubit` reads both only once, at construction
/// (Boundaries).
Future<(_FakeAccountSettingsRepository, AccountSettingsCubit)>
_pumpScreenWithProfile(
  WidgetTester tester, {
  String displayName = '',
  String email = '',
}) async {
  final fakeRepository = _FakeAccountSettingsRepository()
    ..currentDisplayName = displayName
    ..currentEmail = email;
  final cubit = _buildAccountSettingsCubit(fakeRepository);
  addTearDown(() => cubit.close());
  addTearDown(fakeRepository.dispose);

  final router = _routerWith(
    AccountSettingsScreen(
      cubit: cubit,
      dashboardCubit: _buildDashboardCubit(),
      narrativeCubit: _buildNarrativeCubit(),
    ),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));

  return (fakeRepository, cubit);
}

/// Proves spec-2-4's Acceptance Criteria directly against the real screen
/// widget: "shows only the biometric toggle" (minimal), the toggle mirrors
/// the cubit's state, tapping it drives `toggleBiometric()`, and a failed
/// toggle's error message renders inline — `app_router_test.dart` already
/// proves the screen is *reachable*; this suite proves its own rendering
/// and interaction in isolation.
void main() {
  // Story 8.5 — `ConfirmationDialog.isOpen` is a static single-overlay
  // guard, shared across every instance by design (UX-DR16/25/27/36,
  // `confirmation_dialog_test.dart`'s own identical `setUp`) — reset
  // before each test so a previous test's still-open "Apagar conta"
  // dialog (e.g. one that never tapped a button to dismiss it) never
  // silently no-ops a later test's own `ConfirmationDialog.show()` call.
  setUp(() => ConfirmationDialog.isOpen = false);

  testWidgets(
    // Review finding (round 2): renamed from "...exactly one switch — no '
    // other content (AC: shows only the biometric toggle)" — spec-8-1 now
    // also renders the "Sua evolução" chart section on this same screen,
    // so that title no longer reflects what the screen actually shows.
    'shows the biometric toggle and the dashboard chart section',
    (tester) async {
      await _pumpScreen(tester);

      expect(find.byType(BackArrowHeader), findsOneWidget);
      expect(find.text('Configurações'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('Entrar com biometria'), findsOneWidget);
      expect(find.text('Sua evolução'), findsOneWidget);
    },
  );

  testWidgets(
    'the switch mirrors currentBiometricEnabled (true) at construction',
    (tester) async {
      await _pumpScreen(tester);

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    },
  );

  testWidgets(
    'a false currentBiometricEnabled (already fetched before the screen '
    'opened) renders the switch off',
    (tester) async {
      final fakeRepository = _FakeAccountSettingsRepository().._emit(false);
      final cubit = _buildAccountSettingsCubit(fakeRepository);
      addTearDown(() => cubit.close());
      addTearDown(fakeRepository.dispose);

      final router = _routerWith(
        AccountSettingsScreen(
          cubit: cubit,
          dashboardCubit: _buildDashboardCubit(),
          narrativeCubit: _buildNarrativeCubit(),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse);
    },
  );

  testWidgets(
    'tapping the switch calls toggleBiometric() with the requested value and '
    'flips the rendered switch — no error band on success',
    (tester) async {
      final (fakeRepository, _) = await _pumpScreen(tester);
      fakeRepository.setBiometricEnabledResult = right(unit);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse);
      // No error text rendered — only the label and the back-arrow title.
      expect(find.textContaining('conexão'), findsNothing);
    },
  );

  testWidgets(
    'a failed toggle reverts the switch and shows the Failure\'s message '
    'inline, below the toggle row',
    (tester) async {
      final (fakeRepository, _) = await _pumpScreen(tester);
      fakeRepository.setBiometricEnabledResult = left(
        const Failure.networkTimeout(message: 'Sem conexão'),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
      expect(find.text('Sem conexão'), findsOneWidget);
    },
  );

  testWidgets('the switch disables itself while a toggle is in flight, so a '
      'double-tap can never start a second, overlapping call (review '
      'finding)', (tester) async {
    final (fakeRepository, _) = await _pumpScreen(tester);
    fakeRepository.setBiometricEnabledResult = right(unit);
    fakeRepository.setBiometricEnabledGate = Completer<void>();

    await tester.tap(find.byType(Switch));
    await tester.pump();

    var switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.onChanged, isNull);

    fakeRepository.setBiometricEnabledGate!.complete();
    await tester.pumpAndSettle();

    switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.onChanged, isNotNull);
    expect(switchWidget.value, isFalse);
  });

  testWidgets('a stale error from a previous visit is cleared when the screen '
      '(re)mounts — AccountSettingsCubit is a DI singleton that outlives any '
      'single visit, so a failed toggle\'s message must not still be '
      'showing on a later, unrelated visit (review finding)', (tester) async {
    final (fakeRepository, cubit) = await _pumpScreen(tester);
    fakeRepository.setBiometricEnabledResult = left(
      const Failure.networkTimeout(message: 'Sem conexão'),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Sem conexão'), findsOneWidget);

    // Simulates leaving and returning to Configurações: a brand new
    // `AccountSettingsScreen` (and its own `State`, calling `initState`
    // again) built around the SAME, still-singleton cubit — exactly
    // what a fresh `GoRoute.builder` call would produce.
    final router = _routerWith(
      AccountSettingsScreen(
        cubit: cubit,
        dashboardCubit: _buildDashboardCubit(),
        narrativeCubit: _buildNarrativeCubit(),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('Sem conexão'), findsNothing);
    // The toggle's own confirmed value is untouched by the error clear.
    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isTrue);
  });

  testWidgets(
    'the back arrow navigates to / (shared BackArrowHeader behavior)',
    (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
    },
  );

  testWidgets(
    'Boundaries: "AccountSettingsScreen.initState calls dashboardCubit.'
    'load() unconditionally" — mounting the real screen drives a real '
    'fetch on its own, with no test code ever calling load() itself; '
    'configuring a non-default repository result before the screen is '
    'even pumped and seeing it rendered is the only way to tell initState '
    'actually fired it (review finding: every other test here either '
    'calls load() itself or only exercises the default zero-entries '
    'fake, neither of which proves this)',
    (tester) async {
      final fakeDashboardRepository = _FakeDashboardRepository()
        ..getAggregateResult = right(
          const DashboardAggregate(totalCount: 5, bucketCounts: [2, 1, 2]),
        );
      final dashboardCubit = _buildDashboardCubit(
        repository: fakeDashboardRepository,
      );
      final fakeAccountRepository = _FakeAccountSettingsRepository();
      final accountCubit = _buildAccountSettingsCubit(fakeAccountRepository);
      addTearDown(() => accountCubit.close());
      addTearDown(fakeAccountRepository.dispose);

      final router = _routerWith(
        AccountSettingsScreen(
          cubit: accountCubit,
          dashboardCubit: dashboardCubit,
          narrativeCubit: _buildNarrativeCubit(),
        ),
      );
      addTearDown(router.dispose);
      // Deliberately never calls `dashboardCubit.load()` from this test —
      // only `AccountSettingsScreen.initState`'s own unconditional call
      // can be what resolves `fakeDashboardRepository`'s pre-configured
      // Right into the rendered chart below.
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardChartBar), findsNWidgets(3));
      expect(
        find.text('Comece a registrar para ver sua evolução aqui'),
        findsNothing,
      );
    },
  );

  testWidgets(
    // Review finding (round 2): the new `BlocListener<DashboardCubit, '
    // Resource<DashboardAggregate>>` announcing a `ResourceError` via '
    // `_announce` (mirroring the biometric toggle\'s own announcement) '
    // had no test — deleting it or inverting its condition would ship '
    // silently.
    'a DashboardCubit ResourceError sends the Failure\'s message as a real '
    'screen-reader announcement, same as the biometric toggle\'s own '
    'announcement',
    (tester) async {
      final announcements = interceptAnnouncements(tester);
      final fakeDashboardRepository = _FakeDashboardRepository()
        ..getAggregateResult = left(
          const Failure.networkTimeout(message: 'Sem conexão com o gráfico'),
        );
      final dashboardCubit = _buildDashboardCubit(
        repository: fakeDashboardRepository,
      );
      final fakeAccountRepository = _FakeAccountSettingsRepository();
      final accountCubit = _buildAccountSettingsCubit(fakeAccountRepository);
      addTearDown(() => accountCubit.close());
      addTearDown(fakeAccountRepository.dispose);

      final router = _routerWith(
        AccountSettingsScreen(
          cubit: accountCubit,
          dashboardCubit: dashboardCubit,
          narrativeCubit: _buildNarrativeCubit(),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(announcements, contains('Sem conexão com o gráfico'));
    },
  );

  testWidgets(
    // Spec Change Log (spec-8-2 amendment, blind-hunter + verification-gap
    // review finding): the original unconditional version of this listener
    // would speak a narrative-failed announcement even for a user whose
    // screen never renders the narrative section — proving the gate fires
    // correctly is the mirror image of the "gate blocks" test right below.
    'a narrative ResourceError announces the fixed narrative-unavailable '
    'copy (never the raw Failure.message) when DashboardCubit\'s own state '
    'is ResourceData with totalCount > 30 — the only state where the '
    'narrative section is actually visible',
    (tester) async {
      final announcements = interceptAnnouncements(tester);
      final fakeRepository = _FakeDashboardRepository()
        ..getAggregateResult = right(
          const DashboardAggregate(totalCount: 42, bucketCounts: [42]),
        )
        ..getNarrativeResult = left(
          const Failure.networkTimeout(message: 'mensagem crua do narrative'),
        );
      final dashboardCubit = _buildDashboardCubit(repository: fakeRepository);
      final narrativeCubit = _buildNarrativeCubit(repository: fakeRepository);
      final fakeAccountRepository = _FakeAccountSettingsRepository();
      final accountCubit = _buildAccountSettingsCubit(fakeAccountRepository);
      addTearDown(() => accountCubit.close());
      addTearDown(fakeAccountRepository.dispose);

      final router = _routerWith(
        AccountSettingsScreen(
          cubit: accountCubit,
          dashboardCubit: dashboardCubit,
          narrativeCubit: narrativeCubit,
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(announcements, contains('Não foi possível gerar o balanço agora'));
      expect(announcements, isNot(contains('mensagem crua do narrative')));
    },
  );

  testWidgets(
    // Mirror image of the test above: proves the gating condition from
    // patch #1 actually gates, not just that it can fire — a narrative
    // ResourceError must never be announced for a 0 or 1 totalCount, even
    // though that's exactly the state the amendment was written to guard
    // against (Spec Change Log: "a user with 30 or fewer entries hearing a
    // spoken error about a paragraph that was never on screen").
    'a narrative ResourceError never announces when DashboardCubit\'s own '
    'totalCount is 0 or 1 — the narrative section is never shown for '
    'either count, regardless of the narrative fetch\'s own result',
    (tester) async {
      for (final totalCount in [0, 1]) {
        final announcements = interceptAnnouncements(tester);
        final fakeRepository = _FakeDashboardRepository()
          ..getAggregateResult = right(
            DashboardAggregate(
              totalCount: totalCount,
              bucketCounts: totalCount == 0 ? [] : [1],
            ),
          )
          ..getNarrativeResult = left(
            const Failure.networkTimeout(message: 'mensagem crua do narrative'),
          );
        final dashboardCubit = _buildDashboardCubit(repository: fakeRepository);
        final narrativeCubit = _buildNarrativeCubit(repository: fakeRepository);
        final fakeAccountRepository = _FakeAccountSettingsRepository();
        final accountCubit = _buildAccountSettingsCubit(fakeAccountRepository);
        addTearDown(() => accountCubit.close());
        addTearDown(fakeAccountRepository.dispose);

        final router = _routerWith(
          AccountSettingsScreen(
            cubit: accountCubit,
            dashboardCubit: dashboardCubit,
            narrativeCubit: narrativeCubit,
          ),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(
          announcements,
          isEmpty,
          reason:
              'totalCount=$totalCount must never announce a narrative '
              'error — the narrative section is not rendered for this '
              'count',
        );
      }
    },
  );

  testWidgets(
    // Review finding: the two listener tests above both let the aggregate
    // fetch settle (gated or not) before the narrative one ever resolves,
    // so neither can distinguish a gate that only checks `DashboardCubit`'s
    // *current* state at the narrative's own error transition from one
    // that's correctly reactive to both cubits. The two fetches race
    // independently (Boundaries: "neither awaiting the other") — this
    // proves the announcement still fires when the narrative resolves to
    // its error *first*, before the aggregate has reached totalCount > 30.
    'a narrative ResourceError that resolves before the aggregate reaches '
    'totalCount > 30 still announces once the aggregate later resolves '
    '(out-of-order fetch resolution)',
    (tester) async {
      final announcements = interceptAnnouncements(tester);
      final aggregateGate = Completer<void>();
      final fakeRepository = _FakeDashboardRepository()
        ..getAggregateResult = right(
          const DashboardAggregate(totalCount: 42, bucketCounts: [42]),
        )
        ..getNarrativeResult = left(
          const Failure.networkTimeout(message: 'mensagem crua do narrative'),
        )
        ..aggregateGate = aggregateGate;
      final dashboardCubit = _buildDashboardCubit(repository: fakeRepository);
      final narrativeCubit = _buildNarrativeCubit(repository: fakeRepository);
      final fakeAccountRepository = _FakeAccountSettingsRepository();
      final accountCubit = _buildAccountSettingsCubit(fakeAccountRepository);
      addTearDown(() => accountCubit.close());
      addTearDown(fakeAccountRepository.dispose);

      final router = _routerWith(
        AccountSettingsScreen(
          cubit: accountCubit,
          dashboardCubit: dashboardCubit,
          narrativeCubit: narrativeCubit,
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      // The aggregate fetch is still gated (ResourceLoading), but the
      // narrative one is free to settle into its own ResourceError.
      await tester.pump();
      await tester.pump();
      expect(
        announcements,
        isEmpty,
        reason:
            'the aggregate has not reached totalCount > 30 yet, so the '
            'narrative section is not visible — nothing to announce yet',
      );

      // The aggregate now resolves to totalCount > 30, after the
      // narrative has already settled into ResourceError.
      aggregateGate.complete();
      await tester.pumpAndSettle();

      expect(announcements, contains('Não foi possível gerar o balanço agora'));
    },
  );

  testWidgets(
    // Review finding: the switch from a non-scrolling `Padding` to
    // `Expanded` + `SingleChildScrollView` (round 2) was made specifically
    // because the toggle plus the new chart section "can grow past the
    // available height on a shorter device/larger text scale" (inline
    // comment on the screen itself) — but nothing demonstrated that claim.
    // A short viewport plus a large text-scale factor is the combination
    // most likely to overflow; this proves the screen renders both the
    // toggle and a populated chart under it without a RenderFlex overflow.
    'the toggle and a populated chart both fit on a short viewport at a '
    'large text-scale factor, with no RenderFlex overflow (review finding)',
    (tester) async {
      tester.view.physicalSize = const Size(360, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final fakeDashboardRepository = _FakeDashboardRepository()
        ..getAggregateResult = right(
          const DashboardAggregate(totalCount: 12, bucketCounts: [3, 0, 4, 5]),
        );
      final dashboardCubit = _buildDashboardCubit(
        repository: fakeDashboardRepository,
      );
      final fakeAccountRepository = _FakeAccountSettingsRepository();
      final accountCubit = _buildAccountSettingsCubit(fakeAccountRepository);
      addTearDown(() => accountCubit.close());
      addTearDown(fakeAccountRepository.dispose);

      final router = _routerWith(
        AccountSettingsScreen(
          cubit: accountCubit,
          dashboardCubit: dashboardCubit,
          narrativeCubit: _buildNarrativeCubit(),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(DashboardChartBar), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    },
  );

  // spec-8-3 — the profile header's own Acceptance Criteria, proved
  // directly against the real screen widget.
  group('profile header (spec-8-3)', () {
    testWidgets('shows a large avatar with initials, the display name and the '
        'e-mail above the toggle, in display mode', (tester) async {
      await _pumpScreenWithProfile(
        tester,
        displayName: 'Ana Silva',
        email: 'ana@example.com',
      );

      final avatar = tester.widget<Avatar>(find.byType(Avatar));
      expect(avatar.size, AvatarSize.large);
      expect(avatar.initials, 'AS');
      expect(find.text('Ana Silva'), findsOneWidget);
      expect(find.text('ana@example.com'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
      // AC: "Given display mode, when the pencil is tapped, then the name
      // becomes editable (pre-filled) and the icon becomes a check."
      'tapping the pencil icon switches the name to an editable, pre-filled '
      'field and the icon becomes a check',
      (tester) async {
        await _pumpScreenWithProfile(tester, displayName: 'Ana Silva');

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pump();

        expect(find.byType(TextField), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, 'Ana Silva');
        expect(find.byIcon(Icons.check), findsOneWidget);
        expect(find.byIcon(Icons.edit), findsNothing);
      },
    );

    testWidgets(
      // AC: "Given a changed non-empty draft, when the check is tapped and
      // save succeeds, then the screen shows the new name in display
      // mode."
      'confirming a changed, non-empty name saves it and shows the new '
      'name in display mode on success',
      (tester) async {
        final (fakeRepository, _) = await _pumpScreenWithProfile(
          tester,
          displayName: 'Ana Silva',
        );
        fakeRepository.setDisplayNameResult = right(unit);

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Ana Souza');
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);
        expect(find.text('Ana Souza'), findsOneWidget);
        expect(find.byIcon(Icons.edit), findsOneWidget);
      },
    );

    testWidgets(
      // AC: "Given a save fails, then the field stays editable with the
      // typed text and an inline error."
      'a failed save keeps the field editable with the typed text and '
      'shows the Failure\'s message inline',
      (tester) async {
        final (fakeRepository, _) = await _pumpScreenWithProfile(
          tester,
          displayName: 'Ana Silva',
        );
        fakeRepository.setDisplayNameResult = left(
          const Failure.networkTimeout(message: 'Sem conexão'),
        );

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Ana Souza');
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, 'Ana Souza');
        expect(find.text('Sem conexão'), findsOneWidget);
        expect(find.byIcon(Icons.check), findsOneWidget);
      },
    );

    testWidgets(
      // Review finding: the test above only asserted the on-screen Text/
      // TextField — it never proved `_announce` actually fires on a name-
      // save failure, unlike the sibling toggle-failure and narrative-
      // failure tests elsewhere in this file, which all intercept the
      // real accessibility channel. Boundaries: "_announce fires on a
      // save failure, same BlocListener convention as the toggle's
      // error".
      'a failed save sends the Failure\'s message as a real screen-reader '
      'announcement, same BlocListener convention as the toggle\'s own '
      'error',
      (tester) async {
        final announcements = interceptAnnouncements(tester);
        final (fakeRepository, _) = await _pumpScreenWithProfile(
          tester,
          displayName: 'Ana Silva',
        );
        fakeRepository.setDisplayNameResult = left(
          const Failure.networkTimeout(message: 'Sem conexão'),
        );

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Ana Souza');
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(announcements, contains('Sem conexão'));
      },
    );

    testWidgets(
      // Review finding: `setDisplayNameGate` was added to this fake
      // specifically to let a test hold `setDisplayName()` unresolved and
      // observe the mid-flight UI, but nothing used it — the saving
      // indicator and the "tap away while saving is a no-op" I/O-matrix
      // row were proven only at the cubit level, never against the real
      // screen widget.
      'shows a saving indicator while a save is in flight; tapping away '
      'during that save is a no-op until it completes (I/O matrix: "Tap '
      'away, saving -> No-op, save completes")',
      (tester) async {
        final (fakeRepository, _) = await _pumpScreenWithProfile(
          tester,
          displayName: 'Ana Silva',
        );
        fakeRepository.setDisplayNameResult = right(unit);
        fakeRepository.setDisplayNameGate = Completer<void>();

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Ana Souza');
        await tester.tap(find.byIcon(Icons.check));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.check), findsNothing);

        // Tap-away while saving is a no-op — the in-flight save still
        // owns the eventual transition back to display mode.
        await tester.tapAt(tester.getCenter(find.text('Entrar com biometria')));
        await tester.pump();
        expect(find.byType(TextField), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        fakeRepository.setDisplayNameGate!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);
        expect(find.text('Ana Souza'), findsOneWidget);
      },
    );

    testWidgets(
      // AC: "Given an unconfirmed edit, when the user taps outside the
      // field/icon, then the screen reverts with no change sent."
      'tapping away from an unconfirmed edit reverts to display mode with '
      'no PATCH sent',
      (tester) async {
        final (fakeRepository, _) = await _pumpScreenWithProfile(
          tester,
          displayName: 'Ana Silva',
        );

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Rascunho descartado');
        // Taps a point well outside the name field + check icon's own
        // `TapRegion` — the biometric toggle's own label, elsewhere on the
        // same screen.
        await tester.tapAt(tester.getCenter(find.text('Entrar com biometria')));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);
        expect(find.text('Ana Silva'), findsOneWidget);
        expect(find.byIcon(Icons.edit), findsOneWidget);
        expect(fakeRepository.setDisplayNameCallCount, 0);
      },
    );

    testWidgets(
      'confirming an unchanged draft reverts immediately with no PATCH '
      'sent (I/O matrix)',
      (tester) async {
        await _pumpScreenWithProfile(tester, displayName: 'Ana Silva');

        await tester.tap(find.byIcon(Icons.edit));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);
        expect(find.text('Ana Silva'), findsOneWidget);
      },
    );

    // Code-review patch: the backend allows a displayName up to 80
    // characters — the display-mode Text had no maxLines/overflow, so a
    // long name could wrap to multiple lines and misalign against the
    // fixed-size pencil icon beside it.
    testWidgets(
      'a long (80-character) display name renders on one line with an '
      'ellipsis, no overflow exception',
      (tester) async {
        final longName = 'A' * 80;
        await _pumpScreenWithProfile(tester, displayName: longName);
        await tester.pumpAndSettle();

        final textWidget = tester.widget<Text>(find.text(longName));
        expect(textWidget.maxLines, 1);
        expect(textWidget.overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
      },
    );

    // Code-review patch: `_initialsFor` used to slice each initial via
    // `String.substring(0, 1)`, which operates on UTF-16 code units and
    // can split a surrogate pair — e.g. an emoji starting a word — into a
    // lone, unpaired surrogate. Fixed to use `Characters.first`
    // (grapheme-cluster aware).
    testWidgets(
      'a display name whose first word starts with an emoji derives '
      'initials via whole Unicode grapheme clusters, renders without '
      'throwing',
      (tester) async {
        await _pumpScreenWithProfile(tester, displayName: '😀 Silva');
        await tester.pumpAndSettle();

        final avatar = tester.widget<Avatar>(find.byType(Avatar));
        // The emoji's own surrogate pair stays intact (one whole
        // grapheme), followed by "Silva"'s own first letter — not a lone,
        // unpaired surrogate half.
        expect(avatar.initials, '😀S');
        expect(tester.takeException(), isNull);
      },
    );
  });

  // Story 8.4 — the "Sair" button's own Acceptance Criteria, proved
  // directly against the real screen widget (Code Map: "'Sair' AppButton
  // as the scroll column's last child, below DashboardChartSection").
  group('"Sair" button (Story 8.4)', () {
    /// Builds the real screen around a fresh [AccountSettingsCubit] wired
    /// to controllable session/vault/entries/chat fakes (unlike
    /// [_pumpScreen]/[_pumpScreenWithProfile], which only need the trivial,
    /// never-asserted-on quartet [_buildAccountSettingsCubit] gives). Uses
    /// the same plain, non-navigating [_routerWith] stub every other test
    /// in this file already uses — deliberately NOT the vault-gated router
    /// below, since the two tests built on this helper (the button's own
    /// render + its disabled-while-in-flight state) need the screen to
    /// stay mounted through the whole call, which a real vault-gate
    /// redirect would otherwise unmount mid-test.
    Future<
      (
        _FakeSessionRepository,
        _FakeVaultRepository,
        _FakeEntriesRepository,
        _FakeChatRepository,
      )
    >
    pumpWithLogoutFakes(WidgetTester tester) async {
      final fakeAccountRepository = _FakeAccountSettingsRepository();
      final fakeSessionRepository = _FakeSessionRepository();
      final fakeVaultRepository = _FakeVaultRepository();
      final fakeEntriesRepository = _FakeEntriesRepository();
      final fakeChatRepository = _FakeChatRepository();
      final cubit = AccountSettingsCubit(
        fakeAccountRepository,
        fakeSessionRepository,
        fakeVaultRepository,
        fakeEntriesRepository,
        fakeChatRepository,
      );
      addTearDown(() => cubit.close());
      addTearDown(fakeAccountRepository.dispose);

      final router = _routerWith(
        AccountSettingsScreen(
          cubit: cubit,
          dashboardCubit: _buildDashboardCubit(),
          narrativeCubit: _buildNarrativeCubit(),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      return (
        fakeSessionRepository,
        fakeVaultRepository,
        fakeEntriesRepository,
        fakeChatRepository,
      );
    }

    /// Review finding: same fakes/cubit wiring as [pumpWithLogoutFakes],
    /// but around the dedicated vault-gated router below instead of the
    /// plain stub — used ONLY by the one test that needs to prove
    /// `VaultRepository.lock()` actually drives real navigation away from
    /// `/configuracoes`, since that redirect unmounts the screen (same
    /// AD-14 behavior the real `buildAppRouter()` has), which the other
    /// tests in this group must NOT be subject to.
    Future<
      (
        _FakeSessionRepository,
        _FakeVaultRepository,
        _FakeEntriesRepository,
        _FakeChatRepository,
        GoRouter,
      )
    >
    pumpWithLogoutFakesAndVaultGate(WidgetTester tester) async {
      final fakeAccountRepository = _FakeAccountSettingsRepository();
      final fakeSessionRepository = _FakeSessionRepository();
      final fakeVaultRepository = _FakeVaultRepository();
      final fakeEntriesRepository = _FakeEntriesRepository();
      final fakeChatRepository = _FakeChatRepository();
      final cubit = AccountSettingsCubit(
        fakeAccountRepository,
        fakeSessionRepository,
        fakeVaultRepository,
        fakeEntriesRepository,
        fakeChatRepository,
      );
      addTearDown(() => cubit.close());
      addTearDown(fakeAccountRepository.dispose);

      final router = _routerWithVaultGate(
        AccountSettingsScreen(
          cubit: cubit,
          dashboardCubit: _buildDashboardCubit(),
          narrativeCubit: _buildNarrativeCubit(),
        ),
        fakeVaultRepository,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      return (
        fakeSessionRepository,
        fakeVaultRepository,
        fakeEntriesRepository,
        fakeChatRepository,
        router,
      );
    }

    testWidgets(
      'shows a "Sair" button below the chart section',
      (tester) async {
        await pumpWithLogoutFakes(tester);

        expect(find.text('Sair'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "Sair" locks the vault, fires sessionRepository.logout(), '
      'and clears both the entries and chat local caches',
      (tester) async {
        final (
          fakeSessionRepository,
          fakeVaultRepository,
          fakeEntriesRepository,
          fakeChatRepository,
          router,
        ) = await pumpWithLogoutFakesAndVaultGate(tester);

        await tester.tap(find.text('Sair'));
        await tester.pumpAndSettle();

        expect(fakeVaultRepository.lockCallCount, 1);
        expect(fakeSessionRepository.logoutCallCount, 1);
        expect(fakeEntriesRepository.clearLocalCacheCallCount, 1);
        expect(fakeChatRepository.clearLocalCacheCallCount, 1);
        // Review finding: previously only the fakes' own call counts were
        // asserted, never that the router actually redirected — this is
        // the spec's own Acceptance Criteria ("the user is routed to the
        // Biometric Vault screen"), proved here against the same router
        // `VaultRepository.lock()` drives, with no navigation code of
        // this screen's own involved (AD-14).
        expect(router.state.uri.toString(), AppRoutePaths.vaultLock);
      },
    );

    testWidgets(
      'disables the button while a logout is in flight, so a double-tap '
      'can never start a second, overlapping call (I/O matrix: '
      '"Double-tap Sair")',
      (tester) async {
        final (fakeSessionRepository, fakeVaultRepository, _, _) =
            await pumpWithLogoutFakes(tester);
        fakeSessionRepository.logoutGate = Completer<void>();

        await tester.tap(find.text('Sair'));
        await tester.pump();

        final button = tester.widget<OutlinedButton>(
          find.byType(OutlinedButton),
        );
        expect(button.onPressed, isNull);

        fakeSessionRepository.logoutGate!.complete();
        await tester.pumpAndSettle();

        expect(fakeVaultRepository.lockCallCount, 1);
        expect(fakeSessionRepository.logoutCallCount, 1);
      },
    );

    testWidgets(
      'a backend logout failure (offline) still clears local caches, '
      'with no error shown on screen (I/O matrix: "Left swallowed, no UI '
      'message")',
      (tester) async {
        final (
          fakeSessionRepository,
          _,
          fakeEntriesRepository,
          fakeChatRepository,
        ) = await pumpWithLogoutFakes(tester);
        fakeSessionRepository.logoutResult = left(
          const Failure.networkOffline(message: 'Offline'),
        );

        await tester.tap(find.text('Sair'));
        await tester.pumpAndSettle();

        expect(fakeEntriesRepository.clearLocalCacheCallCount, 1);
        expect(fakeChatRepository.clearLocalCacheCallCount, 1);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Offline'), findsNothing);
      },
    );
  });

  // Story 8.5 — the "Apagar conta" button's own Acceptance Criteria,
  // proved directly against the real screen widget (Code Map: "'Apagar
  // conta' trigger + inline error, after 'Sair'; dialog builder").
  group('"Apagar conta" button (Story 8.5)', () {
    /// Same rationale as the "Sair" group's own `pumpWithLogoutFakes` —
    /// gives each test a fresh, controllable fake quintet plus the real
    /// screen, built around the plain, non-navigating router stub (none of
    /// these tests need a real vault-gate redirect to assert on).
    Future<
      (
        _FakeAccountSettingsRepository,
        _FakeSessionRepository,
        _FakeVaultRepository,
        _FakeEntriesRepository,
        _FakeChatRepository,
      )
    >
    pumpWithDeleteAccountFakes(WidgetTester tester) async {
      final fakeAccountRepository = _FakeAccountSettingsRepository();
      final fakeSessionRepository = _FakeSessionRepository();
      final fakeVaultRepository = _FakeVaultRepository();
      final fakeEntriesRepository = _FakeEntriesRepository();
      final fakeChatRepository = _FakeChatRepository();
      final cubit = AccountSettingsCubit(
        fakeAccountRepository,
        fakeSessionRepository,
        fakeVaultRepository,
        fakeEntriesRepository,
        fakeChatRepository,
      );
      addTearDown(() => cubit.close());
      addTearDown(fakeAccountRepository.dispose);

      final router = _routerWith(
        AccountSettingsScreen(
          cubit: cubit,
          dashboardCubit: _buildDashboardCubit(),
          narrativeCubit: _buildNarrativeCubit(),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      return (
        fakeAccountRepository,
        fakeSessionRepository,
        fakeVaultRepository,
        fakeEntriesRepository,
        fakeChatRepository,
      );
    }

    testWidgets(
      'shows an "Apagar conta" button below "Sair"',
      (tester) async {
        await pumpWithDeleteAccountFakes(tester);

        expect(find.text('Sair'), findsOneWidget);
        expect(find.text('Apagar conta'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "Apagar conta" opens the destructive-variant dialog with a '
      'red title, "Apagar tudo" and an outline "Cancelar" (AC: "the '
      'destructive-variant dialog appears with a red title")',
      (tester) async {
        await pumpWithDeleteAccountFakes(tester);

        await tester.tap(find.text('Apagar conta'));
        await tester.pumpAndSettle();

        expect(find.text('Apagar sua conta?'), findsOneWidget);
        final titleText = tester.widget<Text>(
          find.text('Apagar sua conta?'),
        );
        expect(titleText.style!.color, DesignTokens.colorError);
        expect(find.text('Apagar tudo'), findsOneWidget);
        expect(find.text('Cancelar'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "Cancelar" closes the dialog with no network call and the '
      'screen unchanged (I/O matrix)',
      (tester) async {
        final (fakeAccountRepository, _, fakeVaultRepository, _, _) =
            await pumpWithDeleteAccountFakes(tester);

        await tester.tap(find.text('Apagar conta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        expect(find.text('Apagar sua conta?'), findsNothing);
        expect(fakeAccountRepository.deleteAccountCallCount, 0);
        expect(fakeVaultRepository.lockCallCount, 0);
        expect(find.text('Apagar conta'), findsOneWidget);
      },
    );

    testWidgets(
      'confirming "Apagar tudo" closes the dialog immediately, fires '
      'deleteAccount(), and on success relocks the vault + clears both '
      'local caches (AC: "DELETE /account fires and, on success, the '
      'account/data are gone")',
      (tester) async {
        final (
          fakeAccountRepository,
          fakeSessionRepository,
          fakeVaultRepository,
          fakeEntriesRepository,
          fakeChatRepository,
        ) = await pumpWithDeleteAccountFakes(tester);
        fakeAccountRepository.deleteAccountResult = right(unit);

        await tester.tap(find.text('Apagar conta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apagar tudo'));
        // The dialog's own onConfirm pops it synchronously, before
        // deleteAccount() is even called (Boundaries: "onConfirm pops the
        // dialog synchronously, then calls ... deleteAccount()") — settled
        // here past the 180ms exit fade to assert its final state.
        await tester.pumpAndSettle();

        expect(find.text('Apagar sua conta?'), findsNothing);
        expect(fakeAccountRepository.deleteAccountCallCount, 1);
        expect(fakeVaultRepository.lockCallCount, 1);
        expect(fakeSessionRepository.logoutCallCount, 1);
        expect(fakeEntriesRepository.clearLocalCacheCallCount, 1);
        expect(fakeChatRepository.clearLocalCacheCallCount, 1);
      },
    );

    testWidgets(
      'a failed account-delete (offline/expired/...) shows an inline red '
      'error below "Apagar conta", leaves the vault unlocked and clears '
      'nothing (I/O matrix: "dialog already closed; inline red error... '
      'vault stays unlocked, nothing cleared")',
      (tester) async {
        final announcements = interceptAnnouncements(tester);
        final (
          fakeAccountRepository,
          _,
          fakeVaultRepository,
          fakeEntriesRepository,
          fakeChatRepository,
        ) = await pumpWithDeleteAccountFakes(tester);
        fakeAccountRepository.deleteAccountResult = left(
          const Failure.networkOffline(message: 'Offline'),
        );

        await tester.tap(find.text('Apagar conta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apagar tudo'));
        await tester.pumpAndSettle();

        expect(find.text('Apagar sua conta?'), findsNothing);
        expect(find.textContaining('Offline'), findsOneWidget);
        final errorText = tester.widget<Text>(find.textContaining('Offline'));
        expect(errorText.style!.color, DesignTokens.colorError);
        expect(fakeVaultRepository.lockCallCount, 0);
        expect(fakeEntriesRepository.clearLocalCacheCallCount, 0);
        expect(fakeChatRepository.clearLocalCacheCallCount, 0);
        // Code-review patch: proves the failure is both announced to
        // screen readers (I/O matrix's own "Left.message shown") and
        // announced exactly once, not twice (the failure emit and the
        // outer `finally`'s `isDeletingAccount` reset emit both used to
        // carry the same non-null message before the screen's listener
        // gained a `listenWhen` guard).
        expect(announcements, ['Offline']);
      },
    );

    testWidgets(
      'disables the button while a deletion is in flight, so a double-tap '
      'can never start a second, overlapping call (I/O matrix: '
      '"Double-tap Apagar conta")',
      (tester) async {
        final (fakeAccountRepository, _, _, _, _) =
            await pumpWithDeleteAccountFakes(tester);
        fakeAccountRepository.deleteAccountGate = Completer<void>();

        await tester.tap(find.text('Apagar conta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apagar tudo'));
        await tester.pump();

        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Apagar conta'),
        );
        expect(button.onPressed, isNull);

        fakeAccountRepository.deleteAccountGate!.complete();
        await tester.pumpAndSettle();

        expect(fakeAccountRepository.deleteAccountCallCount, 1);
      },
    );
  });
}
