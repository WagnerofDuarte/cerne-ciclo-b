import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/widgets/back_arrow_header.dart';
import 'package:cerne/features/account/domain/repositories/account_settings_repository.dart';
import 'package:cerne/features/account/presentation/cubit/account_settings_cubit.dart';
import 'package:cerne/features/account/presentation/screens/account_settings_screen.dart';
import 'package:cerne/features/dashboard/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_narrative_cubit.dart';
import 'package:cerne/features/dashboard/presentation/widgets/dashboard_chart_section.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

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

  @override
  Future<void> dispose() => _controller.close();

  void _emit(bool value) {
    _value = value;
    _controller.add(value);
  }
}

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

  @override
  Future<Either<Failure, DashboardAggregate>> getAggregate({
    required String period,
  }) async => getAggregateResult;

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
  final cubit = AccountSettingsCubit(fakeRepository);
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
      final cubit = AccountSettingsCubit(fakeRepository);
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
      final accountCubit = AccountSettingsCubit(fakeAccountRepository);
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
      final accountCubit = AccountSettingsCubit(fakeAccountRepository);
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
      final accountCubit = AccountSettingsCubit(fakeAccountRepository);
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
        final accountCubit = AccountSettingsCubit(fakeAccountRepository);
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
      final accountCubit = AccountSettingsCubit(fakeAccountRepository);
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
}
