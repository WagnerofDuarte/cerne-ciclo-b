import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/usecases/save_chat_message_as_entry_use_case.dart';

class MockEntriesRepository extends Mock implements EntriesRepository {}

const _entry = Entry(
  id: 'e1',
  content: 'oi, tudo bem?',
  source: EntrySource.chat,
  chatMessageId: 'srv-1',
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// spec-6-4 — asserts [SaveChatMessageAsEntryUseCaseImpl] forwards to
/// [EntriesRepository.create] with `source: EntrySource.chat` and the
/// given `content`/`chatMessageId` verbatim, and passes both `Right`/
/// `Left` through unmapped — this use case's own only job (Design Notes:
/// "it exists only to satisfy AGENTS.md's RF10 boundary").
void main() {
  late MockEntriesRepository mockRepository;
  late SaveChatMessageAsEntryUseCaseImpl useCase;

  setUpAll(() {
    registerFallbackValue(EntrySource.manual);
  });

  setUp(() {
    mockRepository = MockEntriesRepository();
    useCase = SaveChatMessageAsEntryUseCaseImpl(mockRepository);
  });

  test('forwards content/chatMessageId verbatim with source: EntrySource.chat, '
      'passing a Right through unmapped', () async {
    when(
      () => mockRepository.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
        chatMessageId: any(named: 'chatMessageId'),
      ),
    ).thenAnswer((_) async => right(_entry));

    final result = await useCase(
      content: 'oi, tudo bem?',
      chatMessageId: 'srv-1',
    );

    verify(
      () => mockRepository.create(
        content: 'oi, tudo bem?',
        source: EntrySource.chat,
        chatMessageId: 'srv-1',
      ),
    ).called(1);
    expect(result, right(_entry));
  });

  test('passes a Left(Failure) through unmapped', () async {
    const failure = Failure.networkOffline(message: 'Offline');
    when(
      () => mockRepository.create(
        content: any(named: 'content'),
        source: any(named: 'source'),
        chatMessageId: any(named: 'chatMessageId'),
      ),
    ).thenAnswer((_) async => left(failure));

    final result = await useCase(
      content: 'oi, tudo bem?',
      chatMessageId: 'srv-1',
    );

    expect(result, left(failure));
  });
}
