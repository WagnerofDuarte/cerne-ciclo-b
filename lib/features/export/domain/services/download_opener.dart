/// spec-7-2 — the export feature's own port for handing a finished
/// download's signed URL off to the OS, rather than ever buffering/writing
/// the file in-app (Boundaries: "never buffer/write the file in-app").
/// Feature-local (`export/domain/services/`), mirroring
/// `chat/domain/services/connectivity_watcher.dart`'s own domain/data
/// split: an abstract class here, a concrete `url_launcher`-backed
/// implementation in `export/data/services/`
/// (`UrlLauncherDownloadOpener`), injected directly into
/// `ExportJobCubit`'s constructor — never routed through `ExportRepository`
/// (it owns no network call of its own).
abstract class DownloadOpener {
  /// Opens [url] externally (the OS's own browser tab/share sheet/PDF
  /// viewer — whichever handles it) and returns whether the OS reported it
  /// was able to do so. `false` is a transport-agnostic "couldn't open it"
  /// signal — the cubit surfaces it the same way it surfaces any other
  /// download failure (`Failure.malformedResponse`, Design Notes).
  Future<bool> open(String url);
}
