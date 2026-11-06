import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/isolated_side_effect.dart';

/// spec-6-4 (RF10) — the real (non-stub) `isolatedSideEffect` body's own
/// unit coverage: a never-throws wrapper that either passes a successful
/// [action] result through as `Right`, or maps any thrown exception (sync
/// or async) to `Left(Failure.malformedResponse(...))` instead of letting
/// it escape to the caller (AD-13).
void main() {
  group('isolatedSideEffect', () {
    test(
      'a successful action resolves to Right, passed through verbatim',
      () async {
        final result = await isolatedSideEffect(() async => 'ok');

        expect(result.isRight(), isTrue);
        result.match((_) => fail('expected Right'), (value) {
          expect(value, 'ok');
        });
      },
    );

    test('a synchronous throw inside action is caught and mapped to '
        'Failure.malformedResponse, never escapes the caller', () async {
      final result = await isolatedSideEffect<String>(() {
        throw Exception('boom');
      });

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('an asynchronous throw (a rejected Future) inside action is caught '
        'and mapped to Failure.malformedResponse too', () async {
      final result = await isolatedSideEffect<String>(
        () => Future<String>.error(Exception('async boom')),
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test("the mapped failure carries the thrown error's own toString() as "
        'its message, never a generic placeholder', () async {
      final result = await isolatedSideEffect<String>(() {
        throw Exception('specific boom');
      });

      result.match(
        (failure) => expect(failure.message, contains('specific boom')),
        (_) => fail('expected Left'),
      );
    });

    test('a mapped failure is never retryable — same as every other '
        'malformedResponse (AD-3/AD-4)', () async {
      final result = await isolatedSideEffect<String>(() {
        throw Exception('boom');
      });

      result.match(
        (failure) => expect(failure.retryable, isFalse),
        (_) => fail('expected Left'),
      );
    });
  });
}
