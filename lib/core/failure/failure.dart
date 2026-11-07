import 'package:freezed_annotation/freezed_annotation.dart';

part 'failure.freezed.dart';

/// AD-3 — the one closed `Failure` hierarchy, exactly 14 subtypes: the 13
/// codes from `docs/input/backend/error-taxonomy.md` plus the local-only
/// `malformedResponse` (client-side parse failure, never sent by the
/// backend). Never redefined or subset per feature; every repository method
/// returns `Either<Failure, T>` built from this type (RNF09).
///
/// `retryable` is derived here, once, from the 6 server `retryable:true`
/// codes (AD-4) — no other file re-decides which codes retry.
@freezed
sealed class Failure with _$Failure {
  const factory Failure.authExpired({required String message}) = AuthExpired;
  const factory Failure.authInvalid({required String message}) = AuthInvalid;
  const factory Failure.networkTimeout({required String message}) =
      NetworkTimeout;
  const factory Failure.networkOffline({required String message}) =
      NetworkOffline;
  const factory Failure.validation({required String message}) = Validation;
  const factory Failure.piiCheckFailed({required String message}) =
      PiiCheckFailed;
  const factory Failure.embeddingFailed({required String message}) =
      EmbeddingFailed;
  const factory Failure.aiGenerationTimeout({required String message}) =
      AiGenerationTimeout;
  const factory Failure.notFound({required String message}) = NotFound;
  const factory Failure.rateLimited({required String message}) = RateLimited;
  const factory Failure.exportEmptyPeriod({required String message}) =
      ExportEmptyPeriod;
  const factory Failure.payloadTooLarge({required String message}) =
      PayloadTooLarge;
  const factory Failure.ocrNoText({required String message}) = OcrNoText;

  /// Local-only — the client's own parse-failure detection. `retryable` is
  /// hardcoded `false` for this subtype (AD-3).
  const factory Failure.malformedResponse({required String message}) =
      MalformedResponse;

  const Failure._();

  /// The 6 server `retryable:true` codes (AD-4). Every other code —
  /// including the local `malformedResponse` — is `false`.
  bool get retryable => switch (this) {
    NetworkTimeout() => true,
    NetworkOffline() => true,
    PiiCheckFailed() => true,
    EmbeddingFailed() => true,
    AiGenerationTimeout() => true,
    RateLimited() => true,
    AuthExpired() ||
    AuthInvalid() ||
    Validation() ||
    NotFound() ||
    ExportEmptyPeriod() ||
    PayloadTooLarge() ||
    OcrNoText() ||
    MalformedResponse() => false,
  };

  /// Maps a backend error `code` (`error-taxonomy.md`) to its `Failure`
  /// subtype. An unrecognized code (should never happen — the taxonomy is
  /// closed) falls back to [Failure.malformedResponse] rather than throwing,
  /// so no repository ever lets an unmapped error escape (RNF09).
  factory Failure.fromCode(String code, String message) => switch (code) {
    'AUTH_EXPIRED' => Failure.authExpired(message: message),
    'AUTH_INVALID' => Failure.authInvalid(message: message),
    'NETWORK_TIMEOUT' => Failure.networkTimeout(message: message),
    'NETWORK_OFFLINE' => Failure.networkOffline(message: message),
    'VALIDATION_ERROR' => Failure.validation(message: message),
    'PII_CHECK_FAILED' => Failure.piiCheckFailed(message: message),
    'EMBEDDING_FAILED' => Failure.embeddingFailed(message: message),
    'AI_GENERATION_TIMEOUT' => Failure.aiGenerationTimeout(message: message),
    'NOT_FOUND' => Failure.notFound(message: message),
    'RATE_LIMITED' => Failure.rateLimited(message: message),
    'EXPORT_EMPTY_PERIOD' => Failure.exportEmptyPeriod(message: message),
    'PAYLOAD_TOO_LARGE' => Failure.payloadTooLarge(message: message),
    'OCR_NO_TEXT' => Failure.ocrNoText(message: message),
    _ => Failure.malformedResponse(message: message),
  };
}
