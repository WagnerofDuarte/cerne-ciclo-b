// The constructor keeps public named params (`remoteDataSource`,
// `accessTokenProvider`) distinct from the private fields they initialize,
// matching `api_client.dart`'s documented convention — an initializing
// formal isn't a clean fit here either.
// ignore_for_file: prefer_initializing_formals
import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/access_token_provider.dart';
import '../../domain/entities/authenticated_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/auth_response_dto.dart';

/// Maps the DTO to the domain entity and saves the access token *before*
/// returning `right(...)` — the boundary this story fixes (refresh-token
/// persistence is Story 1.4's job).
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required AccessTokenProvider accessTokenProvider,
  })  : _remoteDataSource = remoteDataSource,
        _accessTokenProvider = accessTokenProvider;

  final AuthRemoteDataSource _remoteDataSource;
  final AccessTokenProvider _accessTokenProvider;

  @override
  Future<Either<Failure, AuthenticatedUser>> signUp({
    required String email,
    required String password,
  }) =>
      _authenticate(
        () => _remoteDataSource.signUp(email: email, password: password),
      );

  @override
  Future<Either<Failure, AuthenticatedUser>> logIn({
    required String email,
    required String password,
  }) =>
      _authenticate(
        () => _remoteDataSource.logIn(email: email, password: password),
      );

  Future<Either<Failure, AuthenticatedUser>> _authenticate(
    Future<Either<Failure, AuthResponseDto>> Function() call,
  ) async {
    final result = await call();
    return result.match(
      (failure) async => left(failure),
      (dto) async {
        // A thrown platform exception (secure-storage channel failure, disk
        // issue, ...) must never escape unmapped (RNF09/AD-2) — if the token
        // can't be persisted, the call as a whole must surface as a Failure
        // rather than leave the caller awaiting forever.
        try {
          await _accessTokenProvider.saveAccessToken(
            dto.data.session.accessToken,
          );
        } catch (error) {
          return left(Failure.malformedResponse(message: error.toString()));
        }
        return right(
          AuthenticatedUser(id: dto.data.user.id, email: dto.data.user.email),
        );
      },
    );
  }
}
