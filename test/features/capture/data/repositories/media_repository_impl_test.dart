import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/capture/data/datasources/media_remote_data_source.dart';
import 'package:cerne/features/capture/data/repositories/media_repository_impl.dart';
import 'package:cerne/features/capture/domain/repositories/media_repository.dart';

class MockMediaRemoteDataSource extends Mock implements MediaRemoteDataSource {}

/// Covers spec-3-3's `MediaRepository.recognizeText` — unlike
/// `EntriesRepositoryImpl`, there is no Hive persistence step to verify;
/// this just proves the datasource's `Either` is forwarded as-is
/// (Boundaries: "no Hive persistence step ... forward the datasource's
/// `Either` as-is").
void main() {
  late MockMediaRemoteDataSource mockRemoteDataSource;
  late MediaRepositoryImpl repository;

  final imageBytes = Uint8List.fromList([1, 2, 3]);

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockRemoteDataSource = MockMediaRemoteDataSource();
    repository = MediaRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  test(
    'success -> forwards the datasource\'s Right(OcrResult) unchanged',
    () async {
      const ocrResult = OcrResult(
        text: 'Hoje foi um bom dia.',
        confidence: 'high',
      );
      when(
        () => mockRemoteDataSource.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async => right(ocrResult));

      final result = await repository.recognizeText(
        imageBytes: imageBytes,
        mimeType: 'image/jpeg',
      );

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (ocr) {
        expect(ocr.text, 'Hoje foi um bom dia.');
        expect(ocr.confidence, 'high');
      });
      verify(
        () => mockRemoteDataSource.recognizeText(
          imageBytes: imageBytes,
          mimeType: 'image/jpeg',
        ),
      ).called(1);
    },
  );

  test(
    'a remote Failure (e.g. OcrNoText) passes through as Left, unchanged',
    () async {
      when(
        () => mockRemoteDataSource.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async =>
            left(const Failure.ocrNoText(message: 'Nenhum texto encontrado.')),
      );

      final result = await repository.recognizeText(
        imageBytes: imageBytes,
        mimeType: 'image/jpeg',
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<OcrNoText>()),
        (_) => fail('expected Left'),
      );
    },
  );
}
