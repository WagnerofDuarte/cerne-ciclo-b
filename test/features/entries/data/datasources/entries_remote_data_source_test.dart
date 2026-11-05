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

    test('spec-5-2: source/dateFrom/dateTo are omitted entirely when null '
        '(same convention as cursor)', () async {
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

    test('spec-5-2: a non-null source is sent as its own .name', () async {
      when(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));

      await dataSource.list(source: EntrySource.audio);

      final captured = verify(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, {'limit': 20, 'source': 'audio'});
    });

    test(
      'spec-5-2 code-review fix: non-null dateFrom/dateTo are sent as '
      'their own .toUtc().toIso8601String() — a local-time '
      'toIso8601String() has no Z/offset suffix, which isn\'t valid '
      'RFC3339 and doesn\'t satisfy the contract\'s own format: date-time',
      () async {
        when(
          () => mockApiClient.get(
            'entries-list',
            queryParameters: any(named: 'queryParameters'),
          ),
        ).thenAnswer((_) async => right(_listBody()));
        final dateFrom = DateTime(2026, 1, 1);
        final dateTo = DateTime(2026, 1, 31);

        await dataSource.list(dateFrom: dateFrom, dateTo: dateTo);

        final captured = verify(
          () => mockApiClient.get(
            'entries-list',
            queryParameters: captureAny(named: 'queryParameters'),
          ),
        ).captured;
        final sent = captured.single as Map<String, dynamic>;
        expect(sent['limit'], 20);
        expect(sent['dateFrom'], dateFrom.toUtc().toIso8601String());
        expect(sent['dateTo'], dateTo.toUtc().toIso8601String());
        // RFC3339: always ends in Z (UTC) or an explicit numeric offset —
        // never a bare local-time string with neither.
        expect(sent['dateFrom'], endsWith('Z'));
        expect(sent['dateTo'], endsWith('Z'));
      },
    );

    test('spec-5-2: source + dateFrom + dateTo are all sent together in one '
        'query — AND narrowing is the backend\'s own job, this data source '
        'just forwards every non-null param', () async {
      when(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));
      final dateFrom = DateTime(2026, 1, 1);
      final dateTo = DateTime(2026, 1, 31);

      await dataSource.list(
        cursor: 'abc',
        source: EntrySource.photo,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      final captured = verify(
        () => mockApiClient.get(
          'entries-list',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, {
        'limit': 20,
        'cursor': 'abc',
        'source': 'photo',
        'dateFrom': dateFrom.toUtc().toIso8601String(),
        'dateTo': dateTo.toUtc().toIso8601String(),
      });
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
    test(
      'calls GET entries-get with [id] as the one pathParams entry',
      () async {
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
      },
    );

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

  // spec-5-1 — `EntriesRepository.search`'s own data-source call,
  // `entries-search` with exactly one `q` query parameter (no
  // `limit`/`cursor`, Boundaries).
  group('EntriesRemoteDataSource.search', () {
    test('calls GET entries-search with exactly {q: query} as queryParameters '
        '— never limit/cursor', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));

      await dataSource.search('ansiedade');

      final captured = verify(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, {'q': 'ansiedade'});
    });

    test('spec-5-3: source/dateFrom/dateTo are omitted entirely when null '
        '(same convention as list())', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));

      await dataSource.search('ansiedade');

      final captured = verify(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, {'q': 'ansiedade'});
    });

    test('spec-5-3: a non-null source is sent as its own .name', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));

      await dataSource.search('ansiedade', source: EntrySource.audio);

      final captured = verify(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, {'q': 'ansiedade', 'source': 'audio'});
    });

    test('spec-5-3: non-null dateFrom/dateTo are sent as their own '
        '.toUtc().toIso8601String() — same RFC3339 rationale list() already '
        'has', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));
      final dateFrom = DateTime(2026, 1, 1);
      final dateTo = DateTime(2026, 1, 31);

      await dataSource.search('ansiedade', dateFrom: dateFrom, dateTo: dateTo);

      final captured = verify(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      final sent = captured.single as Map<String, dynamic>;
      expect(sent['q'], 'ansiedade');
      expect(sent['dateFrom'], dateFrom.toUtc().toIso8601String());
      expect(sent['dateTo'], dateTo.toUtc().toIso8601String());
      expect(sent['dateFrom'], endsWith('Z'));
      expect(sent['dateTo'], endsWith('Z'));
    });

    test('spec-5-3: q + source + dateFrom + dateTo are all sent together in '
        'one query — AND narrowing is the backend\'s own job', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody()));
      final dateFrom = DateTime(2026, 1, 1);
      final dateTo = DateTime(2026, 1, 31);

      await dataSource.search(
        'ansiedade',
        source: EntrySource.photo,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      final captured = verify(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, {
        'q': 'ansiedade',
        'source': 'photo',
        'dateFrom': dateFrom.toUtc().toIso8601String(),
        'dateTo': dateTo.toUtc().toIso8601String(),
      });
    });

    test('decodes every item in data via the same EntryDto.fromJson list() '
        'already uses', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody(ids: ['e1', 'e2'])));

      final result = await dataSource.search('ansiedade');

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (items) {
        expect(items.map((e) => e.id), ['e1', 'e2']);
      });
    });

    test('an empty data array decodes to an empty list', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right(_listBody(ids: const [])));

      final result = await dataSource.search('nada encontrado');

      result.match((_) => fail('expected Right'), (items) {
        expect(items, isEmpty);
      });
    });

    test('a superset response (similarity/mode fields) is simply ignored, '
        'same as list()\'s/get()\'s own superset handling', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => right({
          'data': [
            {..._entryJson('e1'), 'similarity': 0.87, 'mode': 'semantic'},
          ],
        }),
      );

      final result = await dataSource.search('ansiedade');

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (items) {
        expect(items.single.id, 'e1');
      });
    });

    test('a malformed 200 body maps to Left(malformedResponse), never '
        'throws (RNF09)', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => right({'unexpected': 'shape'}));

      final result = await dataSource.search('ansiedade');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('networkOffline from ApiClient passes straight through as Left, '
        'unmapped — no cache fallback at this layer either (AD-9)', () async {
      when(
        () => mockApiClient.get(
          'entries-search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Offline')),
      );

      final result = await dataSource.search('ansiedade');

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
            'entries-search',
            queryParameters: any(named: 'queryParameters'),
          ),
        ).thenAnswer(
          (_) async =>
              left(const Failure.authExpired(message: 'Sessão expirada')),
        );

        final result = await dataSource.search('ansiedade');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<AuthExpired>()),
          (_) => fail('expected Left'),
        );
      },
    );
  });
}
