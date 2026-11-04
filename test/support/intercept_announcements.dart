import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mocks `SystemChannels.accessibility` directly — the channel
/// `SemanticsService.sendAnnouncement` sends on — so a test can assert on
/// the real announcement content instead of only reading visible `Text`
/// widgets (which would still pass even if a `_announce()` call were
/// deleted or its guard inverted). Extracted from
/// `vault_lock_screen_test.dart`'s own `AC3` group, which first proved
/// this pattern; reused by `insertion_modal_test.dart`.
List<String> interceptAnnouncements(WidgetTester tester) {
  final messages = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (dynamic call) async {
      final event = call as Map<dynamic, dynamic>;
      if (event['type'] == 'announce') {
        final data = event['data'] as Map<dynamic, dynamic>;
        messages.add(data['message'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return messages;
}
