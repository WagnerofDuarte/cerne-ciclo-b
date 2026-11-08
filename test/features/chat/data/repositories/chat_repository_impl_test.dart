import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:cerne/features/chat/data/models/chat_message_dto.dart';
import 'package:cerne/features/chat/data/models/chat_session_dto.dart';
import 'package:cerne/features/chat/data/models/insight_dto.dart';
import 'package:cerne/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:cerne/features/chat/domain/entities/chat_insight.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';

class MockChatRemoteDataSource extends Mock implements ChatRemoteDataSource {}

class MockBox extends Mock implements Box<Map> {}

ChatSessionDto _sessionDto(String id, String updatedAt) => ChatSessionDto(
  id: id,
  title: 'Sessão $id',
  personaSnapshot: ChatPersona.analitico,
  userMessageCount: 1,
  lastUserMessageAt: updatedAt,
  createdAt: updatedAt,
  updatedAt: updatedAt,
);

InsightDto _insightDto({
  String id = 'ins-1',
  String status = 'ready',
  String? content = 'conteúdo do insight',
  String? errorCode,
}) => InsightDto(
  id: id,
  sessionId: 's1',
  triggerType: 'message_count',
  status: status,
  errorCode: errorCode,
  content: content,
  dismissedAt: null,
  createdAt: '2026-01-01T00:00:00Z',
);

ChatMessageDto _messageDto(String id, String sessionId, int seq) =>
    ChatMessageDto(
      id: id,
      sessionId: sessionId,
      role: ChatMessageRole.user,
      content: 'content-$id',
      seq: seq,
      status: ChatMessageStatus.complete,
      retryCount: 0,
      createdAt: '2026-01-0${seq + 1}T00:00:00Z',
    );

void main() {
  late MockChatRemoteDataSource mockRemoteDataSource;
  late MockBox mockSessionsBox;
  late MockBox mockMessagesBox;
  late ChatRepositoryImpl repository;

  setUp(() {
    mockRemoteDataSource = MockChatRemoteDataSource();
    mockSessionsBox = MockBox();
    mockMessagesBox = MockBox();
    when(() => mockSessionsBox.put(any(), any())).thenAnswer((_) async {});
    when(() => mockSessionsBox.putAll(any())).thenAnswer((_) async {});
    when(() => mockMessagesBox.putAll(any())).thenAnswer((_) async {});
    repository = ChatRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
      sessionsBox: mockSessionsBox,
      messagesBox: mockMessagesBox,
    );
  });

  group('listSessions', () {
    test(
      'success writes through to the sessions box, then returns Right',
      () async {
        final dto = _sessionDto('s1', '2026-01-02T00:00:00Z');
        when(() => mockRemoteDataSource.listSessions())
            .thenAnswer((_) async => right([dto]));

        final result = await repository.listSessions();

        verify(() => mockSessionsBox.putAll({'s1': dto.toJson()})).called(1);
        expect(result.isRight(), isTrue);
        result.match(
          (_) => fail('expected Right'),
          (sessions) => expect(sessions.single.id, 's1'),
        );
      },
    );

    test(
      'networkOffline falls back to a full box dump, sorted updatedAt desc',
      () async {
        when(() => mockRemoteDataSource.listSessions()).thenAnswer(
          (_) async => left(const Failure.networkOffline(message: 'offline')),
        );
        when(() => mockSessionsBox.values).thenReturn([
          _sessionDto('older', '2026-01-01T00:00:00Z').toJson(),
          _sessionDto('newer', '2026-01-03T00:00:00Z').toJson(),
        ]);

        final result = await repository.listSessions();

        expect(result.isRight(), isTrue);
        result.match((_) => fail('expected Right'), (sessions) {
          expect(sessions.map((s) => s.id).toList(), ['newer', 'older']);
        });
      },
    );

    test('a non-offline/timeout failure propagates as Left, unmapped — no '
        'cache fallback', () async {
      when(() => mockRemoteDataSource.listSessions()).thenAnswer(
        (_) async => left(const Failure.authExpired(message: 'expired')),
      );

      final result = await repository.listSessions();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<AuthExpired>()),
        (_) => fail('expected Left'),
      );
      verifyNever(() => mockSessionsBox.values);
    });

    test('an empty cache still resolves to Right([]), never the original '
        'failure', () async {
      when(() => mockRemoteDataSource.listSessions()).thenAnswer(
        (_) async => left(const Failure.networkTimeout(message: 'timeout')),
      );
      when(() => mockSessionsBox.values).thenReturn(const []);

      final result = await repository.listSessions();

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (sessions) => expect(sessions, isEmpty),
      );
    });

    test('review finding: one corrupted cache entry is skipped, never '
        'discarding every other valid session in the box over it', () async {
      when(() => mockRemoteDataSource.listSessions()).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );
      when(() => mockSessionsBox.values).thenReturn([
        _sessionDto('good1', '2026-01-01T00:00:00Z').toJson(),
        {'this': 'is not a valid session shape'},
        _sessionDto('good2', '2026-01-02T00:00:00Z').toJson(),
      ]);

      final result = await repository.listSessions();

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (sessions) {
        expect(sessions.map((s) => s.id).toList(), ['good2', 'good1']);
      });
    });

    test('review fix: a malformed cached updatedAt never throws — '
        'DateTime.tryParse falls back to DateTime(0), sorting that entry '
        'last rather than crashing the whole offline-cache fallback', () async {
      when(() => mockRemoteDataSource.listSessions()).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );
      when(() => mockSessionsBox.values).thenReturn([
        _sessionDto('good', '2026-01-01T00:00:00Z').toJson(),
        _sessionDto('corruptDate', 'not-a-date').toJson(),
      ]);

      final result = await repository.listSessions();

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (sessions) {
        expect(sessions.map((s) => s.id).toList(), ['good', 'corruptDate']);
      });
    });
  });

  group('createSession', () {
    test(
      'success writes through to the sessions box, then returns Right',
      () async {
        final dto = _sessionDto('s2', '2026-01-01T00:00:00Z');
        when(() => mockRemoteDataSource.createSession())
            .thenAnswer((_) async => right(dto));

        final result = await repository.createSession();

        verify(() => mockSessionsBox.put('s2', dto.toJson())).called(1);
        expect(result.isRight(), isTrue);
      },
    );

    test('blocked offline — no cache fallback, propagates as Left', () async {
      when(() => mockRemoteDataSource.createSession()).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );

      final result = await repository.createSession();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
      verifyNever(() => mockSessionsBox.values);
    });

    test(
      'review finding: a local cache-write failure after a successful '
      'remote create still returns Right — the session already exists '
      'server-side, so a cache-write error must never mask that success',
      () async {
        final dto = _sessionDto('s3', '2026-01-01T00:00:00Z');
        when(() => mockRemoteDataSource.createSession())
            .thenAnswer((_) async => right(dto));
        when(() => mockSessionsBox.put(any(), any()))
            .thenThrow(Exception('disk full'));

        final result = await repository.createSession();

        expect(result.isRight(), isTrue);
        result.match(
          (_) => fail('expected Right — the remote create itself succeeded'),
          (session) => expect(session.id, 's3'),
        );
      },
    );
  });

  group('listMessages', () {
    test(
      'success writes through to the messages box, then returns Right',
      () async {
        final dto = _messageDto('m1', 's1', 0);
        when(() => mockRemoteDataSource.listMessages('s1'))
            .thenAnswer((_) async => right([dto]));

        final result = await repository.listMessages('s1');

        verify(() => mockMessagesBox.putAll({'m1': dto.toJson()})).called(1);
        expect(result.isRight(), isTrue);
      },
    );

    test('networkOffline falls back to the box dump, filtered to sessionId and '
        'sorted seq ascending', () async {
      when(() => mockRemoteDataSource.listMessages('s1')).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );
      when(() => mockMessagesBox.values).thenReturn([
        _messageDto('m2', 's1', 1).toJson(),
        _messageDto('other', 's2', 0).toJson(),
        _messageDto('m1', 's1', 0).toJson(),
      ]);

      final result = await repository.listMessages('s1');

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (messages) {
        expect(messages.map((m) => m.id).toList(), ['m1', 'm2']);
      });
    });

    test('review finding: one corrupted cache entry is skipped, never '
        'discarding every other valid message (including ones from other '
        'sessions) in the box over it', () async {
      when(() => mockRemoteDataSource.listMessages('s1')).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );
      when(() => mockMessagesBox.values).thenReturn([
        _messageDto('m1', 's1', 0).toJson(),
        {'this': 'is not a valid message shape'},
        _messageDto('m2', 's1', 1).toJson(),
      ]);

      final result = await repository.listMessages('s1');

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (messages) {
        expect(messages.map((m) => m.id).toList(), ['m1', 'm2']);
      });
    });
  });

  group('sendMessage', () {
    test('is a pure passthrough to the remote data source — no Hive write', () {
      final stream = Stream<Either<Failure, ChatStreamEvent>>.fromIterable([
        right(const ChatDoneEvent()),
      ]);
      when(() => mockRemoteDataSource.sendMessage('s1', 'hi'))
          .thenAnswer((_) => stream);

      expect(repository.sendMessage('s1', 'hi'), stream);
      verifyNever(() => mockMessagesBox.put(any(), any()));
      verifyNever(() => mockMessagesBox.putAll(any()));
    });
  });

  group('retryMessage — spec-6-3', () {
    test('is a pure passthrough to the remote data source — no Hive write', () {
      final stream = Stream<Either<Failure, ChatStreamEvent>>.fromIterable([
        right(const ChatDoneEvent()),
      ]);
      when(() => mockRemoteDataSource.retryMessage('s1', 'srv-user-1'))
          .thenAnswer((_) => stream);

      expect(repository.retryMessage('s1', 'srv-user-1'), stream);
      verifyNever(() => mockMessagesBox.put(any(), any()));
      verifyNever(() => mockMessagesBox.putAll(any()));
    });
  });

  group('clearLocalCache() — Story 8.4', () {
    test('clears both the sessions and messages Hive boxes, returns '
        'Right(unit)', () async {
      when(() => mockSessionsBox.clear()).thenAnswer((_) async => 0);
      when(() => mockMessagesBox.clear()).thenAnswer((_) async => 0);

      final result = await repository.clearLocalCache();

      verify(() => mockSessionsBox.clear()).called(1);
      verify(() => mockMessagesBox.clear()).called(1);
      expect(result.isRight(), isTrue);
    });

    test('a Hive clear failure on either box maps to Left(malformedResponse), '
        'never throws (RNF09)', () async {
      when(() => mockSessionsBox.clear())
          .thenThrow(Exception('disk full'));
      when(() => mockMessagesBox.clear()).thenAnswer((_) async => 0);

      final result = await repository.clearLocalCache();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('review finding: a thrown failure clearing the sessions box never '
        'skips the messages box — both are always attempted independently, '
        'so a disk-full error on one never leaves the other uncleared',
        () async {
      when(() => mockSessionsBox.clear()).thenThrow(Exception('disk full'));
      when(() => mockMessagesBox.clear()).thenAnswer((_) async => 0);

      await repository.clearLocalCache();

      verify(() => mockSessionsBox.clear()).called(1);
      verify(() => mockMessagesBox.clear()).called(1);
    });

    test('the mirror image: a thrown failure clearing the messages box '
        'never prevents the sessions box from having already been '
        'attempted (and still surfaces as Left)', () async {
      when(() => mockSessionsBox.clear()).thenAnswer((_) async => 0);
      when(() => mockMessagesBox.clear()).thenThrow(Exception('disk full'));

      final result = await repository.clearLocalCache();

      verify(() => mockSessionsBox.clear()).called(1);
      verify(() => mockMessagesBox.clear()).called(1);
      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('generateInsight — spec-6-5', () {
    test(
      'wireValue strings reach the datasource, never the enum\'s own name',
      () async {
        when(
          () => mockRemoteDataSource.generateInsight(
            's1',
            triggerType: 'message_count',
            triggerKey: 'key-1',
          ),
        ).thenAnswer((_) async => right(_insightDto()));

        await repository.generateInsight(
          's1',
          triggerType: InsightTriggerType.messageCount,
          triggerKey: 'key-1',
        );

        verify(
          () => mockRemoteDataSource.generateInsight(
            's1',
            triggerType: 'message_count',
            triggerKey: 'key-1',
          ),
        ).called(1);
      },
    );

    test('inactivity maps to its own wire string too', () async {
      when(
        () => mockRemoteDataSource.generateInsight(
          's1',
          triggerType: 'inactivity',
          triggerKey: 'key-2',
        ),
      ).thenAnswer((_) async => right(_insightDto()));

      await repository.generateInsight(
        's1',
        triggerType: InsightTriggerType.inactivity,
        triggerKey: 'key-2',
      );

      verify(
        () => mockRemoteDataSource.generateInsight(
          's1',
          triggerType: 'inactivity',
          triggerKey: 'key-2',
        ),
      ).called(1);
    });

    test('a ready status with content maps to Right(ChatInsight) — no Hive '
        'write (pure passthrough)', () async {
      when(
        () => mockRemoteDataSource.generateInsight(
          any(),
          triggerType: any(named: 'triggerType'),
          triggerKey: any(named: 'triggerKey'),
        ),
      ).thenAnswer(
        (_) async =>
            right(_insightDto(id: 'ins-9', status: 'ready', content: 'olá')),
      );

      final result = await repository.generateInsight(
        's1',
        triggerType: InsightTriggerType.messageCount,
        triggerKey: 'key-1',
      );

      expect(result.isRight(), isTrue);
      result.match((_) => fail('expected Right'), (insight) {
        expect(insight, const ChatInsight(id: 'ins-9', content: 'olá'));
      });
      verifyNever(() => mockSessionsBox.put(any(), any()));
      verifyNever(() => mockMessagesBox.put(any(), any()));
    });

    for (final status in ['generating', 'failed', 'dismissed']) {
      test('a non-ready status ($status) maps to Right(null) — RF08: never '
          'surfaced as a Failure', () async {
        when(
          () => mockRemoteDataSource.generateInsight(
            any(),
            triggerType: any(named: 'triggerType'),
            triggerKey: any(named: 'triggerKey'),
          ),
        ).thenAnswer((_) async => right(_insightDto(status: status)));

        final result = await repository.generateInsight(
          's1',
          triggerType: InsightTriggerType.messageCount,
          triggerKey: 'key-1',
        );

        expect(result.isRight(), isTrue);
        result.match(
          (_) => fail('expected Right'),
          (insight) => expect(insight, isNull),
        );
      });
    }

    test('a ready status with null content still maps to Right(null) '
        '(defensive — shouldn\'t happen per the contract)', () async {
      when(
        () => mockRemoteDataSource.generateInsight(
          any(),
          triggerType: any(named: 'triggerType'),
          triggerKey: any(named: 'triggerKey'),
        ),
      ).thenAnswer(
        (_) async => right(_insightDto(status: 'ready', content: null)),
      );

      final result = await repository.generateInsight(
        's1',
        triggerType: InsightTriggerType.messageCount,
        triggerKey: 'key-1',
      );

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (insight) => expect(insight, isNull),
      );
    });

    test('a transport Left propagates unchanged, unmapped', () async {
      when(
        () => mockRemoteDataSource.generateInsight(
          any(),
          triggerType: any(named: 'triggerType'),
          triggerKey: any(named: 'triggerKey'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );

      final result = await repository.generateInsight(
        's1',
        triggerType: InsightTriggerType.messageCount,
        triggerKey: 'key-1',
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
