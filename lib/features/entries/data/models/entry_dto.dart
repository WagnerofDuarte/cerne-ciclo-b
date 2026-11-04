import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/entry.dart';

part 'entry_dto.g.dart';

/// `POST /entries`'s response `data` object (`openapi.yaml:370-456`) —
/// decodes exactly the 9 fields [Entry] models (Code Map/Boundaries);
/// every other field (`tags`/`piiStatus`/`piiSpans`/`embeddingStatus`) is
/// simply ignored by `json_serializable`'s generated `fromJson`, same
/// convention `AccountSettingsDto` already uses for the fields it doesn't
/// model.
///
/// [source] serializes/deserializes against [EntrySource]'s own `.name`
/// (`json_serializable`'s default enum handling) — the enum's member
/// names already match the backend's lowercase `manual`/`audio`/`photo`/
/// `chat` strings exactly, so no `@JsonValue` overrides are needed.
@JsonSerializable()
class EntryDto {
  const EntryDto({
    required this.id,
    required this.content,
    required this.source,
    required this.chatMessageId,
    required this.occurredAt,
    required this.serverRevision,
    required this.createdAt,
    required this.updatedAt,
    this.mediaDurationSeconds,
  });

  final String id;
  final String content;
  final EntrySource source;
  final String? chatMessageId;
  final String occurredAt;
  final int serverRevision;
  final String createdAt;
  final String updatedAt;

  /// Sent/decoded only when non-null (Code Map) —
  /// `@JsonKey(includeIfNull: false)` drops the key from `toJson()`
  /// entirely rather than serializing an explicit `null`; a response that
  /// omits the key likewise decodes to `null` here, `json_serializable`'s
  /// default behavior for a nullable field with no `@JsonKey(required:
  /// true)`.
  @JsonKey(includeIfNull: false)
  final int? mediaDurationSeconds;

  factory EntryDto.fromJson(Map<String, dynamic> json) =>
      _$EntryDtoFromJson(json);

  /// Also the exact shape written to the `entries` Hive box (Design
  /// Notes: "raw `Map<String, dynamic>` via `EntryDto.toJson()`").
  Map<String, dynamic> toJson() => _$EntryDtoToJson(this);
}
