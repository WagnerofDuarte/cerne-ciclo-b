import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/navigation/placeholder_screens.dart';
import 'package:cerne/core/widgets/app_drawer.dart';
import 'package:cerne/features/capture/domain/services/audio_transcriber.dart';
import 'package:cerne/features/capture/domain/services/mic_recorder.dart';
import 'package:cerne/features/capture/presentation/cubit/audio_entry_cubit.dart';
import 'package:cerne/features/capture/presentation/cubit/text_entry_cubit.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';

/// A trivial fake — the "+" tests below never exercise a real save, so
/// `create()` is never expected to actually be called.
class _UnusedEntriesRepository implements EntriesRepository {
  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');
}

/// Trivial fakes for `AudioEntryCubit`'s two ports — the "+" test below
/// never switches to the Áudio tab, so neither is ever expected to be
/// called (same rationale as [_UnusedEntriesRepository]).
class _UnusedMicRecorder implements MicRecorder {
  @override
  Future<bool> hasPermission() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<void> start() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<MicRecording?> stop() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<void> cancel() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Stream<double> get amplitudeStream => const Stream.empty();
}

class _UnusedAudioTranscriber implements AudioTranscriber {
  @override
  Future<String?> transcribe(String audioPath) async =>
      throw UnimplementedError('not expected to be called');
}

/// Minimal two-route `GoRouter` for the three back-arrow placeholders —
/// their header's back arrow does `context.go('/')` (Boundaries: "back-arrow
/// always targets `/`"), which needs a real `GoRouter` ancestor to resolve.
GoRouter _routerFrom(String path, Widget screen) {
  return GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Text('Home')),
      GoRoute(path: path, builder: (context, state) => screen),
    ],
  );
}

void main() {
  group('BootSplashScreen (moved from main.dart)', () {
    testWidgets(
      'stays blank below the 300ms threshold, shows a spinner once past it',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: BootSplashScreen()));

        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pump(const Duration(milliseconds: 299));
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pump(const Duration(milliseconds: 2));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );
  });

  group('BiometricReauthPlaceholderScreen (moved from main.dart)', () {
    testWidgets('renders the throwaway "Biometria" placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: BiometricReauthPlaceholderScreen()),
      );

      expect(find.text('Biometria'), findsOneWidget);
    });
  });

  group('HomeChatPlaceholderScreen', () {
    testWidgets(
      'dark-green header shows the "Cerne" wordmark; ☰ opens AppDrawer',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: HomeChatPlaceholderScreen()),
        );

        expect(find.text('Cerne'), findsOneWidget);
        expect(find.byType(AppDrawer), findsNothing);

        // Boundaries: "heavier drawer scrim rgba(36,31,25,.4)" — must
        // actually be wired to the `Scaffold`, not just exist as an
        // unused token value.
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.drawerScrimColor, DesignTokens.colorScrimHeavy);

        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        expect(find.byType(AppDrawer), findsOneWidget);
      },
    );

    testWidgets(
      'the "+" control is always tappable and opens the Insertion Modal '
      'on Texto (Story 3.1)',
      (tester) async {
        await resetCoreDependencies();
        sl.registerFactory<TextEntryCubit>(
          () => TextEntryCubit(_UnusedEntriesRepository()),
        );
        sl.registerFactory<AudioEntryCubit>(
          () => AudioEntryCubit(
            _UnusedMicRecorder(),
            _UnusedAudioTranscriber(),
            _UnusedEntriesRepository(),
          ),
        );
        addTearDown(resetCoreDependencies);

        await tester.pumpWidget(
          const MaterialApp(home: HomeChatPlaceholderScreen()),
        );

        expect(find.byIcon(Icons.add), findsOneWidget);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(find.text('Texto'), findsOneWidget);
        expect(find.text('Áudio'), findsOneWidget);
        expect(find.text('Foto'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      },
    );
  });

  group('MeusRegistrosPlaceholderScreen', () {
    testWidgets(
      'Meus Registros: shows a back-arrow header titled "Meus Registros", '
      'never a broken/unfinished look',
      (tester) async {
        final router = _routerFrom(
          '/meus-registros',
          const MeusRegistrosPlaceholderScreen(),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));

        expect(find.text('Meus Registros'), findsOneWidget);
        expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      },
    );

    testWidgets(
      'Meus Registros: the back arrow navigates to / (Boundaries: "back '
      'arrow always targets /")',
      (tester) async {
        final router = _routerFrom(
          '/meus-registros',
          const MeusRegistrosPlaceholderScreen(),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));

        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/');
        expect(find.text('Home'), findsOneWidget);
      },
    );
  });

  group(
    'ActionPlansPlaceholderScreen — Tela 5, extension, never implemented',
    () {
      testWidgets(
        'renders the prototype\'s exact static 3-column kanban with its '
        'hardcoded example cards, and its back arrow targets /',
        (tester) async {
          final router = _routerFrom(
            '/planos-de-acao',
            const ActionPlansPlaceholderScreen(),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));

          expect(find.text('Planos de Ação'), findsOneWidget);

          // Columns, with counts.
          expect(find.text('A Fazer'), findsOneWidget);
          expect(find.text('Em Andamento'), findsOneWidget);
          expect(find.text('Concluído'), findsOneWidget);
          expect(find.text('2'), findsNWidgets(2));
          expect(find.text('1'), findsOneWidget);

          // Exact hardcoded example cards from the prototype.
          expect(find.text('Organizar registros da semana'), findsOneWidget);
          expect(find.text('Revisar metas do mês'), findsOneWidget);
          expect(
            find.text('Praticar escrita livre 3x por semana'),
            findsOneWidget,
          );
          expect(find.text('Configurar lembretes diários'), findsOneWidget);
          expect(find.text('Primeira semana de registros'), findsOneWidget);

          await tester.tap(find.byIcon(Icons.chevron_left));
          await tester.pumpAndSettle();
          expect(router.state.uri.toString(), '/');
        },
      );
    },
  );
}
