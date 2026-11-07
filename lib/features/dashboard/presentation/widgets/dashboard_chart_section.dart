import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/resource.dart';
import '../../domain/entities/dashboard_aggregate.dart';
import '../cubit/dashboard_cubit.dart';

/// "Sua evolução" — Story 8.1's own chart section on Configurações
/// (`cerne-prototype.html`'s Tela 6 dashboard block). Reads [DashboardCubit]
/// via `BlocBuilder` — `AccountSettingsScreen`'s own `MultiBlocProvider`
/// already makes it available higher up the tree, same convention
/// `MeusRegistrosScreen` already uses for its own two cubits.
///
/// The AI narrative paragraph is explicitly out of scope here (Story 8.2,
/// Intent/Never) — every branch below renders *at most* a short, hardcoded
/// Portuguese placeholder message, never anything derived from
/// `dashboard-narrative-get`.
class DashboardChartSection extends StatelessWidget {
  const DashboardChartSection({super.key});

  static const _emptyMessage =
      'Comece a registrar para ver sua evolução '
      'aqui';

  static const _oneEntryMessage =
      'Ainda é cedo pra ver um padrão — volte '
      'em alguns dias.';

  /// Boundaries: "`buckets` condensed to exactly 10 bars".
  static const _targetCondensedBars = 10;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sua evolução',
          style: DesignTokens.textHeadlineMd.copyWith(
            color: DesignTokens.colorTextPrimary,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        BlocBuilder<DashboardCubit, Resource<DashboardAggregate>>(
          builder: (context, state) => _buildBody(state),
        ),
      ],
    );
  }

  Widget _buildBody(Resource<DashboardAggregate> state) {
    return switch (state) {
      ResourceIdle<DashboardAggregate>() ||
      ResourceLoading<DashboardAggregate>() => _loadingCard(),
      ResourceError<DashboardAggregate>(failure: final failure) => _errorCard(
        failure.message,
      ),
      ResourceData<DashboardAggregate>(data: final aggregate) => _populatedCard(
        aggregate,
      ),
    };
  }

  /// Review finding (round 2): uses [DesignTokens.dashboardCardPadding] —
  /// same padding [_populatedCard]'s own card uses — rather than
  /// [DesignTokens.spacingLg], so the card doesn't visibly resize on every
  /// loading -> data transition (including a background `confirmedWrites`
  /// refresh, which never shows this state to begin with but would have on
  /// a slow repeated `load()`).
  Widget _loadingCard() => _card(
    padding: const EdgeInsets.all(DesignTokens.dashboardCardPadding),
    child: const Center(
      child: CircularProgressIndicator(color: DesignTokens.colorAccent),
    ),
  );

  /// I/O matrix: "Fetch fails -> ResourceError, inline error text, no
  /// crash" — same inline-error treatment `AccountSettingsScreen`'s own
  /// biometric-toggle failure already uses ([DesignTokens.textBodyMd] +
  /// [DesignTokens.colorError]). Padding matches [_loadingCard]'s own
  /// review-fix rationale above.
  Widget _errorCard(String message) => _card(
    padding: const EdgeInsets.all(DesignTokens.dashboardCardPadding),
    child: Text(
      message,
      style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorError),
    ),
  );

  /// I/O matrix: "Zero entries -> icon + 'Comece a registrar...'".
  Widget _emptyCard() => _card(
    padding: const EdgeInsets.all(DesignTokens.spacingLg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Review finding: a bare `Icon` with no `semanticLabel` is simply
        // excluded from the semantics tree (Flutter's own default) — a
        // screen-reader user hears nothing at all for it, relying entirely
        // on the text below. [_emptyMessage]'s own text already reads
        // naturally without the icon, so this label is purely additional
        // context, never a duplicate announcement of that same text.
        const Icon(
          Icons.show_chart,
          size: DesignTokens.dashboardEmptyStateIconSize,
          color: DesignTokens.colorBorder,
          semanticLabel: 'Gráfico de evolução vazio',
        ),
        const SizedBox(height: DesignTokens.dashboardEmptyStateGap),
        Text(
          _emptyMessage,
          textAlign: TextAlign.center,
          style: DesignTokens.textLabelMd.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
        ),
      ],
    ),
  );

  /// Boundaries' own count matrix: `0` is [_emptyCard]; `1` is exactly one
  /// full-height bar plus [_oneEntryMessage]; `>30` condenses
  /// [DashboardAggregate.bucketCounts] to exactly [_targetCondensedBars]
  /// bars via [_condense]; `2..30` renders one bar per bucket as-is — the
  /// "matrix gap" the frozen spec's own Boundaries line resolves per
  /// AGENTS.md's "decide and proceed". None of the non-zero branches ever
  /// renders text other than the `1`-count message (Boundaries: "no text").
  Widget _populatedCard(DashboardAggregate aggregate) {
    final totalCount = aggregate.totalCount;
    if (totalCount == 0) {
      return _emptyCard();
    }

    List<int> barCounts;
    String? message;
    if (totalCount == 1) {
      barCounts = const [1];
      message = _oneEntryMessage;
    } else if (totalCount > 30) {
      barCounts = _condense(aggregate.bucketCounts);
    } else {
      barCounts = aggregate.bucketCounts;
    }

    // Review finding (defensive guard): `totalCount > 0` with an empty
    // `bucketCounts` is contract-inconsistent (`totals.count` and the sum
    // of every `buckets[].count` should always agree) but not impossible
    // against malformed/inconsistent backend data — falls back to a
    // single bar for the whole [totalCount] rather than silently
    // rendering an empty bar row (RNF09: never a blank/broken-looking
    // screen over bad data).
    if (barCounts.isEmpty) {
      barCounts = [totalCount];
    }

    final maxCount = barCounts.fold(
      0,
      (max, count) => count > max ? count : max,
    );

    return _card(
      padding: const EdgeInsets.all(DesignTokens.dashboardCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Review finding: each bar is a bare, unlabeled `Container` —
          // wrapping the whole row in one summarizing `Semantics` label
          // (and excluding the individual bars from the semantics tree)
          // gives a screen-reader user one meaningful announcement
          // instead of N anonymous elements.
          Semantics(
            label:
                'Gráfico de evolução: $totalCount registros no período, '
                'em ${barCounts.length} barras.',
            child: ExcludeSemantics(
              child: SizedBox(
                height: DesignTokens.dashboardBarAreaHeight,
                child: Row(
                  spacing: DesignTokens.spacingSm,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final count in barCounts)
                      DashboardChartBar(
                        heightFraction: maxCount == 0 ? 0 : count / maxCount,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              message,
              style: DesignTokens.textLabelMd.copyWith(
                color: DesignTokens.colorTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Boundaries (amended, Spec Change Log): "`bucketCounts` left-padded
  /// with leading zero-count entries to length 10 (when shorter) *before*
  /// condensing... via 10 contiguous index chunks, summed `count`,
  /// remainder in the last chunk". The original, frozen wording degenerated
  /// whenever `bucketCounts.length < _targetCondensedBars`: the floor-
  /// division chunk size was `0`, so the first 9 chunks each summed an
  /// *empty* range (always `0`) and the 10th silently absorbed the entire
  /// total — 9 invisible bars + 1 giant one, defeating the chart for any
  /// user whose activity concentrates into fewer than 10 distinct backend
  /// buckets while still exceeding 30 entries. [_pad] below removes that
  /// degeneracy: once [bucketCounts] is at least [_targetCondensedBars]
  /// long (real data, or zero-padded), the same "first 9 chunks of
  /// `length ~/ 10`, 10th absorbs the remainder" chunking produces a
  /// non-degenerate spread — leading zero bars, then the real data at the
  /// end, for a short [bucketCounts]. Always exactly [_targetCondensedBars]
  /// ints out, regardless of `bucketCounts.length` (I/O matrix: "`>30`
  /// entries, any `buckets.length`").
  static List<int> _condense(List<int> bucketCounts) {
    final padded = _pad(bucketCounts);
    final chunkSize = padded.length ~/ _targetCondensedBars;
    final condensed = <int>[];
    var index = 0;
    for (var i = 0; i < _targetCondensedBars - 1; i++) {
      final end = index + chunkSize;
      condensed.add(_sum(padded, index, end));
      index = end;
    }
    condensed.add(_sum(padded, index, padded.length));
    return condensed;
  }

  /// Left-pads [bucketCounts] with leading zero-count entries up to
  /// [_targetCondensedBars] — a no-op once [bucketCounts] already has at
  /// least that many entries (Boundaries: "when shorter").
  static List<int> _pad(List<int> bucketCounts) {
    if (bucketCounts.length >= _targetCondensedBars) {
      return bucketCounts;
    }
    return [
      ...List<int>.filled(_targetCondensedBars - bucketCounts.length, 0),
      ...bucketCounts,
    ];
  }

  static int _sum(List<int> list, int start, int end) {
    var total = 0;
    for (var i = start; i < end; i++) {
      total += list[i];
    }
    return total;
  }

  Widget _card({required EdgeInsets padding, required Widget child}) {
    return Container(
      padding: padding,
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusMd)),
        boxShadow: DesignTokens.elevation1,
      ),
      child: child,
    );
  }
}

/// One chart bar — a `cerne-prototype.html` `chartBars` entry
/// (`flex:1;background:#C98A3E;border-radius:4px 4px 0 0`). [heightFraction]
/// is `count / maxCount` for whichever bars [DashboardChartSection] is
/// currently showing (Boundaries: "Bar height ∝ count / max count shown"),
/// clamped to `[0, 1]` by its own caller.
class DashboardChartBar extends StatelessWidget {
  const DashboardChartBar({required this.heightFraction, super.key});

  final double heightFraction;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: DesignTokens.dashboardBarAreaHeight * heightFraction,
        decoration: const BoxDecoration(
          color: DesignTokens.colorAccent,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(DesignTokens.dashboardBarRadius),
            topRight: Radius.circular(DesignTokens.dashboardBarRadius),
          ),
        ),
      ),
    );
  }
}
