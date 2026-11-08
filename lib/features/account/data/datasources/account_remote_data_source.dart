import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/api_client.dart';
import '../models/account_settings_dto.dart';

/// The account feature's one write call (`account-settings-update`) — the
/// only `/account/settings` endpoint (Boundaries: "no GET endpoint exists").
/// Posts via the shared `ApiClient`, mirroring
/// `auth_remote_data_source.dart`'s pattern.
class AccountRemoteDataSource {
  AccountRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  /// Called with `{}` to read the current settings without changing
  /// anything (Boundaries: "`PATCH /account/settings` ... called empty to
  /// read").
  Future<Either<Failure, AccountSettingsDto>> fetchSettings() =>
      _patch(const {});

  /// Called with exactly `{"biometricEnabled": enabled}` to write — never
  /// `displayName`/`persona` (Epic 8's scope, Boundaries).
  Future<Either<Failure, AccountSettingsDto>> updateBiometricEnabled(
    bool enabled,
  ) => _patch({'biometricEnabled': enabled});

  /// spec-8-3 — called with exactly `{"displayName": name}` to write the
  /// profile name, mirroring [updateBiometricEnabled]'s own shape (Code
  /// Map: "mirrors updateBiometricEnabled").
  Future<Either<Failure, AccountSettingsDto>> updateDisplayName(String name) =>
      _patch({'displayName': name});

  /// Story 8.5 — `account-delete` (`DELETE /account`), bearerAuth, exactly
  /// `{"confirmation": "DELETE"}` (Boundaries/Code Map). No DTO shape worth
  /// decoding — same "only whether the call itself succeeded matters"
  /// rationale as `AuthRemoteDataSource.logout()`'s own `{data: {ok:
  /// true}}` response, mapped straight to `Right(unit)`, discarding the
  /// body.
  Future<Either<Failure, Unit>> deleteAccount() async {
    final result = await _apiClient.delete(
      'account-delete',
      data: const {'confirmation': 'DELETE'},
    );
    return result.map((_) => unit);
  }

  Future<Either<Failure, AccountSettingsDto>> _patch(
    Map<String, dynamic> data,
  ) async {
    final result = await _apiClient.patch(
      'account-settings-update',
      data: data,
    );
    return result.flatMap((json) {
      try {
        final responseData = json['data'] as Map<String, dynamic>;
        return right(AccountSettingsDto.fromJson(responseData));
      } catch (error) {
        // A 200 response that doesn't match the expected shape is a
        // client-side parse failure, never a backend-sent code — maps to
        // the local-only `malformedResponse` (RNF09: no exception escapes).
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }
}
