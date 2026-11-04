import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Stands in for the real `path_provider` plugin wherever
/// `Hive.initFlutter()` (first exercised by Story 3.1's
/// `registerEntriesFeature()`, transitively via `hive_ce_flutter`) runs
/// under `flutter test` — no device/simulator exists yet (AGENTS.md) to
/// answer `getApplicationDocumentsPath()` for real. Returns a fresh temp
/// directory per call instead, same "fake the native platform channel"
/// rationale `bootstrap_integration_test.dart`/`main_test.dart` already
/// apply to `flutter_secure_storage`.
///
/// Review finding: a temp directory created here is real disk state, not
/// an in-memory fake — without [cleanUp], every test run exercising DI
/// bootstrap leaks one orphaned folder under the OS temp dir per `setUp()`
/// call. Callers are expected to hold on to the instance they assign to
/// `PathProviderPlatform.instance` and call [cleanUp] from their own
/// `tearDown`.
class FakePathProviderPlatform extends PathProviderPlatform {
  final List<Directory> _createdDirectories = [];

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final dir = Directory.systemTemp.createTempSync('cerne_test_hive_');
    _createdDirectories.add(dir);
    return dir.path;
  }

  /// Deletes every temp directory this instance created. Safe to call
  /// even if nothing was ever created, and even if a directory was
  /// already removed by something else.
  Future<void> cleanUp() async {
    for (final dir in _createdDirectories) {
      try {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {
        // Best-effort cleanup — a leftover temp folder is a minor local
        // annoyance, never a reason to fail the test that asked for it.
      }
    }
    _createdDirectories.clear();
  }
}
