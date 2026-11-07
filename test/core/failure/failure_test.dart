import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/failure/failure.dart';

void main() {
  group('Failure (AD-3) — all 14 subtypes are reachable', () {
    test('authExpired', () {
      const failure = Failure.authExpired(message: 'expired');
      expect(failure, isA<AuthExpired>());
      expect(failure.retryable, isFalse);
    });

    test('authInvalid', () {
      const failure = Failure.authInvalid(message: 'invalid');
      expect(failure, isA<AuthInvalid>());
      expect(failure.retryable, isFalse);
    });

    test('networkTimeout is retryable', () {
      const failure = Failure.networkTimeout(message: 'timeout');
      expect(failure, isA<NetworkTimeout>());
      expect(failure.retryable, isTrue);
    });

    test('networkOffline is retryable', () {
      const failure = Failure.networkOffline(message: 'offline');
      expect(failure, isA<NetworkOffline>());
      expect(failure.retryable, isTrue);
    });

    test('validation', () {
      const failure = Failure.validation(message: 'invalid payload');
      expect(failure, isA<Validation>());
      expect(failure.retryable, isFalse);
    });

    test('piiCheckFailed is retryable', () {
      const failure = Failure.piiCheckFailed(message: 'pii');
      expect(failure, isA<PiiCheckFailed>());
      expect(failure.retryable, isTrue);
    });

    test('embeddingFailed is retryable', () {
      const failure = Failure.embeddingFailed(message: 'embedding');
      expect(failure, isA<EmbeddingFailed>());
      expect(failure.retryable, isTrue);
    });

    test('aiGenerationTimeout is retryable', () {
      const failure = Failure.aiGenerationTimeout(message: 'ai timeout');
      expect(failure, isA<AiGenerationTimeout>());
      expect(failure.retryable, isTrue);
    });

    test('notFound', () {
      const failure = Failure.notFound(message: 'not found');
      expect(failure, isA<NotFound>());
      expect(failure.retryable, isFalse);
    });

    test('rateLimited is retryable', () {
      const failure = Failure.rateLimited(message: 'rate limited');
      expect(failure, isA<RateLimited>());
      expect(failure.retryable, isTrue);
    });

    test('exportEmptyPeriod', () {
      const failure = Failure.exportEmptyPeriod(message: 'empty period');
      expect(failure, isA<ExportEmptyPeriod>());
      expect(failure.retryable, isFalse);
    });

    test('payloadTooLarge', () {
      const failure = Failure.payloadTooLarge(message: 'too large');
      expect(failure, isA<PayloadTooLarge>());
      expect(failure.retryable, isFalse);
    });

    test('ocrNoText', () {
      const failure = Failure.ocrNoText(message: 'no text');
      expect(failure, isA<OcrNoText>());
      expect(failure.retryable, isFalse);
    });

    test('malformedResponse — local-only, retryable hardcoded false', () {
      const failure = Failure.malformedResponse(message: 'bad json');
      expect(failure, isA<MalformedResponse>());
      expect(failure.retryable, isFalse);
    });
  });

  group('Failure.fromCode — maps every backend error-taxonomy code', () {
    const cases = {
      'AUTH_EXPIRED': AuthExpired,
      'AUTH_INVALID': AuthInvalid,
      'NETWORK_TIMEOUT': NetworkTimeout,
      'NETWORK_OFFLINE': NetworkOffline,
      'VALIDATION_ERROR': Validation,
      'PII_CHECK_FAILED': PiiCheckFailed,
      'EMBEDDING_FAILED': EmbeddingFailed,
      'AI_GENERATION_TIMEOUT': AiGenerationTimeout,
      'NOT_FOUND': NotFound,
      'RATE_LIMITED': RateLimited,
      'EXPORT_EMPTY_PERIOD': ExportEmptyPeriod,
      'PAYLOAD_TOO_LARGE': PayloadTooLarge,
      'OCR_NO_TEXT': OcrNoText,
    };

    for (final entry in cases.entries) {
      test('${entry.key} -> ${entry.value}', () {
        final failure = Failure.fromCode(entry.key, 'msg');
        expect(failure.runtimeType, entry.value);
      });
    }

    test('unrecognized code falls back to malformedResponse, never throws', () {
      final failure = Failure.fromCode('SOME_UNKNOWN_CODE', 'msg');
      expect(failure, isA<MalformedResponse>());
    });
  });

  group('retry allowlist matches AD-4 exactly', () {
    test('exactly the 6 retryable codes are retryable, no more no less', () {
      const allCodes = [
        'AUTH_EXPIRED',
        'AUTH_INVALID',
        'NETWORK_TIMEOUT',
        'NETWORK_OFFLINE',
        'VALIDATION_ERROR',
        'PII_CHECK_FAILED',
        'EMBEDDING_FAILED',
        'AI_GENERATION_TIMEOUT',
        'NOT_FOUND',
        'RATE_LIMITED',
        'EXPORT_EMPTY_PERIOD',
        'PAYLOAD_TOO_LARGE',
        'OCR_NO_TEXT',
      ];
      const expectedRetryable = {
        'NETWORK_TIMEOUT',
        'NETWORK_OFFLINE',
        'PII_CHECK_FAILED',
        'EMBEDDING_FAILED',
        'AI_GENERATION_TIMEOUT',
        'RATE_LIMITED',
      };

      for (final code in allCodes) {
        final failure = Failure.fromCode(code, 'msg');
        expect(
          failure.retryable,
          expectedRetryable.contains(code),
          reason: '$code retryable mismatch',
        );
      }
    });
  });
}
