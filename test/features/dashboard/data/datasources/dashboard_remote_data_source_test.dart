import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/features/dashboard/data/datasources/dashboard_remote_data_source.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _sources() => {
  'manual': 0,
  'audio': 0,
  'photo': 0,
  'chat': 0,
};

void main() {
  late MockApiClient mockApiClient;
  late DashboardRemoteDataSource dataSource;

  setUp(() {
    mockApiClient = MockApiClient();
    dataSource = DashboardRemoteDataSource(mockApiClient);
  });

  group('getAggregate', () {
    test('calls dashboard-aggregate-get (x-cerne-function, never the literal '
        'REST path) with the given period as the one query parameter, and '
        'decodes the DTO', () async {
      when(
        () => mockApiClient.get(
          'dashboard-aggregate-get',
          queryParameters: {'period': 'all'},
        ),
      ).thenAnswer(
        (_) async => right({
          'data': {
            'buckets': [
              {'date': '2026-01-01', 'count': 2, 'sources': _sources()},
            ],
            'totals': {'count': 2, 'sources': _sources()},
          },
        }),
      );

      final result = await dataSource.getAggregate(period: 'all');

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (dto) {
        expect(dto.totals.count, 2);
        expect(dto.buckets, hasLength(1));
      });
      verify(
        () => mockApiClient.get(
          'dashboard-aggregate-get',
          queryParameters: {'period': 'all'},
        ),
      ).called(1);
    });

    test(
      'a shape mismatch maps to Left(MalformedResponse), never throws',
      () async {
        when(
          () => mockApiClient.get(
            'dashboard-aggregate-get',
            queryParameters: {'period': 'all'},
          ),
        ).thenAnswer((_) async => right({'data': 'not-a-map'}));

        final result = await dataSource.getAggregate(period: 'all');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<MalformedResponse>()),
          (_) => fail('expected Left'),
        );
      },
    );

    test(
      // Review finding: the only other decode-failure test above uses a
      // top-level shape mismatch (`'data': 'not-a-map'`) — a missing
      // required nested field is the more realistic malformed shape for
      // this endpoint's own nested contract (`totals`/`buckets[].sources`)
      // and exercises `json_serializable`'s generated-code failure path,
      // which the top-level test never reaches.
      'a response missing the required "totals" field maps to '
      'Left(MalformedResponse), never throws',
      () async {
        when(
          () => mockApiClient.get(
            'dashboard-aggregate-get',
            queryParameters: {'period': 'all'},
          ),
        ).thenAnswer(
          (_) async => right({
            'data': {
              'buckets': [
                {'date': '2026-01-01', 'count': 2, 'sources': _sources()},
              ],
              // 'totals' deliberately omitted.
            },
          }),
        );

        final result = await dataSource.getAggregate(period: 'all');

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
          'dashboard-aggregate-get',
          queryParameters: {'period': 'all'},
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );

      final result = await dataSource.getAggregate(period: 'all');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('getNarrative (spec-8-2)', () {
    test('calls dashboard-narrative-get (x-cerne-function, never the '
        'literal REST path) with the given period as the one query '
        'parameter, and decodes the DTO', () async {
      when(
        () => mockApiClient.get(
          'dashboard-narrative-get',
          queryParameters: {'period': 'all'},
        ),
      ).thenAnswer(
        (_) async => right({
          'data': {
            'text': 'Seu balanço do período.',
            'generatedAt': '2026-01-01T00:00:00Z',
          },
        }),
      );

      final result = await dataSource.getNarrative(period: 'all');

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (dto) => expect(dto.text, 'Seu balanço do período.'),
      );
      verify(
        () => mockApiClient.get(
          'dashboard-narrative-get',
          queryParameters: {'period': 'all'},
        ),
      ).called(1);
    });

    test(
      'a shape mismatch maps to Left(MalformedResponse), never throws',
      () async {
        when(
          () => mockApiClient.get(
            'dashboard-narrative-get',
            queryParameters: {'period': 'all'},
          ),
        ).thenAnswer((_) async => right({'data': 'not-a-map'}));

        final result = await dataSource.getNarrative(period: 'all');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<MalformedResponse>()),
          (_) => fail('expected Left'),
        );
      },
    );

    test(
      'a response missing the required "generatedAt" field maps to '
      'Left(MalformedResponse), never throws',
      () async {
        when(
          () => mockApiClient.get(
            'dashboard-narrative-get',
            queryParameters: {'period': 'all'},
          ),
        ).thenAnswer(
          (_) async => right({
            'data': {
              'text': 'Seu balanço do período.',
              // 'generatedAt' deliberately omitted.
            },
          }),
        );

        final result = await dataSource.getNarrative(period: 'all');

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
          'dashboard-narrative-get',
          queryParameters: {'period': 'all'},
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );

      final result = await dataSource.getNarrative(period: 'all');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
