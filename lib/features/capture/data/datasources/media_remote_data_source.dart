import 'dart:convert';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/repositories/media_repository.dart';

/// Capture's one OCR call (`media-ocr`) — posts via the shared
/// `ApiClient`, mirroring `entries_remote_data_source.dart`'s pattern.
/// Base64-encodes the image bytes here, and only here (Boundaries) — no
/// other layer ever handles the raw bytes in that encoded form.
class MediaRemoteDataSource {
  MediaRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, OcrResult>> recognizeText({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final result = await _apiClient.post(
      'media-ocr',
      data: {'image': base64Encode(imageBytes), 'mimeType': mimeType},
    );
    return result.flatMap((json) {
      try {
        final data = json['data'] as Map<String, dynamic>;
        return right(
          OcrResult(
            text: data['text'] as String,
            confidence: data['confidence'] as String,
          ),
        );
      } catch (error) {
        // A 200 response that doesn't match the expected shape is a
        // client-side parse failure, never a backend-sent code — maps to
        // the local-only `malformedResponse` (RNF09: no exception escapes
        // unmapped).
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }
}
