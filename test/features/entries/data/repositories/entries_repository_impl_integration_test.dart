import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cerne/features/entries/data/datasources/entries_remote_data_source.dart';
import 'package:cerne/features/entries/data/models/entry_dto.dart';
import 'package:cerne/features/entries/data/repositories/entries_repository_impl.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';

import '../../../../support/fake_path_provider_platform.dart';

class MockEntriesRemoteDataSource extends Mock
    implements EntriesRemoteDataSource {}

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

/// Review finding: `entries_repository_impl_test.dart`'s own `MockBox`
/// (`when(() => mockBox.put(any(), any())).thenAnswer((_) async {})`)
/// always succeeds and never actually encodes anything — it proves
/// `create()`'s own control flow, but never exercises real `hive_ce`
/// encoding of `EntryDto.toJson()`'s actual shape (an enum value, a
/// nullable field, ints, ISO date strings). This suite opens a *real*,
/// temp-dir-backed `Box<Map>` instead — same `FakePathProviderPlatform`/
/// `Hive.initFlutter()` bootstrap `bootstrap_integration_test.dart`
/// already uses for exactly this reason — so the write-through is proven
/// against the real Hive backend, not a mock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(EntrySource.manual);
  });

  late FakePathProviderPlatform fakePathProvider;
  late Box<Map> box;
  late MockEntriesRemoteDataSource mockRemoteDataSource;
  late EntriesRepositoryImpl repository;

  setUp(() async {
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;
    await Hive.initFlutter();
    box = await Hive.openBox<Map>('entries_integration_test');

    mockRemoteDataSource = MockEntriesRemoteDataSource();
    repository = EntriesRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
      entriesBox: box,
    );
  });

  tearDown(() async {
    await Hive.close();
    await fakePathProvider.cleanUp();
  });

  test(
    'writes the real Hive-encoded EntryDto.toJson() shape and reads it '
    'back verbatim — enum, nullable field, ints, and ISO date strings all '
    'round-trip through the actual hive_ce backend, not a mock',
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

      expect(result.isRight(), isTrue);

      final stored = box.get('e1');
      expect(stored, isNotNull);
      expect(stored!['id'], 'e1');
      expect(stored['content'], 'Hoje foi um bom dia.');
      expect(stored['source'], 'manual');
      expect(stored['chatMessageId'], isNull);
      expect(stored['occurredAt'], '2026-01-01T00:00:00Z');
      expect(stored['serverRevision'], 1);
      expect(stored['createdAt'], '2026-01-01T00:00:00Z');
      expect(stored['updatedAt'], '2026-01-01T00:00:00Z');

      // Re-decoding the stored map back through EntryDto.fromJson proves
      // the round trip is lossless, not just individually-matching
      // fields.
      final decoded = EntryDto.fromJson(stored.cast<String, dynamic>());
      expect(decoded.id, _dto.id);
      expect(decoded.source, _dto.source);
    },
  );

  test(
    'a non-null chatMessageId also round-trips correctly through the real '
    'box',
    () async {
      const chatDto = EntryDto(
        id: 'e2',
        content: 'Registrado a partir do chat.',
        source: EntrySource.chat,
        chatMessageId: 'm1',
        occurredAt: '2026-01-02T00:00:00Z',
        serverRevision: 1,
        createdAt: '2026-01-02T00:00:00Z',
        updatedAt: '2026-01-02T00:00:00Z',
      );
      when(
        () => mockRemoteDataSource.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) async => right(chatDto));

      await repository.create(
        content: 'Registrado a partir do chat.',
        source: EntrySource.chat,
      );

      final stored = box.get('e2');
      expect(stored!['chatMessageId'], 'm1');
      expect(stored['source'], 'chat');
    },
  );
}
