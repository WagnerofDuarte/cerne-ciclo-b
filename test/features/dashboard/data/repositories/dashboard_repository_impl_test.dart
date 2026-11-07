import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:cerne/features/dashboard/data/models/dashboard_aggregate_dto.dart';
import 'package:cerne/features/dashboard/data/models/dashboard_narrative_dto.dart';
import 'package:cerne/features/dashboard/data/repositories/dashboard_repository_impl.dart';

class MockDashboardRemoteDataSource extends Mock
    implements DashboardRemoteDataSource {}

void main() {
  late MockDashboardRemoteDataSource mockDataSource;
  late DashboardRepositoryImpl repository;

  setUp(() {
    mockDataSource = MockDashboardRemoteDataSource();
    repository = DashboardRepositoryImpl(remoteDataSource: mockDataSource);
  });

  test('a thin pass-through (Code Map): forwards period verbatim and maps '
      'the DTO to its own domain shape via DashboardAggregateDto.toDomain, '
      'with no caching of its own', () async {
    const sources = DashboardSourcesDto(manual: 1, audio: 0, photo: 0, chat: 0);
    when(() => mockDataSource.getAggregate(period: 'all')).thenAnswer(
      (_) async => right(
        const DashboardAggregateDto(
          buckets: [
            DashboardBucketDto(date: '2026-01-01', count: 1, sources: sources),
          ],
          totals: DashboardTotalsDto(count: 1, sources: sources),
        ),
      ),
    );

    final result = await repository.getAggregate(period: 'all');

    expect(result.isRight(), isTrue);
    result.match((_) => fail('expected Right'), (aggregate) {
      expect(aggregate.totalCount, 1);
      expect(aggregate.bucketCounts, [1]);
    });
    verify(() => mockDataSource.getAggregate(period: 'all')).called(1);
  });

  test('an upstream Failure propagates unchanged', () async {
    when(() => mockDataSource.getAggregate(period: 'all')).thenAnswer(
      (_) async => left(const Failure.networkTimeout(message: 'timeout')),
    );

    final result = await repository.getAggregate(period: 'all');

    expect(result.isLeft(), isTrue);
    result.match(
      (failure) => expect(failure, isA<NetworkTimeout>()),
      (_) => fail('expected Left'),
    );
  });

  group('getNarrative (spec-8-2)', () {
    test('a thin pass-through: forwards period verbatim and maps the DTO '
        'to its own domain shape via DashboardNarrativeDto.toDomain, with '
        'no caching of its own', () async {
      when(() => mockDataSource.getNarrative(period: 'all')).thenAnswer(
        (_) async => right(
          const DashboardNarrativeDto(
            text: 'Seu balanço do período.',
            generatedAt: '2026-01-01T00:00:00Z',
          ),
        ),
      );

      final result = await repository.getNarrative(period: 'all');

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (text) => expect(text, 'Seu balanço do período.'),
      );
      verify(() => mockDataSource.getNarrative(period: 'all')).called(1);
    });

    test('an upstream Failure propagates unchanged', () async {
      when(() => mockDataSource.getNarrative(period: 'all')).thenAnswer(
        (_) async => left(const Failure.networkTimeout(message: 'timeout')),
      );

      final result = await repository.getNarrative(period: 'all');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkTimeout>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
