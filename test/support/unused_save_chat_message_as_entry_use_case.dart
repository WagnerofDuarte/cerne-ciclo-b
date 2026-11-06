import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/usecases/save_chat_message_as_entry_use_case.dart';

/// Shared across every test that resolves a real `ChatCubit`/DI graph but
/// never exercises its spec-6-4 bookmark-save path — a stray call here is
/// itself the test failure, same convention every other touched suite's
/// "never expected to be called" fake already follows.
class UnusedSaveChatMessageAsEntryUseCase
    implements SaveChatMessageAsEntryUseCase {
  @override
  Future<Either<Failure, Entry>> call({
    required String content,
    required String chatMessageId,
  }) async => throw UnimplementedError('not expected to be called');
}
