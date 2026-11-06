import 'package:flutter_test/flutter_test.dart' as flutter_test;
import 'package:flutter_test/flutter_test.dart' hide testWidgets;

/// Review fix (spec-6-5): factors out the near-identical local
/// `testWidgets` override that `app_router_test.dart`, `app_drawer_test.dart`,
/// `main_test.dart`, and `chat_screen_test.dart` each defined independently.
///
/// spec-6-5 made every bootstrapped `ChatCubit` start a real
/// `_insightInactivityTimer`; `testWidgets`' own `!timersPending`
/// invariant check runs *inside* the test's own callback execution,
/// before any `addTearDown`/`tearDown` callback ever fires, so a pending
/// `ChatCubit` must be closed from inside the callback itself — this
/// wrapper runs [cleanup] right after [callback] completes (success or
/// failure), still before that check.
///
/// Review fix: a bare `try`/`finally` would let a [cleanup] exception
/// (e.g. a double-`close()`) silently replace [callback]'s own exception
/// per Dart's standard finally semantics, masking a genuine test failure
/// behind an unrelated cleanup error — so a failing [callback] is
/// rethrown as-is and [cleanup]'s own exception, if any, is only ever the
/// one reported when [callback] itself succeeded.
void testWidgetsWithCleanup(
  String description,
  WidgetTesterCallback callback, {
  required Future<void> Function() cleanup,
}) {
  flutter_test.testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } catch (_) {
      await cleanup();
      rethrow;
    }
    await cleanup();
  });
}
