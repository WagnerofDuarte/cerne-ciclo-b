import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/back_arrow_header.dart';
import '../../domain/entities/entry_date_group.dart';
import '../cubit/meus_registros_cubit.dart';
import '../cubit/meus_registros_state.dart';
import '../widgets/entry_record_card.dart';
import '../widgets/entry_skeleton_card.dart';

/// Tela 4 — Meus Registros, spec-4-1's real build: every `Entry`,
/// newest-first, grouped by day, each card marked by origin. Replaces the
/// former `MeusRegistrosPlaceholderScreen`.
///
/// [cubit] is a DI `lazySingleton` (Code Map) — this `StatefulWidget` never
/// closes it (`BlocProvider.value`, same convention
/// `AccountSettingsScreen` already uses for its own singleton cubit); only
/// this screen's own [ScrollController] is this `State`'s to dispose.
///
/// The global `ExpiryOverlayHost` shows its "Sessão expirada" dialog via
/// `showGeneralDialog` on the `Navigator` *above* this screen's own widget
/// subtree (`expiry_overlay_host.dart`) — this screen is never popped or
/// rebuilt from scratch underneath it, so [_scrollController]'s position
/// and [cubit]'s state survive that overlay appearing with no extra code
/// needed here (Acceptance Criteria's third bullet).
class MeusRegistrosScreen extends StatefulWidget {
  const MeusRegistrosScreen({required this.cubit, super.key});

  final MeusRegistrosCubit cubit;

  @override
  State<MeusRegistrosScreen> createState() => _MeusRegistrosScreenState();
}

class _MeusRegistrosScreenState extends State<MeusRegistrosScreen> {
  // RNF01: no loading UI below 300ms — same threshold/`Timer` pattern as
  // `BootSplashScreen`.
  static const _skeletonThreshold = Duration(milliseconds: 300);

  final ScrollController _scrollController = ScrollController();
  Timer? _skeletonTimer;
  bool _showSkeleton = false;

  @override
  void initState() {
    super.initState();
    widget.cubit.loadFirstPage();
    _skeletonTimer = Timer(_skeletonThreshold, () {
      if (mounted) {
        setState(() => _showSkeleton = true);
      }
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _skeletonTimer?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    // Pre-fetches a little before the exact end (reusing `spacing2xl`
    // purely as a scroll-distance buffer, not a new literal) for a
    // smoother scroll-pagination feel; `loadMore()` itself is a no-op once
    // there's no further page or a call is already in flight.
    if (position.pixels >= position.maxScrollExtent - DesignTokens.spacing2xl) {
      widget.cubit.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: widget.cubit,
      child: Scaffold(
        backgroundColor: DesignTokens.colorSurfaceBg,
        body: Column(
          children: [
            const BackArrowHeader(title: 'Meus Registros'),
            Expanded(
              child: BlocBuilder<MeusRegistrosCubit, MeusRegistrosState>(
                builder: (context, state) => switch (state) {
                  MeusRegistrosLoading() =>
                    _showSkeleton
                        ? const _SkeletonList()
                        : const SizedBox.shrink(),
                  MeusRegistrosEmpty() => const _EmptyState(),
                  MeusRegistrosError(message: final message) => _ErrorState(
                    message: message,
                    onRetry: widget.cubit.loadFirstPage,
                  ),
                  MeusRegistrosLoaded() => _EntryList(
                    state: state,
                    scrollController: _scrollController,
                    onRetryLoadMore: widget.cubit.retryLoadMore,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  // Not a real count of anything server-sent — just enough placeholder
  // cards to fill a typical screen while the first page is in flight.
  static const _placeholderCount = 4;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: DesignTokens.screenPadding,
      itemCount: _placeholderCount,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
        child: const EntrySkeletonCard(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // Boundaries: "polished empty-state CTA (4.3) — plain 'no entries yet'
    // text only" this story.
    return Center(
      child: Text(
        'Nenhum registro ainda.',
        style: DesignTokens.textBodyMd.copyWith(
          color: DesignTokens.colorTextSecondary,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: DesignTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: DesignTokens.textBodyMd.copyWith(
                color: DesignTokens.colorTextPrimary,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Tentar novamente',
                style: DesignTokens.textLabelMd.copyWith(
                  color: DesignTokens.colorPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.state,
    required this.scrollController,
    required this.onRetryLoadMore,
  });

  final MeusRegistrosLoaded state;
  final ScrollController scrollController;
  final VoidCallback onRetryLoadMore;

  @override
  Widget build(BuildContext context) {
    final groups = state.groups;
    return ListView.builder(
      controller: scrollController,
      padding: DesignTokens.screenPadding,
      itemCount: groups.length + 1,
      itemBuilder: (context, index) {
        if (index == groups.length) {
          return _LoadMoreFooter(
            hasMore: state.nextCursor != null,
            isLoading: state.isLoadingMore,
            failed: state.loadMoreFailed,
            onRetry: onRetryLoadMore,
          );
        }
        return _DateGroupSection(group: groups[index]);
      },
    );
  }
}

class _DateGroupSection extends StatelessWidget {
  const _DateGroupSection({required this.group});

  final EntryDateGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dayLabel(group.date),
            style: DesignTokens.textTitleSm.copyWith(
              color: DesignTokens.colorTextPrimary,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          for (final entry in group.entries) ...[
            EntryRecordCard(entry: entry),
            const SizedBox(height: DesignTokens.spacingSm),
          ],
        ],
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.hasMore,
    required this.isLoading,
    required this.failed,
    required this.onRetry,
  });

  final bool hasMore;
  final bool isLoading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
        child: Center(
          child: TextButton(
            onPressed: onRetry,
            child: Text(
              'Tentar novamente',
              style: DesignTokens.textLabelMd.copyWith(
                color: DesignTokens.colorPrimary,
              ),
            ),
          ),
        ),
      );
    }
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
        child: Center(
          child: CircularProgressIndicator(color: DesignTokens.colorPrimary),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// "Hoje"/"Ontem"/`dd/mm/yyyy` — presentation's own job (Code Map: day
/// labels aren't the pure `groupEntriesByDate()`'s concern). [date] is
/// always already truncated to local midnight (`EntryDateGroup`'s own
/// contract).
String _dayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (date == today) {
    return 'Hoje';
  }
  if (date == yesterday) {
    return 'Ontem';
  }
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}
