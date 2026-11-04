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
    repository = EntriesRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
      entriesBox: mockBox,
    );
  });

  group('create() — success', () {
    test(
      'writes EntryDto.toJson() to the Hive box keyed by id, then returns '
      'Right(Entry) mapped from the dto',
      () async {
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
      },
    );

    test(
      'spec-3-2: a non-null mediaDurationSeconds is threaded through to '
      'the remote data source and onto the mapped Entry',
      () async {
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
      },
    );

    test('a Hive write failure maps to Left(malformedResponse), never '
        'throws (RNF09)', () async {
      when(
        () => mockRemoteDataSource.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) async => right(_dto));
      when(
        () => mockBox.put(any(), any()),
      ).thenThrow(Exception('disk full'));

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
    test(
      'a remote Failure (e.g. offline) passes through as Left, the Hive '
      'box is never touched',
      () async {
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
      },
    );
  });
}
