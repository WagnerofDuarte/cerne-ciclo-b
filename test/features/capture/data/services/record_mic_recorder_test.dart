import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:record/record.dart' as record_pkg;

import 'package:cerne/features/capture/data/services/record_mic_recorder.dart';

class MockAudioRecorder extends Mock implements record_pkg.AudioRecorder {}

/// `getTemporaryDirectory()` (`package:path_provider`) needs a platform
/// instance even under `flutter test` — no device/simulator exists yet
/// (AGENTS.md), so this fakes the plugin's own platform interface
/// directly, same convention `fake_path_provider_platform.dart` already
/// uses for `getApplicationDocumentsPath()` (a different method of the
/// same interface — `RecordMicRecorder` calls this one instead).
class _FakeTempPathProvider extends PathProviderPlatform {
  _FakeTempPathProvider(this._path);

  final String _path;

  @override
  Future<String?> getTemporaryPath() async => _path;
}

/// Covers spec-3-2's Code Map wrapper directly — `package:record`'s own
/// `AudioRecorder` is mocked (mocktail), never a real native platform
/// channel call (Never: no automated test exercises the real plugin),
/// same "mock the plugin class directly" convention
/// `vault_repository_impl_test.dart` already uses for `LocalAuthentication`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const record_pkg.RecordConfig());
    registerFallbackValue(Duration.zero);
  });

  late Directory tempDir;
  late MockAudioRecorder mockRecorder;
  late RecordMicRecorder recorder;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cerne_test_record_');
    PathProviderPlatform.instance = _FakeTempPathProvider(tempDir.path);
    mockRecorder = MockAudioRecorder();
    recorder = RecordMicRecorder(recorder: mockRecorder);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('hasPermission() forwards AudioRecorder.hasPermission() verbatim', () async {
    when(() => mockRecorder.hasPermission()).thenAnswer((_) async => true);

    expect(await recorder.hasPermission(), isTrue);
  });

  group('start()', () {
    test(
      'starts the real recorder with a 16kHz mono wav config, writing to '
      'a fresh file under the temp dir',
      () async {
        when(
          () => mockRecorder.start(any(), path: any(named: 'path')),
        ).thenAnswer((_) async {});

        await recorder.start();

        final captured = verify(
          () => mockRecorder.start(
            captureAny(),
            path: captureAny(named: 'path'),
          ),
        ).captured;
        final config = captured[0] as record_pkg.RecordConfig;
        final path = captured[1] as String;
        expect(config.encoder, record_pkg.AudioEncoder.wav);
        expect(config.sampleRate, 16000);
        expect(config.numChannels, 1);
        expect(path, startsWith(tempDir.path));
        expect(path, endsWith('.wav'));
      },
    );
  });

  group('stop()', () {
    test(
      'after start(), returns the real output path and a duration (whole '
      'seconds, never negative)',
      () async {
        when(
          () => mockRecorder.start(any(), path: any(named: 'path')),
        ).thenAnswer((_) async {});
        when(() => mockRecorder.stop()).thenAnswer((_) async => '/tmp/out.wav');

        await recorder.start();
        final result = await recorder.stop();

        expect(result, isNotNull);
        expect(result!.path, '/tmp/out.wav');
        expect(result.durationSeconds, greaterThanOrEqualTo(0));
      },
    );

    test('with no prior start() -> null, even if the plugin returns a path', () async {
      when(() => mockRecorder.stop()).thenAnswer((_) async => '/tmp/stale.wav');

      final result = await recorder.stop();

      expect(result, isNull);
    });

    test('the plugin itself returning null (nothing captured) -> null', () async {
      when(
        () => mockRecorder.start(any(), path: any(named: 'path')),
      ).thenAnswer((_) async {});
      when(() => mockRecorder.stop()).thenAnswer((_) async => null);

      await recorder.start();
      final result = await recorder.stop();

      expect(result, isNull);
    });

    test(
      'a backward clock jump between start() and stop() (DST/NTP '
      'correction) floors durationSeconds at 0, never negative (Review '
      'finding: the existing happy-path test above can never drive this '
      'branch, since the real wall clock never moves backward during a '
      'test run)',
      () async {
        final clockReadings = [
          DateTime(2026, 1, 1, 12, 0, 10), // start()'s _startedAt
          DateTime(2026, 1, 1, 12, 0, 0), // stop()'s read — 10s earlier
        ];
        final clockRecorder = RecordMicRecorder(
          recorder: mockRecorder,
          now: () => clockReadings.removeAt(0),
        );
        when(
          () => mockRecorder.start(any(), path: any(named: 'path')),
        ).thenAnswer((_) async {});
        when(() => mockRecorder.stop()).thenAnswer((_) async => '/tmp/out.wav');

        await clockRecorder.start();
        final result = await clockRecorder.stop();

        expect(result!.durationSeconds, 0);
      },
    );
  });

  test(
    'cancel() forwards to AudioRecorder.cancel() and deletes the '
    'in-progress recording file itself (review finding: previously only '
    'asserted the plugin was called, never that the file this class\'s '
    'own doc comment promises to discard is actually gone)',
    () async {
      when(
        () => mockRecorder.start(
          captureAny(),
          path: captureAny(named: 'path'),
        ),
      ).thenAnswer((_) async {});
      when(() => mockRecorder.cancel()).thenAnswer((_) async {});
      await recorder.start();
      final path =
          verify(
                () => mockRecorder.start(
                  captureAny(),
                  path: captureAny(named: 'path'),
                ),
              ).captured.last
              as String;
      // Simulates the plugin having actually written the file by now.
      File(path).createSync();
      expect(File(path).existsSync(), isTrue);

      await recorder.cancel();

      verify(() => mockRecorder.cancel()).called(1);
      expect(File(path).existsSync(), isFalse);
    },
  );

  group('amplitudeStream', () {
    test(
      'normalizes AudioRecorder.onAmplitudeChanged dBFS into a 0.0-1.0 '
      'range, with no package:record Amplitude type ever crossing the '
      'MicRecorder boundary',
      () async {
        when(
          () => mockRecorder.onAmplitudeChanged(any()),
        ).thenAnswer(
          (_) => Stream.fromIterable([
            record_pkg.Amplitude(current: -45, max: 0),
            record_pkg.Amplitude(current: 0, max: 0),
            record_pkg.Amplitude(current: -100, max: 0),
          ]),
        );

        final values = await recorder.amplitudeStream.toList();

        expect(values[0], closeTo(0.0, 0.0001));
        expect(values[1], closeTo(1.0, 0.0001));
        // Below the -45dBFS floor clamps to the same 0.0 as exactly -45.
        expect(values[2], closeTo(0.0, 0.0001));
      },
    );
  });
}
