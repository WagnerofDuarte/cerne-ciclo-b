import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';

/// `media-ocr`'s own result shape. [confidence] is a string enum
/// (`high`/`low`, Design Notes) — carried through but not surfaced in any
/// UI this story calls for; available for a future story if needed.
class OcrResult {
  const OcrResult({required this.text, required this.confidence});

  final String text;
  final String confidence;
}

/// Capture's own OCR port — belongs to `capture/`, never `entries/`
/// (epic Technical Decisions: "`features/capture/` ... holds no Entry
/// data itself"). The `media-ocr`-backed `MediaRepositoryImpl` is the
/// only implementation (Code Map).
abstract class MediaRepository {
  /// Posts [imageBytes] (never persisted anywhere beyond this in-flight
  /// call — Never clause) to `media-ocr` and returns its recognized
  /// text/confidence. Every [Failure] — including [Failure.ocrNoText]/
  /// [Failure.payloadTooLarge] — is returned as `Left`, unmapped and
  /// un-retried; the caller decides what to do with it (RNF09).
  Future<Either<Failure, OcrResult>> recognizeText({
    required Uint8List imageBytes,
    required String mimeType,
  });
}
