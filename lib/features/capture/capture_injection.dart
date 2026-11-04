import '../../core/di/injection_container.dart';
import '../entries/domain/repositories/entries_repository.dart';
import 'presentation/cubit/text_entry_cubit.dart';

/// Registers the `capture` feature into the project's single `get_it`
/// instance (`sl`). Unlike every other feature's cubit in this codebase
/// (`AccountSettingsCubit`/`AuthCubit`, lazy singletons), [TextEntryCubit]
/// is a **factory** — the Insertion Modal needs a fresh instance per "+"
/// tap (Boundaries: "Modal open resets"), not one long-lived instance
/// reused across opens. Called from `setupCoreDependencies()` right after
/// `registerEntriesFeature()` (Code Map).
void registerCaptureFeature() {
  sl.registerFactory<TextEntryCubit>(
    () => TextEntryCubit(sl<EntriesRepository>()),
  );
}
