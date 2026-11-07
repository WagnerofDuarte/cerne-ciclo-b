import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/resource.dart';
import '../../../entries/domain/entities/entry.dart';
import '../../../entries/domain/services/pending_entry_write_tracker.dart';
import '../../domain/entities/dashboard_aggregate.dart';
import '../../domain/repositories/dashboard_repository.dart';

/// Drives `DashboardChartSection`/Configurações' own "Sua evolução" chart
/// (spec-8-1, AD-12: a single data source, single fetch — exactly
/// `Resource<T>`'s own shape). A DI `registerLazySingleton` (Boundaries) —
/// long-lived like `AccountSettingsCubit`/`MeusRegistrosCubit`, so this
/// cubit's constructor subscription to [PendingEntryWriteTracker.
/// confirmedWrites] below stays live for the app's whole session, not just
/// while Configurações happens to be mounted (Boundaries: "recomputing on
/// each event (entry created on another tab while this one stays
/// mounted)").
///
/// Deliberately never caches a previous [load] result across calls
/// (Boundaries/Never: "cache the aggregate", AD-15 exclusion; FR-09:
/// "computed on demand, never stale") — every [load] re-emits
/// [ResourceLoading] first, same as `EntriesSearchCubit._search`.
class DashboardCubit extends Cubit<Resource<DashboardAggregate>> {
  DashboardCubit(this._repository, this._tracker)
    : super(const ResourceIdle()) {
    _confirmedSubscription = _tracker.confirmedWrites.listen((_) => load());
  }

  final DashboardRepository _repository;
  final PendingEntryWriteTracker _tracker;
  late final StreamSubscription<({String tempId, Entry entry})>
  _confirmedSubscription;

  /// A monotonic counter guarding against a stale in-flight [load] call's
  /// result landing after a newer one has already superseded it (e.g. a
  /// `confirmedWrites` event fires while `AccountSettingsScreen.initState`'s
  /// own [load] call is still in flight) — same generation-guard
  /// convention `EntriesSearchCubit._search`/`MeusRegistrosCubit.
  /// _loadFiltered` already use.
  int _generation = 0;

  /// Boundaries: "`queryParameters: {'period': 'all'}` — fixed; no period
  /// selector exists anywhere in the product" — [load]'s one and only
  /// call to [DashboardRepository.getAggregate] always passes this.
  Future<void> load() async {
    final generation = ++_generation;
    emit(ResourceLoading());
    final result = await _repository.getAggregate(period: 'all');
    // Mirrors `EntriesSearchCubit._search`'s own guard: `close()` can race
    // this awaited call, and a newer `load()` (constructor-triggered
    // `confirmedWrites` event, or a second screen open) can have
    // superseded this one while it was in flight.
    if (isClosed || generation != _generation) {
      return;
    }
    result.match(
      (failure) => emit(ResourceError(failure)),
      (aggregate) => emit(ResourceData(aggregate)),
    );
  }

  @override
  Future<void> close() async {
    await _confirmedSubscription.cancel();
    return super.close();
  }
}
