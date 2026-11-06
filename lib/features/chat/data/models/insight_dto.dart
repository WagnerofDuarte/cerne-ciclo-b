import 'package:json_annotation/json_annotation.dart';

part 'insight_dto.g.dart';

/// `chat.insight.create`'s own response `data` object (`openapi.yaml:1344-
/// 1405`) — decodes only the fields `ChatRepositoryImpl.generateInsight`
/// actually needs (Code Map): [id]/[sessionId]/[createdAt] always
/// present; [triggerType]/[status]/[errorCode] kept as raw `String`
/// (never an enum like `ChatSessionDto.personaSnapshot`'s own
/// [ChatPersona] — only [status] is ever inspected, compared against the
/// literal `'ready'`); [content]/[dismissedAt]/[errorCode] nullable per
/// `openapi.yaml`'s own `nullable: true`. The wire's own `triggerKey`
/// field is never decoded here — nothing downstream ever reads the
/// echoed value back.
@JsonSerializable()
class InsightDto {
  const InsightDto({
    required this.id,
    required this.sessionId,
    required this.triggerType,
    required this.status,
    this.errorCode,
    this.content,
    this.dismissedAt,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String triggerType;
  final String status;
  final String? errorCode;
  final String? content;
  final String? dismissedAt;
  final String createdAt;

  factory InsightDto.fromJson(Map<String, dynamic> json) =>
      _$InsightDtoFromJson(json);

  Map<String, dynamic> toJson() => _$InsightDtoToJson(this);
}
