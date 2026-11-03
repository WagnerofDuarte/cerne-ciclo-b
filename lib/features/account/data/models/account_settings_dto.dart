import 'package:json_annotation/json_annotation.dart';

part 'account_settings_dto.g.dart';

/// `PATCH /account/settings`'s response `data` object
/// (`openapi.yaml:1764-1803`) carries `id`/`email`/`displayName`/`persona`/
/// `biometricEnabled`/`serverRevision`/`createdAt`/`updatedAt` — this DTO
/// decodes only [biometricEnabled] (Code Map), the single field Story 2.4
/// needs; every other field is simply ignored by `json_serializable`'s
/// generated `fromJson` rather than modeled here (`displayName`/`persona`
/// are Epic 8's scope — Boundaries: "never touched").
@JsonSerializable()
class AccountSettingsDto {
  const AccountSettingsDto({required this.biometricEnabled});

  final bool biometricEnabled;

  factory AccountSettingsDto.fromJson(Map<String, dynamic> json) =>
      _$AccountSettingsDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AccountSettingsDtoToJson(this);
}
