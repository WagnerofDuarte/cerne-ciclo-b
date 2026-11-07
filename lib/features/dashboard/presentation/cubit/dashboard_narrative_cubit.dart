import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/resource.dart';
import '../../../entries/domain/entities/entry.dart';
import '../../../entries/domain/services/pending_entry_write_tracker.dart';
import '../../domain/repositories/dashboard_repository.dart';

/// Drives `DashboardChartSection`'s own AI narrative paragraph (spec-8-2) —
/// a second, independent fetch from [DashboardCubit]'s own aggregate fetch
/// (Boundaries/Never: "couple the two `Resource`s into one state object"),
/// mirroring [DashboardCubit]'s exact shape: a DI `registerLazySingleton`,
/// constructor-subscribed to [PendingEntryWriteTracker.confirmedWrites] so
/// it recomputes on every entry write same as the aggregate, and [load] is
/// generation-guarded the same way.
///
/// Deliberately never caches a previous [load] result across calls, same
/// rationale [DashboardCubit] gives — every [load] re-emits
/// [ResourceLoading] first.
class DashboardNarrativeCubit extends Cubit<Resource<String>> {
  DashboardNarrativeCubit(this._repository, this._tracker)
    : super(const ResourceIdle()) {
    _confirmedSubscription = _tracker.confirmedWrites.listen((_) => load());
  }

  final DashboardRepository _repository;
  final PendingEntryWriteTracker _tracker;
  late final StreamSubscription<({String tempId, Entry entry})>
  _confirmedSubscription;

  /// Same generation-guard convention [DashboardCubit]'s own `_generation`
  /// uses — guards against a stale in-flight [load] call's result landing
  /// after a newer one has already superseded it.
  int _generation = 0;

  /// Boundaries: "`queryParameters: {'period': 'all'}` — same fixed value
  /// as `dashboard-aggregate-get`" — [load]'s one and only call to
  /// [DashboardRepository.getNarrative] always passes this.
  Future<void> load() async {
    final generation = ++_generation;
    emit(ResourceLoading());
    final result = await _repository.getNarrative(period: 'all');
    // Mirrors `DashboardCubit.load()`'s own guard: `close()` can race this
    // awaited call, and a newer `load()` (constructor-triggered
    // `confirmedWrites` event, a second screen open, or a retry tap) can
    // have superseded this one while it was in flight.
    if (isClosed || generation != _generation) {
      return;
    }
    result.match(
      (failure) => emit(ResourceError(failure)),
      (text) => emit(ResourceData(text)),
    );
  }

  @override
  Future<void> close() async {
    await _confirmedSubscription.cancel();
    return super.close();
  }
}
