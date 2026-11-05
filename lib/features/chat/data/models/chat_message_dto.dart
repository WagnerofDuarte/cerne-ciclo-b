import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/chat_message.dart';

part 'chat_message_dto.g.dart';

/// `chat.messages.list`'s own response `data` item (`openapi.yaml:1180-
/// 1218`) — decodes exactly the 8 fields [ChatMessage] models, mirroring
/// `entry_dto.dart`'s own DTO shape. [role]/[status] serialize/deserialize
/// against [ChatMessageRole]/[ChatMessageStatus]'s own `.name` (same
/// `json_serializable` default-enum-handling convention `ChatSessionDto.
/// personaSnapshot` already uses) — both enums' member names already match
/// the backend's own lowercase strings exactly.
@JsonSerializable()
class ChatMessageDto {
  const ChatMessageDto({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.seq,
    required this.status,
    required this.retryCount,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final ChatMessageRole role;
  final String content;
  final int seq;
  final ChatMessageStatus status;
  final int retryCount;
  final String createdAt;

  factory ChatMessageDto.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageDtoFromJson(json);

  /// Also the exact shape written to the `chat_messages` Hive box (same
  /// convention `EntryDto.toJson()` already documents for its own box).
  Map<String, dynamic> toJson() => _$ChatMessageDtoToJson(this);

  ChatMessage toEntity() => ChatMessage(
    id: id,
    sessionId: sessionId,
    role: role,
    content: content,
    seq: seq,
    status: status,
    retryCount: retryCount,
    createdAt: createdAt,
  );
}
