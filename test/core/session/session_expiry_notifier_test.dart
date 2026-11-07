import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/session/session_expiry_notifier.dart';

void main() {
  late SessionExpiryNotifierImpl notifier;

  setUp(() {
    notifier = SessionExpiryNotifierImpl();
  });

  group('SessionExpiryNotifierImpl', () {
    test('notifyExpired delivers one event to a listener', () async {
      final events = <void>[];
      final subscription = notifier.expiredEvents.listen(events.add);

      notifier.notifyExpired();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      await subscription.cancel();
    });

    test('expiredEvents is a broadcast stream — more than one listener can '
        'subscribe at once', () async {
      final firstEvents = <void>[];
      final secondEvents = <void>[];
      final firstSubscription = notifier.expiredEvents.listen(firstEvents.add);
      final secondSubscription = notifier.expiredEvents.listen(
        secondEvents.add,
      );

      notifier.notifyExpired();
      await Future<void>.delayed(Duration.zero);

      expect(firstEvents, hasLength(1));
      expect(secondEvents, hasLength(1));
      await firstSubscription.cancel();
      await secondSubscription.cancel();
    });

    test('notifyExpired with no listener never throws', () {
      expect(notifier.notifyExpired, returnsNormally);
    });

    test(
      'notifyExpired after dispose() is a silent no-op, never throws',
      () async {
        await notifier.dispose();

        expect(notifier.notifyExpired, returnsNormally);
      },
    );

    test(
      'dispose() closes the stream — a late listen gets no more events',
      () async {
        await notifier.dispose();

        final events = <void>[];
        final subscription = notifier.expiredEvents.listen(
          events.add,
          onDone: () {},
        );
        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
        await subscription.cancel();
      },
    );
  });
}
