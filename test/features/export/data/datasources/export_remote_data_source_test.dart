import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/features/export/data/datasources/export_remote_data_source.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockApiClient;
  late ExportRemoteDataSource dataSource;

  setUp(() {
    mockApiClient = MockApiClient();
    dataSource = ExportRemoteDataSource(mockApiClient);
  });

  group('createJob', () {
    test(
      'calls export-summary-create (x-cerne-function, never the literal '
      'REST path) with the full local calendar day — periodStart at '
      'local start-of-day, periodEnd bumped to local end-of-day — '
      'converted to UTC, decodes jobId',
      () async {
        when(
          () => mockApiClient.post(
            'export-summary-create',
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async =>
              right({'data': {'jobId': 'job-1', 'status': 'pending'}}),
        );

        // Review finding (blind-hunter layer): `showDateRangePicker`
        // returns local-midnight `DateTime`s, not UTC instants — asserting
        // against a hardcoded UTC string would make this test's pass/fail
        // depend on the machine's local timezone. Parsing the captured
        // value back with `.toLocal()` round-trips losslessly regardless
        // of offset, so this verifies the actual fix (end-of-day bump on
        // periodEnd) without being timezone-sensitive itself.
        final result = await dataSource.createJob(
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
        );

        expect(result.isRight(), isTrue);
        result.match(
          (_) => fail('expected Right'),
          (jobId) => expect(jobId, 'job-1'),
        );

        final captured = verify(
          () => mockApiClient.post(
            'export-summary-create',
            data: captureAny(named: 'data'),
          ),
        ).captured.single as Map<String, dynamic>;
        final sentStart = DateTime.parse(
          captured['periodStart'] as String,
        ).toLocal();
        final sentEnd = DateTime.parse(
          captured['periodEnd'] as String,
        ).toLocal();
        expect(sentStart, DateTime(2026, 1, 1));
        expect(sentEnd, DateTime(2026, 1, 31, 23, 59, 59, 999));
      },
    );

    test(
      'a shape mismatch maps to Left(MalformedResponse), never throws',
      () async {
        when(
          () => mockApiClient.post(
            'export-summary-create',
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => right({'data': <String, dynamic>{}}));

        final result = await dataSource.createJob(
          periodStart: DateTime.utc(2026, 1, 1),
          periodEnd: DateTime.utc(2026, 1, 31),
        );

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<MalformedResponse>()),
          (_) => fail('expected Left'),
        );
      },
    );

    test('an upstream Failure propagates unchanged', () async {
      when(
        () => mockApiClient.post(
          'export-summary-create',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );

      final result = await dataSource.createJob(
        periodStart: DateTime.utc(2026, 1, 1),
        periodEnd: DateTime.utc(2026, 1, 31),
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('getStatus', () {
    test(
      'calls export-status-get with jobId as the one trailing path '
      'segment and decodes the DTO',
      () async {
        when(
          () => mockApiClient.get(
            'export-status-get',
            pathParams: ['job-1'],
          ),
        ).thenAnswer(
          (_) async => right({
            'data': {
              'jobId': 'job-1',
              'status': 'done',
              'narrativeStatus': 'done',
              'entryCount': 5,
              'errorCode': null,
              'narrativeErrorCode': null,
              'downloadAvailable': true,
            },
          }),
        );

        final result = await dataSource.getStatus('job-1');

        expect(result.isRight(), isTrue);
        result.match((_) => fail('expected Right'), (dto) {
          expect(dto.jobId, 'job-1');
          expect(dto.status, 'done');
          expect(dto.narrativeStatus, 'done');
          expect(dto.downloadAvailable, isTrue);
        });
      },
    );

    test(
      'a shape mismatch maps to Left(MalformedResponse), never throws',
      () async {
        when(
          () => mockApiClient.get(
            'export-status-get',
            pathParams: ['job-1'],
          ),
        ).thenAnswer((_) async => right({'data': 'not-a-map'}));

        final result = await dataSource.getStatus('job-1');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<MalformedResponse>()),
          (_) => fail('expected Left'),
        );
      },
    );

    test('an upstream Failure propagates unchanged', () async {
      when(
        () => mockApiClient.get(
          'export-status-get',
          pathParams: ['job-1'],
        ),
      ).thenAnswer(
        (_) async =>
            left(const Failure.networkTimeout(message: 'timeout')),
      );

      final result = await dataSource.getStatus('job-1');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkTimeout>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
