import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/features/chat/data/services/connectivity_plus_watcher.dart';

class MockConnectivity extends Mock implements Connectivity {}

/// Review finding: every test that exercises `ChatReady.isOffline`
/// elsewhere in this suite goes through `FakeConnectivityWatcher`, so
/// this file's actual online/offline mapping — the only adapter wired
/// into the real app via DI — had zero coverage; an inverted comparison
/// here would have shipped with the rest of the suite green. Mocks
/// `package:connectivity_plus`'s own `Connectivity` class directly (its
/// constructor's injectable `Connectivity?` seam), same "mock the plugin
/// class directly" convention `record_mic_recorder_test.dart` already
/// uses for `AudioRecorder`.
void main() {
  late MockConnectivity mockConnectivity;
  late ConnectivityPlusWatcher watcher;

  setUp(() {
    mockConnectivity = MockConnectivity();
    watcher = ConnectivityPlusWatcher(connectivity: mockConnectivity);
  });

  group('_isOnline mapping', () {
    test(
      'a non-none result (e.g. wifi) maps to true for the initial seed',
      () async {
        when(() => mockConnectivity.checkConnectivity())
            .thenAnswer((_) async => [ConnectivityResult.wifi]);
        // Never closes — mirrors the real `onConnectivityChanged` event
        // channel, which never completes on its own; `Stream.empty()`
        // would fire `done` almost immediately and race-close `watch()`'s
        // own controller before the seed future below gets a chance to
        // land.
        final liveController = StreamController<List<ConnectivityResult>>();
        when(() => mockConnectivity.onConnectivityChanged)
            .thenAnswer((_) => liveController.stream);
        addTearDown(liveController.close);

        expect(await watcher.watch().first, isTrue);
      },
    );

    test('[none] maps to false for the initial seed', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);
      final liveController = StreamController<List<ConnectivityResult>>();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => liveController.stream);
      addTearDown(liveController.close);

      expect(await watcher.watch().first, isFalse);
    });

    test('a live onConnectivityChanged event is mapped the same way as the '
        'initial seed', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);
      final liveController = StreamController<List<ConnectivityResult>>();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => liveController.stream);

      final events = <bool>[];
      final subscription = watcher.watch().listen(events.add);
      addTearDown(subscription.cancel);
      addTearDown(liveController.close);

      await Future<void>.delayed(Duration.zero);
      expect(events, [false]); // the initial seed

      liveController.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      expect(events, [false, true]);

      liveController.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(events, [false, true, false]);
    });
  });

  group('review finding: the live subscription is never gated behind '
      'checkConnectivity()', () {
    test('a checkConnectivity() that never resolves does not block a live '
        'event from being delivered', () async {
      final neverCompletes = Completer<List<ConnectivityResult>>();
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) => neverCompletes.future);
      final liveController = StreamController<List<ConnectivityResult>>();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => liveController.stream);

      final events = <bool>[];
      final subscription = watcher.watch().listen(events.add);
      addTearDown(subscription.cancel);
      addTearDown(liveController.close);

      liveController.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);

      // The live event arrived despite the initial check hanging
      // forever — the two are no longer sequential.
      expect(events, [true]);
    });

    test('a late-resolving checkConnectivity() is ignored once a live '
        'event has already arrived first', () async {
      final checkCompleter = Completer<List<ConnectivityResult>>();
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) => checkCompleter.future);
      final liveController = StreamController<List<ConnectivityResult>>();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => liveController.stream);

      final events = <bool>[];
      final subscription = watcher.watch().listen(events.add);
      addTearDown(subscription.cancel);
      addTearDown(liveController.close);

      liveController.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      expect(events, [true]);

      // The initial check finally resolves, with a *different*
      // value — must never overwrite/duplicate onto the stream once
      // a live event has already arrived.
      checkCompleter.complete([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);

      expect(events, [true]);
    });

    test('a checkConnectivity() that throws synchronously never escapes '
        'watch() itself and never ends the stream — the live subscription '
        'still works (RNF09)', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenThrow(Exception('platform channel unavailable'));
      final liveController = StreamController<List<ConnectivityResult>>();
      when(() => mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => liveController.stream);

      final events = <bool>[];
      late final Stream<bool> stream;
      expect(() => stream = watcher.watch(), returnsNormally);
      final subscription = stream.listen(events.add);
      addTearDown(subscription.cancel);
      addTearDown(liveController.close);

      liveController.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);

      expect(events, [true]);
    });

    test('an onConnectivityChanged getter that throws synchronously never '
        'escapes watch() itself — the seed path still works (RNF09, review '
        'finding)', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => mockConnectivity.onConnectivityChanged)
          .thenThrow(Exception('platform channel unavailable'));

      late final Stream<bool> stream;
      expect(() => stream = watcher.watch(), returnsNormally);

      expect(await stream.first, isTrue);
    });
  });
}
