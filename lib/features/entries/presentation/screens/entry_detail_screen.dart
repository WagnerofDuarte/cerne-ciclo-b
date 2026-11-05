import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/back_arrow_header.dart';
import '../../domain/entities/entry.dart';
import '../cubit/entry_detail_cubit.dart';
import '../cubit/entry_detail_state.dart';
import '../widgets/sync_badge.dart';

/// `/meus-registros/:id`'s screen (spec-4-4) — strictly read-only: content,
/// source, local time, and a `SyncBadge` with no `onRetryTap` (a fetched
/// Entry is always server-confirmed, Boundaries) — zero edit affordance
/// anywhere. This screen has no prototype precedent to match (Intent), so
/// its layout is a plain reuse of existing tokens rather than a ported
/// `cerne-prototype.html` block.
///
/// [cubit] is a DI `factory` (Code Map), already constructed *and* loading
/// by the time this widget is built (`app_router.dart`'s own `GoRoute.
/// builder` cascade — it resolves a fresh `EntryDetailCubit` from `sl` and
/// immediately calls `load(id)` on it) — this `StatefulWidget`'s only job
/// over that is owning its disposal: unlike
/// `MeusRegistrosScreen`'s shared `lazySingleton` (never closed by the
/// screen), each visit to this route gets its own throwaway instance, so
/// [dispose] closes it.
class EntryDetailScreen extends StatelessWidget {
  const EntryDetailScreen({required this.cubit, super.key});

  final EntryDetailCubit cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: _EntryDetailBody(cubit: cubit),
    );
  }
}

/// Split out of [EntryDetailScreen] (a `StatelessWidget`, so it can't own
/// `State.dispose` itself) purely to close [cubit] once this route is
/// popped — the one disposal responsibility `MeusRegistrosScreen`'s own
/// shared-singleton cubit never needs.
class _EntryDetailBody extends StatefulWidget {
  const _EntryDetailBody({required this.cubit});

  final EntryDetailCubit cubit;

  @override
  State<_EntryDetailBody> createState() => _EntryDetailBodyState();
}

class _EntryDetailBodyState extends State<_EntryDetailBody> {
  @override
  void dispose() {
    widget.cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: Column(
        children: [
          const BackArrowHeader(title: 'Registro'),
          Expanded(
            child: BlocBuilder<EntryDetailCubit, EntryDetailState>(
              builder: (context, state) => switch (state) {
                EntryDetailLoading() => const SizedBox.shrink(),
                EntryDetailData() => _DetailView(state: state),
                EntryDetailNotFound() => const _NotFoundView(),
                EntryDetailError() => const _NotFoundView(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One source's own Portuguese label — reuses the exact same `EntrySource`
/// keys `entry_record_card.dart`'s own `_sourceMeta` map does, "Texto"
/// matching `insertion_modal.dart`'s own tab label for a manually-typed
/// entry (Design Notes: no prototype precedent gives this screen its own
/// label set, so the existing capture-tab vocabulary is reused rather than
/// inventing a new one).
const _sourceLabel = <EntrySource, String>{
  EntrySource.manual: 'Texto',
  EntrySource.audio: 'Áudio',
  EntrySource.photo: 'Foto',
  EntrySource.chat: 'Chat',
};

class _DetailView extends StatelessWidget {
  const _DetailView({required this.state});

  final EntryDetailData state;

  @override
  Widget build(BuildContext context) {
    final entry = state.entry;
    final sourceLabel = _sourceLabel[entry.source] ?? '';
    final time = _formatLocalDateTime(entry.occurredAt);

    return SingleChildScrollView(
      padding: DesignTokens.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                sourceLabel,
                style: DesignTokens.textLabelMd.copyWith(
                  color: DesignTokens.colorTextSecondary,
                ),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Text(
                time,
                style: DesignTokens.textMonoCaption.copyWith(
                  color: DesignTokens.colorTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          Text(
            entry.content,
            style: DesignTokens.textBodyLg.copyWith(
              color: DesignTokens.colorTextPrimary,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          // No `onRetryTap` (Boundaries) — a fetched Entry is always
          // server-confirmed, so this badge is purely informational here.
          SyncBadge(state: state.badgeState),
        ],
      ),
    );
  }
}

/// RNF04 — the one generic treatment both `EntryDetailNotFound` and
/// `EntryDetailError` render (entry_detail_state.dart's own doc): identical
/// whether the id never existed, belongs to another user, or any other
/// non-absorbed `Failure` occurred — never a distinguishable
/// permission-denied (or failure-reason) state.
class _NotFoundView extends StatelessWidget {
  const _NotFoundView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: DesignTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              size: DesignTokens.entriesEmptyStateIconSize,
              color: DesignTokens.colorBorder,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              'Registro não encontrado',
              style: DesignTokens.textBodyMd.copyWith(
                color: DesignTokens.colorTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [Entry.occurredAt]'s local wall-clock date+time, `dd/mm/yyyy HH:mm` —
/// this screen's own detail-level format (distinct from `EntryRecordCard`'s
/// list-level `HH:mm`-only `_formatTime`, since a full date is only useful
/// once a single entry is in full view). A malformed [occurredAt] falls
/// back to a placeholder instead of throwing (RNF09), same rationale
/// `_formatTime` already documents.
String _formatLocalDateTime(String occurredAt) {
  final local = DateTime.tryParse(occurredAt)?.toLocal();
  if (local == null) {
    return '--/--/---- --:--';
  }
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}
