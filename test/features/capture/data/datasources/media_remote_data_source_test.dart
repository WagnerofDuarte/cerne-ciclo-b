import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/features/capture/data/datasources/media_remote_data_source.dart';
import 'package:cerne/features/capture/domain/repositories/media_repository.dart';

import '../../../../support/write_failure_matrix_helper.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _ocrBody({
  String text = 'Texto reconhecido.',
  String confidence = 'high',
}) => {
  'data': {'text': text, 'confidence': confidence},
};

void main() {
  late MockApiClient mockApiClient;
  late MediaRemoteDataSource dataSource;

  final imageBytes = Uint8List.fromList([1, 2, 3]);

  setUp(() {
    mockApiClient = MockApiClient();
    dataSource = MediaRemoteDataSource(mockApiClient);
  });

  // RNF09 — this story's slice of the write-failure matrix is
  // `media-ocr`, exercised through `recognizeText()`.
  runWriteFailureMatrix<OcrResult>(
    endpointName: 'media-ocr',
    stubNetworkTimeout: () =>
        when(() => mockApiClient.post(any(), data: any(named: 'data')))
            .thenAnswer(
              (_) async =>
                  left(const Failure.networkTimeout(message: 'Timed out')),
            ),
    stubMalformedResponse: () =>
        when(() => mockApiClient.post(any(), data: any(named: 'data')))
            .thenAnswer((_) async => right({'unexpected': 'shape'})),
    stubNoConnection: () =>
        when(() => mockApiClient.post(any(), data: any(named: 'data')))
            .thenAnswer(
              (_) async =>
                  left(const Failure.networkOffline(message: 'Offline')),
            ),
    invoke: () => dataSource.recognizeText(
      imageBytes: imageBytes,
      mimeType: 'image/jpeg',
    ),
  );

  group('MediaRemoteDataSource.recognizeText', () {
    test('calls POST media-ocr with {image: base64(bytes), mimeType} — the '
        'image is base64-encoded here, and only here (Boundaries)', () async {
      when(() => mockApiClient.post('media-ocr', data: any(named: 'data')))
          .thenAnswer((_) async => right(_ocrBody()));

      await dataSource.recognizeText(
        imageBytes: imageBytes,
        mimeType: 'image/jpeg',
      );

      final captured = verify(
        () => mockApiClient.post('media-ocr', data: captureAny(named: 'data')),
      ).captured;
      expect(captured.single, {
        'image': base64Encode(imageBytes),
        'mimeType': 'image/jpeg',
      });
    });

    test('decodes the OcrResult (text/confidence) from the response data '
        'object', () async {
      when(
        () => mockApiClient.post('media-ocr', data: any(named: 'data')),
      ).thenAnswer(
        (_) async =>
            right(_ocrBody(text: 'Hoje foi um bom dia.', confidence: 'low')),
      );

      final result = await dataSource.recognizeText(
        imageBytes: imageBytes,
        mimeType: 'image/png',
      );

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (ocr) {
        expect(ocr.text, 'Hoje foi um bom dia.');
        expect(ocr.confidence, 'low');
      });
    });

    test('a backend error code (e.g. OCR_NO_TEXT) maps straight through as '
        'the matching Failure', () async {
      when(
        () => mockApiClient.post('media-ocr', data: any(named: 'data')),
      ).thenAnswer(
        (_) async =>
            left(const Failure.ocrNoText(message: 'Nenhum texto encontrado.')),
      );

      final result = await dataSource.recognizeText(
        imageBytes: imageBytes,
        mimeType: 'image/jpeg',
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<OcrNoText>()),
        (_) => fail('expected Left'),
      );
    });

    test(
      'PAYLOAD_TOO_LARGE maps straight through as Failure.payloadTooLarge',
      () async {
        when(() => mockApiClient.post('media-ocr', data: any(named: 'data')))
            .thenAnswer(
              (_) async => left(
                const Failure.payloadTooLarge(message: 'Imagem muito grande.'),
              ),
            );

        final result = await dataSource.recognizeText(
          imageBytes: imageBytes,
          mimeType: 'image/jpeg',
        );

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<PayloadTooLarge>()),
          (_) => fail('expected Left'),
        );
      },
    );
  });
}
