import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/entities/sync_badge_state.dart';

const _entry = Entry(
  id: 'e1',
  content: 'content',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

PendingEntryWrite _pendingWrite(PendingEntryWriteStatus status) =>
    PendingEntryWrite(
      tempId: 'temp-1',
      content: 'pending content',
      source: EntrySource.manual,
      mediaDurationSeconds: null,
      startedAt: DateTime(2026, 1, 1),
      status: status,
    );

/// Covers spec-4-2's own Tasks item: "unit tests (all 3 states, null/
/// non-null combos)" for `deriveSyncBadgeState()` — the one place this
/// app ever decides a card's badge.
void main() {
  group('deriveSyncBadgeState', () {
    test(
      'entry present, pending null -> SyncBadgeSynchronized (nothing '
      'pending for this entry)',
      () {
        expect(
          deriveSyncBadgeState(_entry, null),
          const SyncBadgeState.synchronized(),
        );
      },
    );

    test(
      'entry null, pending inFlight -> SyncBadgeSynchronizing',
      () {
        expect(
          deriveSyncBadgeState(
            null,
            _pendingWrite(const PendingEntryWriteInFlight()),
          ),
          const SyncBadgeState.synchronizing(),
        );
      },
    );

    test(
      'entry null, pending failed -> SyncBadgeError carrying the same '
      'Failure verbatim',
      () {
        const failure = Failure.networkTimeout(message: 'Timed out');
        final result = deriveSyncBadgeState(
          null,
          _pendingWrite(const PendingEntryWriteFailed(failure: failure)),
        );

        expect(result, isA<SyncBadgeError>());
        expect((result as SyncBadgeError).failure, failure);
      },
    );

    test(
      'both entry and pending non-null -> pending wins regardless of '
      'entry (pending is always the authoritative client-side signal, '
      'sync-badge.md)',
      () {
        expect(
          deriveSyncBadgeState(
            _entry,
            _pendingWrite(const PendingEntryWriteInFlight()),
          ),
          const SyncBadgeState.synchronizing(),
        );

        const failure = Failure.validation(message: 'Conteúdo inválido.');
        final errorResult = deriveSyncBadgeState(
          _entry,
          _pendingWrite(const PendingEntryWriteFailed(failure: failure)),
        );
        expect(errorResult, isA<SyncBadgeError>());
        expect((errorResult as SyncBadgeError).failure, failure);
      },
    );

    test(
      'both entry and pending null -> SyncBadgeSynchronized (unreachable '
      'from any real caller, but resolves rather than throwing, RNF09)',
      () {
        expect(
          deriveSyncBadgeState(null, null),
          const SyncBadgeState.synchronized(),
        );
      },
    );
  });

  group('SyncBadgeState equality', () {
    test('SyncBadgeSynchronizing instances are equal', () {
      expect(
        const SyncBadgeState.synchronizing(),
        const SyncBadgeState.synchronizing(),
      );
    });

    test('SyncBadgeSynchronized instances are equal', () {
      expect(
        const SyncBadgeState.synchronized(),
        const SyncBadgeState.synchronized(),
      );
    });

    test('SyncBadgeError instances with the same Failure are equal', () {
      expect(
        const SyncBadgeState.error(
          Failure.networkOffline(message: 'Sem conexão'),
        ),
        const SyncBadgeState.error(
          Failure.networkOffline(message: 'Sem conexão'),
        ),
      );
    });

    test('SyncBadgeError instances with different Failures are not equal', () {
      expect(
        const SyncBadgeState.error(
          Failure.networkOffline(message: 'Sem conexão'),
        ),
        isNot(
          const SyncBadgeState.error(
            Failure.networkTimeout(message: 'Timed out'),
          ),
        ),
      );
    });
  });
}
