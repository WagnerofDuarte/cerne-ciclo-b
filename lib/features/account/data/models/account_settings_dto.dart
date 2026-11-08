import 'package:json_annotation/json_annotation.dart';

part 'account_settings_dto.g.dart';

/// `PATCH /account/settings`'s response `data` object
/// (`openapi.yaml:1764-1803`) carries `id`/`email`/`displayName`/`persona`/
/// `biometricEnabled`/`serverRevision`/`createdAt`/`updatedAt` — Story 2.4
/// decoded only [biometricEnabled]; spec-8-3 widens this to also decode
/// [displayName]/[email] (both required strings, per the contract's own
/// `required` list), same full-contract-decode precedent
/// `DashboardNarrativeDto` already sets for its own unused fields. `persona`
/// remains undecoded — Story 8.3's own Boundaries: "never: persona/logout/
/// delete UI" (Stories 8.4/8.5, and the persona selector is an extension
/// feature).
@JsonSerializable()
class AccountSettingsDto {
  const AccountSettingsDto({
    required this.biometricEnabled,
    required this.displayName,
    required this.email,
  });

  final bool biometricEnabled;
  final String displayName;
  final String email;

  factory AccountSettingsDto.fromJson(Map<String, dynamic> json) =>
      _$AccountSettingsDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AccountSettingsDtoToJson(this);
}
