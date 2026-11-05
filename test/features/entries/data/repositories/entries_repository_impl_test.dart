import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/data/datasources/entries_remote_data_source.dart';
import 'package:cerne/features/entries/data/models/entry_dto.dart';
import 'package:cerne/features/entries/data/repositories/entries_repository_impl.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';

class MockEntriesRemoteDataSource extends Mock
    implements EntriesRemoteDataSource {}

class MockBox extends Mock implements Box<Map> {}

const _dto = EntryDto(
  id: 'e1',
  content: 'Hoje foi um bom dia.',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

EntryDto _listDto(String id, String occurredAt) => EntryDto(
  id: id,
  content: 'content-$id',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: occurredAt,
  serverRevision: 1,
  createdAt: occurredAt,
  updatedAt: occurredAt,
);

/// Covers spec-3-1's I/O & Edge-Case Matrix for `EntriesRepository.create`:
/// - success -> maps the `EntryDto` to `Entry` and writes it through to
///   the Hive box, keyed by id, *before* returning `Right`.
/// - failure (incl. offline) -> `Left(Failure)`, the box is never touched.
void main() {
  late MockEntriesRemoteDataSource mockRemoteDataSource;
  late MockBox mockBox;
  late EntriesRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(EntrySource.manual);
  });

  setUp(() {
    mockRemoteDataSource = MockEntriesRemoteDataSource();
    mockBox = MockBox();
    when(() => mockBox.put(any(), any())).thenAnswer((_) async {});
    when(() => mockBox.putAll(any())).thenAnswer((_) async {});
    repository = EntriesRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
      entriesBox: mockBox,
    );
  });

  group('create() — success', () {
    test('writes EntryDto.toJson() to the Hive box keyed by id, then returns '
        'Right(Entry) mapped from the dto', () async {
      when(
        () => mockRemoteDataSource.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) async => right(_dto));

      final result = await repository.create(
        content: 'Hoje foi um bom dia.',
        source: EntrySource.manual,
      );

      verify(() => mockBox.put('e1', _dto.toJson())).called(1);
      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (entry) {
        expect(entry.id, 'e1');
        expect(entry.content, 'Hoje foi um bom dia.');
        expect(entry.source, EntrySource.manual);
        expect(entry.serverRevision, 1);
      });
    });

    test('spec-3-2: a non-null mediaDurationSeconds is threaded through to '
        'the remote data source and onto the mapped Entry', () async {
      const audioDto = EntryDto(
        id: 'e2',
        content: 'Transcrição de áudio.',
        source: EntrySource.audio,
        chatMessageId: null,
        occurredAt: '2026-01-01T00:00:00Z',
        serverRevision: 1,
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
        mediaDurationSeconds: 7,
      );
      when(
        () => mockRemoteDataSource.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
          mediaDurationSeconds: any(named: 'mediaDurationSeconds'),
        ),
      ).thenAnswer((_) async => right(audioDto));

      final result = await repository.create(
        content: 'Transcrição de áudio.',
        source: EntrySource.audio,
        mediaDurationSeconds: 7,
      );

      verify(
        () => mockRemoteDataSource.create(
          content: 'Transcrição de áudio.',
          source: EntrySource.audio,
          mediaDurationSeconds: 7,
        ),
      ).called(1);
      result.match((_) => fail('expected Right'), (entry) {
        expect(entry.mediaDurationSeconds, 7);
      });
    });

    test('a Hive write failure maps to Left(malformedResponse), never '
        'throws (RNF09)', () async {
      when(
        () => mockRemoteDataSource.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) async => right(_dto));
      when(() => mockBox.put(any(), any())).thenThrow(Exception('disk full'));

      final result = await repository.create(
        content: 'Hoje foi um bom dia.',
        source: EntrySource.manual,
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('create() — failure', () {
    test('a remote Failure (e.g. offline) passes through as Left, the Hive '
        'box is never touched', () async {
      when(
        () => mockRemoteDataSource.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Offline')),
      );

      final result = await repository.create(
        content: 'Hoje foi um bom dia.',
        source: EntrySource.manual,
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
      verifyNever(() => mockBox.put(any(), any()));
    });
  });

  // spec-4-1
  group('list() — success', () {
    test('calls list() on the remote data source, persists every item to the '
        'Hive box keyed by id, then returns Right(EntriesPage) mapped from '
        'the dtos', () async {
      when(
        () => mockRemoteDataSource.list(
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => right((
          items: [
            _listDto('e1', '2026-01-02T00:00:00Z'),
            _listDto('e2', '2026-01-01T00:00:00Z'),
          ],
          nextCursor: 'next-page',
        )),
      );

      final result = await repository.list();

      verify(
        () => mockBox.putAll({
          'e1': _listDto('e1', '2026-01-02T00:00:00Z').toJson(),
          'e2': _listDto('e2', '2026-01-01T00:00:00Z').toJson(),
        }),
      ).called(1);
      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (page) {
        expect(page.items.map((e) => e.id), ['e1', 'e2']);
        expect(page.nextCursor, 'next-page');
      });
    });

    test('passes cursor/limit straight through to the data source', () async {
      when(
        () => mockRemoteDataSource.list(
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => right((items: <EntryDto>[], nextCursor: null)));

      await repository.list(cursor: 'abc', limit: 5);

      verify(() => mockRemoteDataSource.list(cursor: 'abc', limit: 5))
          .called(1);
    });

    test('a Hive write failure maps to Left(malformedResponse), never '
        'throws (RNF09)', () async {
      when(
        () => mockRemoteDataSource.list(
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => right((
          items: [_listDto('e1', '2026-01-01T00:00:00Z')],
          nextCursor: null,
        )),
      );
      when(() => mockBox.putAll(any())).thenThrow(Exception('disk full'));

      final result = await repository.list();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('list() — offline/timeout fallback (Boundaries)', () {
    test(
      'networkOffline falls back to a full Hive box dump, sorted '
      'occurredAt desc, with nextCursor: null — never propagated as Left',
      () async {
        when(
          () => mockRemoteDataSource.list(
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => left(const Failure.networkOffline(message: 'Offline')),
        );
        when(() => mockBox.values).thenReturn([
          _listDto('older', '2026-01-01T00:00:00Z').toJson(),
          _listDto('newer', '2026-01-03T00:00:00Z').toJson(),
          _listDto('middle', '2026-01-02T00:00:00Z').toJson(),
        ]);

        final result = await repository.list();

        expect(result.isRight(), isTrue);
        result.match((_) => fail('expected Right'), (page) {
          expect(page.items.map((e) => e.id), ['newer', 'middle', 'older']);
          expect(page.nextCursor, isNull);
        });
      },
    );

    test('networkTimeout triggers the exact same cache fallback', () async {
      when(
        () => mockRemoteDataSource.list(
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkTimeout(message: 'Timed out')),
      );
      when(() => mockBox.values)
          .thenReturn([_listDto('e1', '2026-01-01T00:00:00Z').toJson()]);

      final result = await repository.list();

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (page) {
        expect(page.items.single.id, 'e1');
        expect(page.nextCursor, isNull);
      });
    });

    test('an empty Hive box falls back to an empty EntriesPage, not an '
        'error', () async {
      when(
        () => mockRemoteDataSource.list(
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Offline')),
      );
      when(() => mockBox.values).thenReturn(const []);

      final result = await repository.list();

      result.match((_) => fail('expected Right'), (page) {
        expect(page.items, isEmpty);
        expect(page.nextCursor, isNull);
      });
    });

    test('every other Failure (e.g. authExpired) propagates as Left, '
        'unmapped — the Hive box is never read', () async {
      when(
        () => mockRemoteDataSource.list(
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async =>
            left(const Failure.authExpired(message: 'Sessão expirada')),
      );

      final result = await repository.list();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<AuthExpired>()),
        (_) => fail('expected Left'),
      );
      verifyNever(() => mockBox.values);
    });

    test(
      'Design Notes clarification: a paginated call (cursor != null) that '
      'fails with networkOffline propagates as Left, unmapped — the Hive '
      'box is never read, so loadMore()\'s own loadMoreFailed/retry path '
      'handles it instead of a full unrelated cache dump silently '
      'replacing the in-progress paginated list',
      () async {
        when(
          () => mockRemoteDataSource.list(
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async =>
              left(const Failure.networkOffline(message: 'Offline')),
        );

        final result = await repository.list(cursor: 'x');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<NetworkOffline>()),
          (_) => fail('expected Left'),
        );
        verifyNever(() => mockBox.values);
      },
    );

    test(
      'Design Notes clarification: a paginated call (cursor != null) that '
      'fails with networkTimeout propagates as Left too, same as '
      'networkOffline',
      () async {
        when(
          () => mockRemoteDataSource.list(
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async =>
              left(const Failure.networkTimeout(message: 'Timed out')),
        );

        final result = await repository.list(cursor: 'x');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<NetworkTimeout>()),
          (_) => fail('expected Left'),
        );
        verifyNever(() => mockBox.values);
      },
    );
  });
}
