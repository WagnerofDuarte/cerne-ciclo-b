import 'package:json_annotation/json_annotation.dart';

part 'dashboard_narrative_dto.g.dart';

/// `dashboard-narrative-get`'s own response `data` (`openapi.yaml:1689-
/// 1736`) — decoded in full (`text`/`generatedAt`) even though [toDomain]
/// only ever reads [text], same "mirror the full contract" precedent
/// `DashboardAggregateDto` already sets for its own unused fields.
@JsonSerializable()
class DashboardNarrativeDto {
  const DashboardNarrativeDto({
    required this.text,
    required this.generatedAt,
  });

  final String text;
  final String generatedAt;

  factory DashboardNarrativeDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardNarrativeDtoFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardNarrativeDtoToJson(this);

  /// Code Map: `toDomain()` returns only [text] as a plain `String` — no
  /// new entity, since the chart section only ever needs the narrative's
  /// own text (Intent: "one field").
  String toDomain() => text;
}
