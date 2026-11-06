import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/entry.dart';
import '../repositories/entries_repository.dart';

/// spec-6-4 — the shared interface/use case AGENTS.md's RF10 rule
/// requires: `ChatCubit` depends on this port only, never on
/// [EntriesRepository] directly, never on anything under `entries/data/`
/// or `entries/presentation/` (RNF06). Port+impl in one file, pure domain
/// (no `package:flutter`/`data` import), mirrors `PendingEntryWriteTracker`'s
/// own structural convention.
///
/// Deliberately narrower than [EntriesRepository.create] — only [content]/
/// [chatMessageId], `source` is implicit ([EntrySource.chat]) — this is
/// the one caller that only ever needs that source, and this port exists
/// solely to satisfy the RF10 layering boundary, not to become a general-
/// purpose entries port (Design Notes): a future caller needing more of
/// [EntriesRepository.create]'s own surface gets its own use case rather
/// than this one growing extra optional params.
abstract class SaveChatMessageAsEntryUseCase {
  Future<Either<Failure, Entry>> call({
    required String content,
    required String chatMessageId,
  });
}

/// Default implementation — forwards verbatim to
/// [EntriesRepository.create] with `source: EntrySource.chat`.
/// [EntriesRepository] is this use case's own only caller-facing
/// dependency, and its own only caller (Never: "bypass EntriesRepository").
class SaveChatMessageAsEntryUseCaseImpl
    implements SaveChatMessageAsEntryUseCase {
  SaveChatMessageAsEntryUseCaseImpl(EntriesRepository repository)
    : _repository = repository;

  final EntriesRepository _repository;

  @override
  Future<Either<Failure, Entry>> call({
    required String content,
    required String chatMessageId,
  }) => _repository.create(
    content: content,
    source: EntrySource.chat,
    chatMessageId: chatMessageId,
  );
}
