import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/features/dashboard/data/models/dashboard_narrative_dto.dart';

void main() {
  group('DashboardNarrativeDto.fromJson (openapi.yaml:1689-1736)', () {
    test('decodes text/generatedAt in full', () {
      final dto = DashboardNarrativeDto.fromJson({
        'text': 'Seu balanço do período.',
        'generatedAt': '2026-01-01T00:00:00Z',
      });

      expect(dto.text, 'Seu balanço do período.');
      expect(dto.generatedAt, '2026-01-01T00:00:00Z');
    });
  });

  group('DashboardNarrativeDto.toDomain', () {
    test('maps text -> a plain String, one field, no new entity (Code '
        'Map)', () {
      final dto = DashboardNarrativeDto.fromJson({
        'text': 'Seu balanço do período.',
        'generatedAt': '2026-01-01T00:00:00Z',
      });

      expect(dto.toDomain(), 'Seu balanço do período.');
    });
  });
}
