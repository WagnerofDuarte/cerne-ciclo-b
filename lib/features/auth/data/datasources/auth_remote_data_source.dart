import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/api_client.dart';
import '../models/auth_response_dto.dart';

/// The two write calls (`auth-signup`, `auth-login`) — exactly `{email,
/// password}`, no extra field (epics.md Story 1.3 AC). Posts via the shared
/// `ApiClient` (already anon-keyed for these two functions through
/// `HeaderInterceptor.anonKeyOnlyFunctions`, AD-5).
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, AuthResponseDto>> signUp({
    required String email,
    required String password,
  }) => _post('auth-signup', email: email, password: password);

  Future<Either<Failure, AuthResponseDto>> logIn({
    required String email,
    required String password,
  }) => _post('auth-login', email: email, password: password);

  /// `auth-refresh` (`openapi.yaml:179-240`) — own body shape (`{refreshToken}`,
  /// no `email`/`password`) and own response shape (`{data: {session}}`,
  /// no `user`), so it can't reuse [_post]/[AuthResponseDto]. Decodes the
  /// nested `session` object straight into [AuthSessionDto] (Code Map: reuse
  /// as-is, no DTO change).
  Future<Either<Failure, AuthSessionDto>> refresh(String refreshToken) async {
    final result = await _apiClient.post(
      'auth-refresh',
      data: {'refreshToken': refreshToken},
    );
    return result.flatMap((json) {
      try {
        final data = json['data'] as Map<String, dynamic>;
        final session = data['session'] as Map<String, dynamic>;
        return right(AuthSessionDto.fromJson(session));
      } catch (error) {
        // A 200 response that doesn't match the expected shape is a
        // client-side parse failure, never a backend-sent code — maps to
        // the local-only `malformedResponse` (RNF09: no exception escapes).
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }

  Future<Either<Failure, AuthResponseDto>> _post(
    String function, {
    required String email,
    required String password,
  }) async {
    final result = await _apiClient.post(
      function,
      data: {'email': email, 'password': password},
    );
    return result.flatMap((json) {
      try {
        return right(AuthResponseDto.fromJson(json));
      } catch (error) {
        // A 200 response that doesn't match the expected shape is a
        // client-side parse failure, never a backend-sent code — maps to
        // the local-only `malformedResponse` (RNF09: no exception escapes).
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }
}
