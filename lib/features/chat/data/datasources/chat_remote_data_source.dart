import 'dart:convert';

import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/chat_stream_event.dart';
import '../models/chat_message_dto.dart';
import '../models/chat_session_dto.dart';

/// The chat feature's one remote data source — non-streaming calls go
/// through `ApiClient`'s plain JSON methods exactly like
/// `EntriesRemoteDataSource`'s own `create`/`list`/`get`; [sendMessage]
/// alone goes through `ApiClient.postStream` and owns the one piece of
/// SSE-specific logic this story introduces: splitting the raw byte
/// stream into `event:`/`data:` blocks and mapping each into a
/// [ChatStreamEvent] (or an in-band [Failure]) — kept feature-local per
/// the Code Map, `ApiClient` itself knows nothing about the SSE grammar.
class ChatRemoteDataSource {
  ChatRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, List<ChatSessionDto>>> listSessions() async {
    final result = await _apiClient.get('chat-sessions-list');
    return result.flatMap((json) {
      try {
        final data = json['data'] as List<dynamic>;
        return right(
          data
              .map(
                (item) => ChatSessionDto.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
        );
      } catch (error) {
        // A 200 response that doesn't match the expected shape is a
        // client-side parse failure, never a backend-sent code — same
        // RNF09 rationale `EntriesRemoteDataSource`'s own calls document.
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }

  /// Sends no `title` (Boundaries: "`chat-sessions-create` with no
  /// title") — the contract's own `title` field is optional
  /// (`openapi.yaml`), an empty body is valid.
  Future<Either<Failure, ChatSessionDto>> createSession() async {
    final result = await _apiClient.post('chat-sessions-create', data: const {});
    return result.flatMap((json) {
      try {
        final data = json['data'] as Map<String, dynamic>;
        return right(ChatSessionDto.fromJson(data));
      } catch (error) {
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }

  Future<Either<Failure, List<ChatMessageDto>>> listMessages(
    String sessionId,
  ) async {
    final result = await _apiClient.get(
      'chat-messages-list',
      pathParams: [sessionId],
    );
    return result.flatMap((json) {
      try {
        final data = json['data'] as List<dynamic>;
        return right(
          data
              .map(
                (item) => ChatMessageDto.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
        );
      } catch (error) {
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }

  /// Consumes `ApiClient.postStream('chat-messages-send', pathParams:
  /// [sessionId], data: {'content': content})` chunk by chunk, buffering
  /// raw text until a full `\n\n`-terminated SSE event block is
  /// available, then hands each complete block to [_parseEvent].
  ///
  /// Terminal handling (Design Notes/I/O matrix):
  /// - An upstream `Left` (an offline/timeout/etc. failure from the
  ///   underlying HTTP call itself, surfaced by `ApiClient.postStream`) is
  ///   forwarded as-is and ends the stream immediately — covers "Send
  ///   while offline" (an immediate `Left(Failure.networkOffline)`, never
  ///   queued) and any other transport-level failure.
  /// - A parsed `done` event or an in-band `error` event (mapped via
  ///   [Failure.fromCode]) both end the stream right after being emitted
  ///   — the backend's own SSE ordering guarantees neither is followed by
  ///   anything else worth reading.
  /// - If the underlying byte stream simply ends (no exception, no
  ///   `done`/`error` event ever parsed) — a mid-stream drop — a single
  ///   trailing `Left(Failure.networkTimeout)` is emitted, since the
  ///   closed, 13-code taxonomy has no dedicated "dropped stream" code
  ///   (Design Notes).
  Stream<Either<Failure, ChatStreamEvent>> sendMessage(
    String sessionId,
    String content,
  ) async* {
    var buffer = '';
    await for (final chunkResult in _apiClient.postStream(
      'chat-messages-send',
      pathParams: [sessionId],
      data: {'content': content},
    )) {
      final upstreamFailure = chunkResult.fold((f) => f, (_) => null);
      if (upstreamFailure != null) {
        yield left(upstreamFailure);
        return;
      }
      final chunk = chunkResult.fold((_) => '', (s) => s);
      buffer += chunk.replaceAll('\r\n', '\n');

      var separatorIndex = buffer.indexOf('\n\n');
      while (separatorIndex != -1) {
        final rawEvent = buffer.substring(0, separatorIndex);
        buffer = buffer.substring(separatorIndex + 2);
        if (rawEvent.trim().isNotEmpty) {
          final parsed = _parseEvent(rawEvent);
          if (parsed != null) {
            final isDone = parsed.fold((_) => false, (e) => e is ChatDoneEvent);
            final isFailure = parsed.isLeft();
            yield parsed;
            // A `done`/in-band-error exit is a clean terminal event, not
            // a drop — return directly, skipping the trailing
            // mid-stream-drop failure below.
            if (isDone || isFailure) {
              return;
            }
          }
        }
        separatorIndex = buffer.indexOf('\n\n');
      }
    }
    // Reached only if the byte stream ended on its own (no exception, no
    // `done`/`error` event ever parsed) — a mid-stream drop.
    yield left(
      const Failure.networkTimeout(
        message: 'Connection closed before the response completed',
      ),
    );
  }

  /// Parses one complete, blank-line-delimited SSE event block into a
  /// [ChatStreamEvent] (`Right`), an in-band failure (`Left`), or `null`
  /// when the block should simply be skipped — a `context` event
  /// (Boundaries: "received and discarded", never surfaced as a
  /// [ChatStreamEvent]) or any event name this client doesn't recognize
  /// (forward-compatible: an unknown future event type is ignored rather
  /// than treated as malformed). Any JSON-decode failure, or a decoded
  /// payload missing the field a known event name requires, maps to
  /// [Failure.malformedResponse] (Design Notes: "anything that fails to
  /// parse as expected becomes `Failure.malformedResponse`, never a
  /// crash") — never a thrown exception escaping into [sendMessage]'s own
  /// `async*` body.
  Either<Failure, ChatStreamEvent>? _parseEvent(String rawEvent) {
    String? eventName;
    final dataLines = <String>[];
    for (final line in rawEvent.split('\n')) {
      if (line.startsWith('event:')) {
        eventName = line.substring('event:'.length).trim();
      } else if (line.startsWith('data:')) {
        var value = line.substring('data:'.length);
        if (value.startsWith(' ')) {
          value = value.substring(1);
        }
        dataLines.add(value);
      }
    }
    if (eventName == null) {
      return null;
    }
    final dataStr = dataLines.join('\n');

    switch (eventName) {
      case 'message_created':
        try {
          final json = jsonDecode(dataStr) as Map<String, dynamic>;
          return right(ChatMessageCreatedEvent(json['id'] as String));
        } catch (error) {
          return left(
            Failure.malformedResponse(
              message: 'malformed message_created event: $error',
            ),
          );
        }
      case 'context':
        // Boundaries: "never rendering the SSE `context` event's
        // retrieval/citation data" — received and discarded.
        return null;
      case 'token':
        try {
          final json = jsonDecode(dataStr) as Map<String, dynamic>;
          return right(ChatTokenEvent(json['delta'] as String));
        } catch (error) {
          return left(
            Failure.malformedResponse(
              message: 'malformed token event: $error',
            ),
          );
        }
      case 'done':
        return right(const ChatDoneEvent());
      case 'error':
        try {
          final json = jsonDecode(dataStr) as Map<String, dynamic>;
          final code = json['code'] as String;
          final message = json['message'];
          return left(
            Failure.fromCode(
              code,
              message is String ? message : 'Unknown error',
            ),
          );
        } catch (error) {
          return left(
            Failure.malformedResponse(
              message: 'malformed error event: $error',
            ),
          );
        }
      default:
        // Forward-compatible: an event name this client doesn't
        // recognize is skipped, not treated as malformed.
        return null;
    }
  }
}
