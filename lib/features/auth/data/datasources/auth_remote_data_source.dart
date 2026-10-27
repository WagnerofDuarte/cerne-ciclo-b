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
  }) =>
      _post('auth-signup', email: email, password: password);

  Future<Either<Failure, AuthResponseDto>> logIn({
    required String email,
    required String password,
  }) =>
      _post('auth-login', email: email, password: password);

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
