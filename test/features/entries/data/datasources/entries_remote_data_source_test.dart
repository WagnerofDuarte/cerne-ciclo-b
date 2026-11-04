import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/features/entries/data/datasources/entries_remote_data_source.dart';
import 'package:cerne/features/entries/data/models/entry_dto.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';

import '../../../../support/write_failure_matrix_helper.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _entryBody({String source = 'manual'}) => {
  'data': {
    'id': 'e1',
    'content': 'Hoje foi um bom dia.',
    'source': source,
    'chatMessageId': null,
    'occurredAt': '2026-01-01T00:00:00Z',
    'tags': <dynamic>[],
    'piiStatus': 'pending',
    'embeddingStatus': 'pending',
    'serverRevision': 1,
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  },
};

void main() {
  late MockApiClient mockApiClient;
  late EntriesRemoteDataSource dataSource;

  setUp(() {
    mockApiClient = MockApiClient();
    dataSource = EntriesRemoteDataSource(mockApiClient);
  });

  // RNF09 — this story's slice of the write-failure matrix is
  // `entries-create`, exercised through `create()`.
  runWriteFailureMatrix<EntryDto>(
    endpointName: 'entries-create',
    stubNetworkTimeout: () =>
        when(() => mockApiClient.post(any(), data: any(named: 'data')))
            .thenAnswer(
              (_) async =>
                  left(const Failure.networkTimeout(message: 'Timed out')),
            ),
    stubMalformedResponse: () =>
        when(() => mockApiClient.post(any(), data: any(named: 'data')))
            .thenAnswer((_) async => right({'unexpected': 'shape'})),
    stubNoConnection: () =>
        when(() => mockApiClient.post(any(), data: any(named: 'data')))
            .thenAnswer(
              (_) async =>
                  left(const Failure.networkOffline(message: 'Offline')),
            ),
    invoke: () =>
        dataSource.create(content: 'Hoje foi um bom dia.', source: EntrySource.manual),
  );

  group('EntriesRemoteDataSource.create', () {
    test(
      'calls POST entries-create with exactly {content, source} — never '
      'chatMessageId/occurredAt/mediaDurationSeconds this story '
      '(Boundaries)',
      () async {
        when(
          () => mockApiClient.post('entries-create', data: any(named: 'data')),
        ).thenAnswer((_) async => right(_entryBody()));

        await dataSource.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.manual,
        );

        final captured = verify(
          () => mockApiClient.post(
            'entries-create',
            data: captureAny(named: 'data'),
          ),
        ).captured;
        expect(captured.single, {
          'content': 'Hoje foi um bom dia.',
          'source': 'manual',
        });
      },
    );

    test(
      'spec-3-2: a non-null mediaDurationSeconds is sent alongside '
      'content/source',
      () async {
        when(
          () => mockApiClient.post('entries-create', data: any(named: 'data')),
        ).thenAnswer((_) async => right(_entryBody(source: 'audio')));

        await dataSource.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.audio,
          mediaDurationSeconds: 7,
        );

        final captured = verify(
          () => mockApiClient.post(
            'entries-create',
            data: captureAny(named: 'data'),
          ),
        ).captured;
        expect(captured.single, {
          'content': 'Hoje foi um bom dia.',
          'source': 'audio',
          'mediaDurationSeconds': 7,
        });
      },
    );

    test(
      'decodes a non-null mediaDurationSeconds from the response data '
      'object',
      () async {
        when(
          () => mockApiClient.post('entries-create', data: any(named: 'data')),
        ).thenAnswer((_) async {
          final body = _entryBody(source: 'audio');
          (body['data']! as Map<String, dynamic>)['mediaDurationSeconds'] = 7;
          return right(body);
        });

        final result = await dataSource.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.audio,
          mediaDurationSeconds: 7,
        );

        result.match((_) => fail('expected Right'), (dto) {
          expect(dto.mediaDurationSeconds, 7);
        });
      },
    );

    test('decodes the EntryDto from the response data object', () async {
      when(
        () => mockApiClient.post('entries-create', data: any(named: 'data')),
      ).thenAnswer((_) async => right(_entryBody()));

      final result = await dataSource.create(
        content: 'Hoje foi um bom dia.',
        source: EntrySource.manual,
      );

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (dto) {
        expect(dto.id, 'e1');
        expect(dto.content, 'Hoje foi um bom dia.');
        expect(dto.source, EntrySource.manual);
        expect(dto.chatMessageId, isNull);
        expect(dto.serverRevision, 1);
      });
    });

    test('a backend error code maps straight through as the matching '
        'Failure', () async {
      when(
        () => mockApiClient.post('entries-create', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => left(const Failure.validation(message: 'conteúdo vazio')),
      );

      final result = await dataSource.create(
        content: 'Hoje foi um bom dia.',
        source: EntrySource.manual,
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<Validation>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
