import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/chat_session.dart';

part 'chat_session_dto.g.dart';

/// `chat.sessions.list`/`chat.sessions.create`'s own response `data` object
/// (`openapi.yaml:1026-1059`/`:1098-1135`) — decodes exactly the 7 fields
/// [ChatSession] models, mirroring `entry_dto.dart`'s own DTO shape.
///
/// [persona] serializes/deserializes against [ChatPersona]'s own `.name`
/// (`json_serializable`'s default enum handling) — the enum's member names
/// already match the backend's lowercase `analitico`/`empatico`/`socratico`
/// strings exactly, same convention `EntryDto.source` already uses for
/// [EntrySource].
@JsonSerializable()
class ChatSessionDto {
  const ChatSessionDto({
    required this.id,
    required this.title,
    required this.personaSnapshot,
    required this.userMessageCount,
    required this.lastUserMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final ChatPersona personaSnapshot;
  final int userMessageCount;
  final String? lastUserMessageAt;
  final String createdAt;
  final String updatedAt;

  factory ChatSessionDto.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionDtoFromJson(json);

  /// Also the exact shape written to the `chat_sessions` Hive box (same
  /// convention `EntryDto.toJson()` already documents for its own box).
  Map<String, dynamic> toJson() => _$ChatSessionDtoToJson(this);

  ChatSession toEntity() => ChatSession(
    id: id,
    title: title,
    persona: personaSnapshot,
    userMessageCount: userMessageCount,
    lastUserMessageAt: lastUserMessageAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
