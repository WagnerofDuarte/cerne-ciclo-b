import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/features/dashboard/data/models/dashboard_aggregate_dto.dart';

Map<String, dynamic> _sources({
  int manual = 0,
  int audio = 0,
  int photo = 0,
  int chat = 0,
}) => {'manual': manual, 'audio': audio, 'photo': photo, 'chat': chat};

Map<String, dynamic> _bucket(String date, int count) => {
  'date': date,
  'count': count,
  'sources': _sources(manual: count),
};

void main() {
  group('DashboardAggregateDto.fromJson (openapi.yaml:1582-1688)', () {
    test('decodes buckets[]/totals in full, including the sources every '
        'bucket carries', () {
      final dto = DashboardAggregateDto.fromJson({
        'buckets': [_bucket('2026-01-01', 2), _bucket('2026-01-02', 3)],
        'totals': {'count': 5, 'sources': _sources(manual: 5)},
      });

      expect(dto.buckets, hasLength(2));
      expect(dto.buckets[0].date, '2026-01-01');
      expect(dto.buckets[0].count, 2);
      expect(dto.buckets[0].sources.manual, 2);
      expect(dto.buckets[1].count, 3);
      expect(dto.totals.count, 5);
      expect(dto.totals.sources.manual, 5);
    });

    test('an empty buckets list (zero entries) decodes without throwing', () {
      final dto = DashboardAggregateDto.fromJson({
        'buckets': <dynamic>[],
        'totals': {'count': 0, 'sources': _sources()},
      });

      expect(dto.buckets, isEmpty);
      expect(dto.totals.count, 0);
    });
  });

  group('DashboardAggregateDto.toDomain', () {
    test('maps totals.count -> totalCount and each bucket\'s own count -> '
        'bucketCounts, preserving order (Code Map: domain exposes only '
        'totalCount/bucketCounts)', () {
      final dto = DashboardAggregateDto.fromJson({
        'buckets': [
          _bucket('2026-01-01', 2),
          _bucket('2026-01-02', 0),
          _bucket('2026-01-03', 5),
        ],
        'totals': {'count': 7, 'sources': _sources(manual: 7)},
      });

      final aggregate = dto.toDomain();

      expect(aggregate.totalCount, 7);
      expect(aggregate.bucketCounts, [2, 0, 5]);
    });

    test('an empty buckets list maps to an empty bucketCounts', () {
      final dto = DashboardAggregateDto.fromJson({
        'buckets': <dynamic>[],
        'totals': {'count': 0, 'sources': _sources()},
      });

      expect(dto.toDomain().bucketCounts, isEmpty);
    });
  });
}
