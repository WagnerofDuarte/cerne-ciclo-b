import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/navigation/app_route_paths.dart';
import '../../../../core/resource.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/back_arrow_header.dart';
import '../../../capture/presentation/cubit/audio_entry_cubit.dart';
import '../../../capture/presentation/cubit/photo_entry_cubit.dart';
import '../../../capture/presentation/cubit/text_entry_cubit.dart';
import '../../../capture/presentation/widgets/insertion_modal.dart';
import '../../domain/entities/entry.dart';
import '../../domain/entities/entry_date_group.dart';
import '../../domain/entities/sync_badge_state.dart';
import '../cubit/entries_search_cubit.dart';
import '../cubit/meus_registros_cubit.dart';
import '../cubit/meus_registros_state.dart';
import '../widgets/entries_filter_sheet.dart';
import '../widgets/entries_search_bar.dart';
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
  const MeusRegistrosScreen({
    required this.cubit,
    required this.searchCubit,
    super.key,
  });

  final MeusRegistrosCubit cubit;

  /// spec-5-1 — the permanently-docked `EntriesSearchBar`'s own cubit, a DI
  /// `lazySingleton` like [cubit] (Code Map); this `StatefulWidget` never
  /// closes it either, same rationale [cubit]'s own doc above gives.
  final EntriesSearchCubit searchCubit;

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

  /// spec-5-1 — the search surface's own 300ms skeleton threshold,
  /// mirroring [_skeletonTimer]/[_showSkeleton] above but keyed off
  /// `EntriesSearchCubit`'s `ResourceLoading` rather than
  /// `MeusRegistrosLoading`: started fresh on every transition into
  /// `ResourceLoading` (`_onSearchStateChanged` below), since unlike the
  /// first-load timer above (started once, in [initState]) a search can
  /// enter/leave loading many times across one screen visit.
  Timer? _searchSkeletonTimer;
  bool _showSearchSkeleton = false;

  /// Review fix (round 2, spec-4-4) — guards `_openDetail` against a rapid
  /// double-tap on a card pushing `/meus-registros/:id` twice (stacking two
  /// detail-route instances); cleared once the pushed route is popped, via
  /// `whenComplete` below.
  bool _navigatingToDetail = false;

  @override
  void initState() {
    super.initState();
    widget.cubit.loadFirstPage();
    // spec-5-3 — both `cubit`/`searchCubit` are `lazySingleton`s (Code
    // Map): a fresh mount of this screen must reset both, not just
    // `cubit`'s own filters above, or a re-entered screen would carry a
    // stale filter selection from a previous visit into a still-active
    // search (Boundaries: "Re-enter screen after a prior combined
    // session").
    widget.searchCubit.updateFilters(
      source: null,
      dateFrom: null,
      dateTo: null,
    );
    _skeletonTimer = Timer(_skeletonThreshold, () {
      if (mounted) {
        setState(() => _showSkeleton = true);
      }
    });
    _scrollController.addListener(_onScroll);
    // Review finding: `searchCubit` is a long-lived singleton (Code Map)
    // that can already be `ResourceLoading` the moment this `State` is
    // (re)created — e.g. the user switches tabs away mid-search and back,
    // which tears down and rebuilds this plain `GoRoute`'s widget while the
    // DI-singleton cubit keeps running. `BlocConsumer`'s `listener` below
    // only fires on a *new* state, never for one already current at
    // subscription time, so without this check the search skeleton would
    // never arm for an in-flight search resumed this way.
    if (widget.searchCubit.state is ResourceLoading<List<Entry>>) {
      _searchSkeletonTimer = Timer(_skeletonThreshold, () {
        if (mounted) {
          setState(() => _showSearchSkeleton = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _skeletonTimer?.cancel();
    _searchSkeletonTimer?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// `BlocConsumer<EntriesSearchCubit, ...>`'s own listener (below) — starts
  /// [_searchSkeletonTimer] fresh on every transition into
  /// `ResourceLoading`, mirroring [initState]'s one-shot [_skeletonTimer]
  /// but re-armed per search rather than once per screen visit; any other
  /// state (including a fast resolve before the 300ms threshold, RNF01)
  /// cancels it and resets [_showSearchSkeleton].
  void _onSearchStateChanged(
    BuildContext context,
    Resource<List<Entry>> state,
  ) {
    _searchSkeletonTimer?.cancel();
    if (state is ResourceLoading<List<Entry>>) {
      _searchSkeletonTimer = Timer(_skeletonThreshold, () {
        if (mounted) {
          setState(() => _showSearchSkeleton = true);
        }
      });
      return;
    }
    if (_showSearchSkeleton) {
      setState(() => _showSearchSkeleton = false);
    }
  }

  void _openDetail(Entry entry) {
    if (_navigatingToDetail) {
      return;
    }
    _navigatingToDetail = true;
    context
        .push(
          '${AppRoutePaths.meusRegistros}/'
          '${Uri.encodeComponent(entry.id)}',
        )
        .whenComplete(() {
          if (mounted) {
            setState(() => _navigatingToDetail = false);
          } else {
            _navigatingToDetail = false;
          }
        });
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
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: widget.cubit),
        BlocProvider.value(value: widget.searchCubit),
      ],
      child: Scaffold(
        backgroundColor: DesignTokens.colorSurfaceBg,
        body: Column(
          children: [
            const BackArrowHeader(title: 'Meus Registros'),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacingMd,
                DesignTokens.spacingMd,
                DesignTokens.spacingMd,
                0,
              ),
              // spec-5-2: `hasActiveFilters`/`onFilterTap` need the real
              // `MeusRegistrosCubit` — this now rebuilds on its state too,
              // while `EntriesSearchBar` itself stays a dumb, stateless
              // widget, same as before. spec-5-3 (Boundaries: "Funnel fill
              // ... drops its ResourceIdle gate — becomes
              // widget.cubit.hasActiveFilters unconditionally"): a filter
              // now also narrows an active search (via `searchCubit.
              // updateFilters()`), so the funnel reads as "filled"
              // whenever a filter is active, regardless of which surface
              // — plain timeline or search results — is currently on
              // screen; no `EntriesSearchCubit` rebuild needed here
              // anymore.
              child: BlocBuilder<MeusRegistrosCubit, MeusRegistrosState>(
                builder: (context, _) => EntriesSearchBar(
                  onChanged: widget.searchCubit.onQueryChanged,
                  onFilterTap: () => EntriesFilterSheet.show(
                    context,
                    cubit: widget.cubit,
                    searchCubit: widget.searchCubit,
                  ),
                  hasActiveFilters: widget.cubit.hasActiveFilters,
                ),
              ),
            ),
            Expanded(
              child: BlocConsumer<EntriesSearchCubit, Resource<List<Entry>>>(
                listener: _onSearchStateChanged,
                builder: (context, searchState) {
                  // Boundaries: "an empty query reverts to the normal
                  // timeline" — `ResourceIdle` is the only variant that
                  // falls through to the pre-existing
                  // `MeusRegistrosCubit`-driven timeline below; every other
                  // variant renders the search surface instead.
                  if (searchState is ResourceIdle<List<Entry>>) {
                    return BlocBuilder<MeusRegistrosCubit, MeusRegistrosState>(
                      builder: (context, state) {
                        final timeline = switch (state) {
                          MeusRegistrosLoading() =>
                            _showSkeleton
                                ? const _SkeletonList()
                                : const SizedBox.shrink(),
                          MeusRegistrosEmpty() => const _EmptyState(),
                          MeusRegistrosError(message: final message) =>
                            _ErrorState(
                              message: message,
                              // Code-review fix: `retryCurrentPage()`, not
                              // `loadFirstPage()` — the latter resets the
                              // active filter selection, silently turning
                              // a failed *filtered* retry into a
                              // successful unfiltered one.
                              onRetry: widget.cubit.retryCurrentPage,
                            ),
                          MeusRegistrosLoaded() => _EntryList(
                            state: state,
                            scrollController: _scrollController,
                            onRetryLoadMore: widget.cubit.retryLoadMore,
                            onRetryTap: (entry) => widget.cubit.retry(entry.id),
                            onCardTap: _openDetail,
                          ),
                        };
                        // spec-5-2/5-3: the active-filter chip row renders
                        // here whenever a filter is active — this branch
                        // (plain/filtered timeline) or the search-results
                        // branch below, same condition either way (spec-5-3
                        // Boundaries: "`_ActiveFiltersRow` renders above
                        // `_SearchResults` too, same condition").
                        if (!widget.cubit.hasActiveFilters) {
                          return timeline;
                        }
                        return Column(
                          children: [
                            _ActiveFiltersRow(
                              cubit: widget.cubit,
                              searchCubit: widget.searchCubit,
                            ),
                            Expanded(child: timeline),
                          ],
                        );
                      },
                    );
                  }
                  final searchResults = _SearchResults(
                    state: searchState,
                    showSkeleton: _showSearchSkeleton,
                    onCardTap: _openDetail,
                  );
                  if (!widget.cubit.hasActiveFilters) {
                    return searchResults;
                  }
                  return Column(
                    children: [
                      _ActiveFiltersRow(
                        cubit: widget.cubit,
                        searchCubit: widget.searchCubit,
                      ),
                      Expanded(child: searchResults),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// spec-5-1's own search-results surface — `EntriesSearchCubit`'s
/// `Resource<List<Entry>>` rendered in place of the timeline whenever
/// [state] isn't `ResourceIdle` (the screen's own `build` filters that
/// variant out before ever reaching here). Every result here is always a
/// server-confirmed [Entry] (`EntriesRepository.search()`'s own contract —
/// no cache fallback, no pending-write overlay), so every card's badge is
/// unconditionally [SyncBadgeState.synchronized] — never recomputed via
/// `deriveSyncBadgeState()` (Never: "any screen recomputing badge state
/// inline" extends here too, there is simply no pending/offline state for
/// a search result to derive).
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.state,
    required this.showSkeleton,
    required this.onCardTap,
  });

  final Resource<List<Entry>> state;
  final bool showSkeleton;
  final void Function(Entry entry) onCardTap;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      ResourceIdle<List<Entry>>() =>
        // Unreachable — `MeusRegistrosScreen.build` never routes
        // `ResourceIdle` here — kept only so this switch stays exhaustive.
        const SizedBox.shrink(),
      ResourceLoading<List<Entry>>() =>
        showSkeleton ? const _SkeletonList() : const SizedBox.shrink(),
      ResourceError<List<Entry>>(failure: final failure) => _SearchErrorState(
        message: failure.message,
      ),
      ResourceData<List<Entry>>(data: final entries) =>
        entries.isEmpty
            ? const _EmptySearchResults()
            : ListView.builder(
                padding: DesignTokens.screenPadding,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    key: ValueKey(entry.id),
                    padding: const EdgeInsets.only(
                      bottom: DesignTokens.spacingSm,
                    ),
                    child: EntryRecordCard(
                      entry: entry,
                      badgeState: const SyncBadgeState.synchronized(),
                      onTap: () => onCardTap(entry),
                    ),
                  );
                },
              ),
    };
  }
}

/// `ResourceError<List<Entry>>`'s own rendering (spec-5-1 I/O matrix:
/// "ResourceError(networkOffline) rendered") — just the message, unlike
/// [_ErrorState] above: there is no retry affordance named for search
/// anywhere in Boundaries/the I/O matrix, since the user's own next
/// keystroke (re-debounced through `EntriesSearchCubit`) is what retries,
/// never an explicit button.
class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: DesignTokens.screenPadding,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: DesignTokens.textBodyMd.copyWith(
            color: DesignTokens.colorTextPrimary,
          ),
        ),
      ),
    );
  }
}

class _EmptySearchResults extends StatelessWidget {
  const _EmptySearchResults();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: DesignTokens.screenPadding,
        child: Text(
          'Nenhum resultado encontrado',
          textAlign: TextAlign.center,
          style: DesignTokens.textBodyMd.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
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
    // Tela 4 — Vazio: icon + copy + a primary CTA that opens the same
    // Insertion Modal the Home/Chat "+" FAB opens (`placeholder_screens.
    // dart`'s own call shape, mirrored verbatim) — spec-4-3.
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.entriesEmptyStateVerticalPadding,
          horizontal: DesignTokens.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: DesignTokens.entriesEmptyStateIconSize,
              color: DesignTokens.colorBorder,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              'Nenhum registro ainda',
              style: DesignTokens.textBodyMd.copyWith(
                color: DesignTokens.colorTextSecondary,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            AppButton(
              label: 'Criar primeiro registro',
              onPressed: () => InsertionModal.show(
                context,
                cubit: sl<TextEntryCubit>(),
                audioCubit: sl<AudioEntryCubit>(),
                photoCubit: sl<PhotoEntryCubit>(),
              ),
            ),
          ],
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
    required this.onRetryTap,
    required this.onCardTap,
  });

  final MeusRegistrosLoaded state;
  final ScrollController scrollController;
  final VoidCallback onRetryLoadMore;
  final void Function(Entry entry) onRetryTap;

  /// spec-4-4 — opens `EntryDetailScreen` for the tapped card.
  final void Function(Entry entry) onCardTap;

  @override
  Widget build(BuildContext context) {
    final groups = state.groups;
    // A non-empty `state.entries` can still yield zero groups if every one
    // of its `occurredAt` values is malformed (`groupEntriesByDate()` skips
    // rather than throws) — fall back to the same plain empty-state text
    // rather than rendering a ListView with nothing visibly in it.
    if (groups.isEmpty) {
      return const _EmptyState();
    }
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
        return _DateGroupSection(
          group: groups[index],
          badgeFor: state.badgeFor,
          onRetryTap: onRetryTap,
          onCardTap: onCardTap,
        );
      },
    );
  }
}

class _DateGroupSection extends StatelessWidget {
  const _DateGroupSection({
    required this.group,
    required this.badgeFor,
    required this.onRetryTap,
    required this.onCardTap,
  });

  final EntryDateGroup group;

  /// `MeusRegistrosLoaded.badgeFor` — the one call site outside the
  /// cubit/state itself (Never: "any screen recomputing badge state
  /// inline").
  final SyncBadgeState Function(Entry entry) badgeFor;

  /// `MeusRegistrosCubit.retry`, pre-bound to this entry's own id —
  /// `EntryRecordCard`/`SyncBadge` only ever call this for a retryable
  /// error badge.
  final void Function(Entry entry) onRetryTap;

  /// spec-4-4 — `EntryRecordCard`'s own `onTap`, pre-bound to this entry's
  /// own id.
  final void Function(Entry entry) onCardTap;

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
            EntryRecordCard(
              key: ValueKey(entry.id),
              entry: entry,
              badgeState: badgeFor(entry),
              onTap: () => onCardTap(entry),
              onRetryTap: () => onRetryTap(entry),
            ),
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

/// spec-5-2 — the active-filter chip row rendered under the search bar
/// whenever `MeusRegistrosCubit.hasActiveFilters` is true (Boundaries);
/// reads the cubit's own filter fields directly rather than threading them
/// through `MeusRegistrosState` (Design Notes: a filter change already
/// re-emits a new state via `applyFilters()`/`clearFilters()`, so this
/// widget's own `BlocBuilder` ancestor already rebuilds it in lockstep).
class _ActiveFiltersRow extends StatelessWidget {
  const _ActiveFiltersRow({required this.cubit, required this.searchCubit});

  final MeusRegistrosCubit cubit;

  /// spec-5-3 — `MeusRegistrosScreen`'s own bridge to
  /// `EntriesSearchCubit` (Design Notes): every filter-mutating call site
  /// below also calls this cubit's own `updateFilters()`, right alongside
  /// [cubit]'s `applyFilters()`/`clearFilters()`, so a filter change
  /// during an active search is reflected there too.
  final EntriesSearchCubit searchCubit;

  @override
  Widget build(BuildContext context) {
    final source = cubit.activeSource;
    final dateFrom = cubit.activeDateFrom;
    final dateTo = cubit.activeDateTo;
    final dateRangePreset = cubit.activeDateRangePreset;
    final hasDateRange = dateFrom != null && dateTo != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
        DesignTokens.spacingMd,
        0,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: DesignTokens.spacingSm,
        runSpacing: DesignTokens.spacingSm,
        children: [
          if (source != null)
            _ActiveFilterChip(
              label: entrySourceLabel(source),
              // I/O matrix: "Remove one of two active chips" — re-applies
              // every *other* active filter exactly as it stood, dropping
              // only this one. Round-2 review fix: passes `dateRangePreset`
              // back in too — otherwise the still-active date range would
              // revert to the cubit's default "Todo o período" preset.
              onRemove: () {
                cubit.applyFilters(
                  dateFrom: dateFrom,
                  dateTo: dateTo,
                  dateRangePreset: dateRangePreset,
                );
                searchCubit.updateFilters(dateFrom: dateFrom, dateTo: dateTo);
              },
            ),
          if (hasDateRange)
            _ActiveFilterChip(
              label: dateRangePresetLabel(dateRangePreset),
              onRemove: () {
                cubit.applyFilters(source: source);
                searchCubit.updateFilters(source: source);
              },
            ),
          AppButton(
            variant: AppButtonVariant.textGhost,
            label: 'Limpar filtros',
            // I/O matrix: "Clear all filters" — restores the full
            // unfiltered list in place, no reload/re-mount (Boundaries).
            onPressed: () {
              cubit.clearFilters();
              searchCubit.updateFilters();
            },
          ),
        ],
      ),
    );
  }
}

/// One removable active-filter chip — `colorSecondary`/
/// `colorCategoryChipText`/`radiusFull` (Boundaries: exact token reuse,
/// no new token).
class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, remover filtro',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.radiusFull),
        ),
        onTap: onRemove,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
            vertical: DesignTokens.spacingXs,
          ),
          decoration: const BoxDecoration(
            color: DesignTokens.colorSecondary,
            borderRadius: BorderRadius.all(
              Radius.circular(DesignTokens.radiusFull),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: DesignTokens.textLabelMd.copyWith(
                  color: DesignTokens.colorCategoryChipText,
                ),
              ),
              const SizedBox(width: DesignTokens.spacingXs),
              const Icon(
                Icons.close,
                color: DesignTokens.colorCategoryChipText,
              ),
            ],
          ),
        ),
      ),
    );
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
