import 'package:json_annotation/json_annotation.dart';

part 'auth_response_dto.g.dart';

/// The `auth-signup`/`auth-login` response envelope
/// (`openapi.yaml:19-98`): `{data: {session: {...}, user: {id, email}}}`.
/// Field names already match the wire format's camelCase, so no `@JsonKey`
/// renames are needed.
@JsonSerializable()
class AuthResponseDto {
  const AuthResponseDto({required this.data});

  final AuthResponseDataDto data;

  factory AuthResponseDto.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AuthResponseDtoToJson(this);
}

@JsonSerializable()
class AuthResponseDataDto {
  const AuthResponseDataDto({required this.session, required this.user});

  final AuthSessionDto session;
  final AuthUserDto user;

  factory AuthResponseDataDto.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseDataDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AuthResponseDataDtoToJson(this);
}

@JsonSerializable()
class AuthSessionDto {
  const AuthSessionDto({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.expiresAt,
    required this.tokenType,
  });

  final String accessToken;

  /// Persisted via `AccessTokenProvider.saveSession` (Story 1.4). Decoded
  /// here regardless, so a missing/malformed field surfaces as
  /// `MalformedResponse` rather than being silently dropped.
  final String refreshToken;
  final int expiresIn;
  final int expiresAt;
  final String tokenType;

  factory AuthSessionDto.fromJson(Map<String, dynamic> json) =>
      _$AuthSessionDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AuthSessionDtoToJson(this);
}

@JsonSerializable()
class AuthUserDto {
  const AuthUserDto({required this.id, required this.email});

  final String id;
  final String email;

  factory AuthUserDto.fromJson(Map<String, dynamic> json) =>
      _$AuthUserDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AuthUserDtoToJson(this);
}
