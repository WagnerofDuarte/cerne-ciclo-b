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

Map<String, dynamic> _entryJson(String id) => {
  'id': id,
  'content': 'content-$id',
  'source': 'manual',
  'chatMessageId': null,
  'occurredAt': '2026-01-01T00:00:00Z',
  'tags': <dynamic>[],
  'piiStatus': 'pending',
  'embeddingStatus': 'pending',
  'serverRevision': 1,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> _listBody({
  List<String> ids = const ['e1'],
  String? nextCursor,
}) => {
  'data': [for (final id in ids) _entryJson(id)],
  'meta': {'nextCursor': nextCursor},
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
    invoke: () => dataSource.create(
      content: 'Hoje foi um bom dia.',
      source: EntrySource.manual,
    ),
  );

  group('EntriesRemoteDataSource.create', () {
    test('calls POST entries-create with exactly {content, source} — never '
        'chatMessageId/occurredAt/mediaDurationSeconds this story '
        '(Boundaries)', () async {
      when(() => mockApiClient.post('entries-create', data: any(named: 'data')))
          .thenAnswer((_) async => right(_entryBody()));

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
    });

    test('spec-3-2: a non-null mediaDurationSeconds is sent alongside '
        'content/source', () async {
      when(() => mockApiClient.post('entries-create', data: any(named: 'data')))
          .thenAnswer((_) async => right(_entryBody(source: 'audio')));

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
    });

    test('decodes a non-null mediaDurationSeconds from the response data '
        'object', () async {
      when(() => mockApiClient.post('entries-create', data: any(named: 'data')))
          .thenAnswer((_) async {
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
    });

    test('decodes the EntryDto from the response data object', () async {
      when(() => mockApiClient.post('entries-create', data: any(named: 'data')))
          .thenAnswer((_) async => right(_entryBody()));

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
      when(() => mockApiClient.post('entries-create', data: any(named: 'data')))
          .thenAnswer(
            (_) async =>
                left(const Failure.validation(message: 'conteúdo vazio')),
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

  // spec-4-1 — this story's slice of the write-failure matrix's read-side
  // analogue: `entries-list`, exercised through `list()`. Not
  // `runWriteFailureMatrix` (RNF09's own helper is scoped to write
  // endpoints) — asserted directly instead.
  group('EntriesRemoteDataSource.list', () {
    test('calls GET entries-list with limit always sent, cursor omitted when '
        'null', () async {
      when(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));

      await dataSource.list();

      final captured = verify(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, {'limit': 20});
    });

    test('a non-null cursor and a custom limit are both sent', () async {
      when(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));

      await dataSource.list(cursor: 'abc123', limit: 5);

      final captured = verify(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, {'limit': 5, 'cursor': 'abc123'});
    });

    test(
      'decodes every item in data plus meta.nextCursor on success',
      () async {
        when(
          () => mockApiClient.get(
            'entries-list',
            queryParameters: any(named: 'queryParameters'),
          ),
        ).thenAnswer(
          (_) async =>
              right(_listBody(ids: ['e1', 'e2'], nextCursor: 'next-page')),
        );

        final result = await dataSource.list();

        expect(result.isRight(), isTrue);
        result.match((_) => fail('expected Right'), (page) {
          expect(page.items.map((e) => e.id), ['e1', 'e2']);
          expect(page.nextCursor, 'next-page');
        });
      },
    );

    test('a null meta.nextCursor decodes to null (last page)', () async {
      when(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));

      final result = await dataSource.list();

      result.match((_) => fail('expected Right'), (page) {
        expect(page.nextCursor, isNull);
      });
    });

    test('an empty data array decodes to an empty items list', () async {
      when(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody(ids: const [])));

      final result = await dataSource.list();

      result.match((_) => fail('expected Right'), (page) {
        expect(page.items, isEmpty);
      });
    });

    test('a malformed 200 body maps to Left(malformedResponse), never '
        'throws (RNF09)', () async {
      when(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right({'unexpected': 'shape'}));

      final result = await dataSource.list();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('networkOffline/networkTimeout from ApiClient pass straight through '
        'as Left, unmapped — the Hive fallback is the repository\'s own job, '
        'not this data source\'s', () async {
      when(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Offline')),
      );

      final result = await dataSource.list();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
    });

    test(
      'a backend error code (e.g. authExpired) maps straight through',
      () async {
        when(
          () => mockApiClient.get(
            'entries-list',
            queryParameters: any(named: 'queryParameters'),
          ),
        ).thenAnswer(
          (_) async =>
              left(const Failure.authExpired(message: 'Sessão expirada')),
        );

        final result = await dataSource.list();

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<AuthExpired>()),
          (_) => fail('expected Left'),
        );
      },
    );
  });

  // spec-4-4 (RF07) — `EntriesRepository.getById`'s own data-source call,
  // `entries-get` with [id] as its one trailing path segment.
  group('EntriesRemoteDataSource.get', () {
    test('calls GET entries-get with [id] as the one pathParams entry', () async {
      when(
        () => mockApiClient.get(
          'entries-get',
          pathParams: any(named: 'pathParams'),
        ),
      ).thenAnswer((_) async => right(_entryBody()));

      await dataSource.get('e1');

      final captured = verify(
        () => mockApiClient.get(
          'entries-get',
          pathParams: captureAny(named: 'pathParams'),
        ),
      ).captured;
      expect(captured.single, ['e1']);
    });

    test('decodes the EntryDto from the response data object', () async {
      when(
        () => mockApiClient.get(
          'entries-get',
          pathParams: any(named: 'pathParams'),
        ),
      ).thenAnswer((_) async => right(_entryBody()));

      final result = await dataSource.get('e1');

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (dto) {
        expect(dto.id, 'e1');
        expect(dto.content, 'Hoje foi um bom dia.');
        expect(dto.source, EntrySource.manual);
      });
    });

    test('a malformed 200 body maps to Left(malformedResponse), never '
        'throws (RNF09)', () async {
      when(
        () => mockApiClient.get(
          'entries-get',
          pathParams: any(named: 'pathParams'),
        ),
      ).thenAnswer((_) async => right({'unexpected': 'shape'}));

      final result = await dataSource.get('e1');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test(
      'a backend NOT_FOUND passes straight through as Left, unmapped',
      () async {
        when(
          () => mockApiClient.get(
            'entries-get',
            pathParams: any(named: 'pathParams'),
          ),
        ).thenAnswer(
          (_) async => left(const Failure.notFound(message: 'Não encontrado')),
        );

        final result = await dataSource.get('unknown-id');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<NotFound>()),
          (_) => fail('expected Left'),
        );
      },
    );

    test('networkOffline/networkTimeout from ApiClient pass straight '
        'through as Left, unmapped — the Hive fallback is the repository\'s '
        'own job, not this data source\'s', () async {
      when(
        () => mockApiClient.get(
          'entries-get',
          pathParams: any(named: 'pathParams'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Offline')),
      );

      final result = await dataSource.get('e1');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
