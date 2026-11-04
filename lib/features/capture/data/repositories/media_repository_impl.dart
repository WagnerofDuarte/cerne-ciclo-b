// The constructor keeps a public named param (`remoteDataSource`)
// distinct from the private field it initializes, matching
// `entries_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/repositories/media_repository.dart';
import '../datasources/media_remote_data_source.dart';

/// Forwards `MediaRemoteDataSource`'s result as-is, with no Hive
/// persistence step (Boundaries: "no Hive persistence step — the image
/// is never persisted, forward the datasource's `Either` as-is") —
/// unlike `EntriesRepositoryImpl`'s own post-success write-through.
class MediaRepositoryImpl implements MediaRepository {
  MediaRepositoryImpl({required MediaRemoteDataSource remoteDataSource})
    : _remoteDataSource = remoteDataSource;

  final MediaRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure, OcrResult>> recognizeText({
    required Uint8List imageBytes,
    required String mimeType,
  }) => _remoteDataSource.recognizeText(
    imageBytes: imageBytes,
    mimeType: mimeType,
  );
}
