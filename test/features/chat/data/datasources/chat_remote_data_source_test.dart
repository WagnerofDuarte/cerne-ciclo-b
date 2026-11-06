import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:cerne/features/chat/domain/entities/chat_stream_event.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockApiClient;
  late ChatRemoteDataSource dataSource;

  setUp(() {
    mockApiClient = MockApiClient();
    dataSource = ChatRemoteDataSource(mockApiClient);
  });

  void stubPostStream(Stream<Either<Failure, String>> stream) {
    when(
      () => mockApiClient.postStream(
        'chat-messages-send',
        pathParams: any(named: 'pathParams'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) => stream);
  }

  void stubRetryPostStream(Stream<Either<Failure, String>> stream) {
    when(
      () => mockApiClient.postStream(
        'chat-messages-retry',
        pathParams: any(named: 'pathParams'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) => stream);
  }

  group('listSessions', () {
    test('a valid data array decodes into ChatSessionDtos', () async {
      when(() => mockApiClient.get('chat-sessions-list')).thenAnswer(
        (_) async => right({
          'data': [
            {
              'id': 's1',
              'title': 'Sessão 1',
              'personaSnapshot': 'analitico',
              'userMessageCount': 2,
              'lastUserMessageAt': '2026-01-01T00:00:00Z',
              'createdAt': '2026-01-01T00:00:00Z',
              'updatedAt': '2026-01-01T00:00:00Z',
            },
          ],
        }),
      );

      final result = await dataSource.listSessions();

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (dtos) => expect(dtos.single.id, 's1'),
      );
    });

    test('a shape mismatch maps to Left(MalformedResponse), never throws', () async {
      when(() => mockApiClient.get('chat-sessions-list')).thenAnswer(
        (_) async => right({'data': 'not-a-list'}),
      );

      final result = await dataSource.listSessions();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('an upstream Failure propagates unchanged', () async {
      when(() => mockApiClient.get('chat-sessions-list')).thenAnswer(
        (_) async =>
            left(const Failure.networkOffline(message: 'offline')),
      );

      final result = await dataSource.listSessions();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
    });

    test(
      'one malformed item is skipped, valid items still decode',
      () async {
        when(() => mockApiClient.get('chat-sessions-list')).thenAnswer(
          (_) async => right({
            'data': [
              {
                'id': 's1',
                'title': 'Sessão 1',
                'personaSnapshot': 'analitico',
                'userMessageCount': 2,
                'lastUserMessageAt': '2026-01-01T00:00:00Z',
                'createdAt': '2026-01-01T00:00:00Z',
                'updatedAt': '2026-01-01T00:00:00Z',
              },
              {'this': 'is not a valid session shape'},
            ],
          }),
        );

        final result = await dataSource.listSessions();

        expect(result.isRight(), isTrue);
        result.match(
          (_) => fail('expected Right'),
          (dtos) => expect(dtos.map((d) => d.id).toList(), ['s1']),
        );
      },
    );

    test(
      'review fix: a non-empty response where every item fails to decode '
      'maps to Left(MalformedResponse), never Right([]) — the latter '
      'would make ChatCubit._bootstrap() believe no sessions exist and '
      'spuriously create one, hiding the user\'s real sessions',
      () async {
        when(() => mockApiClient.get('chat-sessions-list')).thenAnswer(
          (_) async => right({
            'data': [
              {'this': 'is not a valid session shape'},
            ],
          }),
        );

        final result = await dataSource.listSessions();

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<MalformedResponse>()),
          (_) => fail('expected Left'),
        );
      },
    );
  });

  group('createSession', () {
    test('sends no title and decodes the created session', () async {
      when(
        () => mockApiClient.post('chat-sessions-create', data: const {}),
      ).thenAnswer(
        (_) async => right({
          'data': {
            'id': 's2',
            'title': '',
            'personaSnapshot': 'empatico',
            'userMessageCount': 0,
            'lastUserMessageAt': null,
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
          },
        }),
      );

      final result = await dataSource.createSession();

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (dto) => expect(dto.id, 's2'),
      );
    });
  });

  group('listMessages', () {
    test('appends sessionId as the one trailing path segment', () async {
      when(
        () => mockApiClient.get(
          'chat-messages-list',
          pathParams: ['s1'],
        ),
      ).thenAnswer((_) async => right({'data': <dynamic>[]}));

      final result = await dataSource.listMessages('s1');

      expect(result.isRight(), isTrue);
      verify(
        () => mockApiClient.get('chat-messages-list', pathParams: ['s1']),
      ).called(1);
    });

    test('a shape mismatch maps to Left(MalformedResponse), never throws', () async {
      when(
        () => mockApiClient.get('chat-messages-list', pathParams: ['s1']),
      ).thenAnswer((_) async => right({'data': 'not-a-list'}));

      final result = await dataSource.listMessages('s1');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test(
      'one malformed item is skipped, valid items still decode',
      () async {
        when(
          () => mockApiClient.get('chat-messages-list', pathParams: ['s1']),
        ).thenAnswer(
          (_) async => right({
            'data': [
              {
                'id': 'm1',
                'sessionId': 's1',
                'role': 'user',
                'content': 'oi',
                'seq': 1,
                'status': 'complete',
                'retryCount': 0,
                'createdAt': '2026-01-01T00:00:00Z',
              },
              {'this': 'is not a valid message shape'},
            ],
          }),
        );

        final result = await dataSource.listMessages('s1');

        expect(result.isRight(), isTrue);
        result.match(
          (_) => fail('expected Right'),
          (dtos) => expect(dtos.map((d) => d.id).toList(), ['m1']),
        );
      },
    );

    test(
      'review fix: a non-empty response where every item fails to decode '
      'maps to Left(MalformedResponse), never Right([]) — the latter '
      'would render a session\'s whole history as silently empty',
      () async {
        when(
          () => mockApiClient.get('chat-messages-list', pathParams: ['s1']),
        ).thenAnswer(
          (_) async => right({
            'data': [
              {'this': 'is not a valid message shape'},
            ],
          }),
        );

        final result = await dataSource.listMessages('s1');

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<MalformedResponse>()),
          (_) => fail('expected Left'),
        );
      },
    );
  });

  group('sendMessage — SSE parsing', () {
    test(
      'happy path: message_created -> context (discarded) -> token* -> '
      'done emits exactly the expected ChatStreamEvents, in order',
      () {
        stubPostStream(
          Stream.fromIterable([
            right(
              'event: message_created\ndata: {"id":"um1"}\n\n'
              'event: context\ndata: {"anything":"ignored"}\n\n'
              'event: token\ndata: {"delta":"Oi"}\n\n'
              'event: token\ndata: {"delta":" la"}\n\n'
              'event: done\ndata: {}\n\n',
            ),
          ]),
        );

        expect(
          dataSource.sendMessage('s1', 'hello'),
          emitsInOrder([
            isA<Right<Failure, ChatStreamEvent>>().having(
              (r) => r.getRight().toNullable(),
              'event',
              isA<ChatMessageCreatedEvent>().having(
                (e) => e.userMessageId,
                'userMessageId',
                'um1',
              ),
            ),
            isA<Right<Failure, ChatStreamEvent>>().having(
              (r) => r.getRight().toNullable(),
              'event',
              isA<ChatTokenEvent>().having((e) => e.delta, 'delta', 'Oi'),
            ),
            isA<Right<Failure, ChatStreamEvent>>().having(
              (r) => r.getRight().toNullable(),
              'event',
              isA<ChatTokenEvent>().having((e) => e.delta, 'delta', ' la'),
            ),
            isA<Right<Failure, ChatStreamEvent>>().having(
              (r) => r.getRight().toNullable(),
              'event',
              isA<ChatDoneEvent>(),
            ),
            emitsDone,
          ]),
        );
      },
    );

    test(
      'chunks split mid-event still parse correctly (buffering across '
      'chunk boundaries)',
      () {
        stubPostStream(
          Stream.fromIterable([
            right('event: tok'),
            right('en\ndata: {"del'),
            right('ta":"Oi"}\n\n'),
          ]),
        );

        expect(
          dataSource.sendMessage('s1', 'hello'),
          emitsInOrder([
            isA<Right<Failure, ChatStreamEvent>>().having(
              (r) => r.getRight().toNullable(),
              'event',
              isA<ChatTokenEvent>().having((e) => e.delta, 'delta', 'Oi'),
            ),
            // The underlying stream also ends right here with no done/
            // error event — same "mid-stream drop" trailing emission the
            // dedicated test below covers.
            isA<Left<Failure, ChatStreamEvent>>().having(
              (l) => l.value,
              'failure',
              isA<NetworkTimeout>(),
            ),
            emitsDone,
          ]),
        );
      },
    );

    test(
      'mid-stream drop (connection ends with no done/error event) yields a '
      'trailing Left(NetworkTimeout)',
      () {
        stubPostStream(
          Stream.fromIterable([
            right('event: token\ndata: {"delta":"partial"}\n\n'),
            // The underlying stream simply ends here — no done, no error.
          ]),
        );

        expect(
          dataSource.sendMessage('s1', 'hello'),
          emitsInOrder([
            isA<Right<Failure, ChatStreamEvent>>(),
            isA<Left<Failure, ChatStreamEvent>>().having(
              (l) => l.value,
              'failure',
              isA<NetworkTimeout>(),
            ),
            emitsDone,
          ]),
        );
      },
    );

    test(
      'an in-band error event maps through Failure.fromCode and ends the '
      'stream — no trailing NetworkTimeout double-emission',
      () {
        stubPostStream(
          Stream.fromIterable([
            right(
              'event: token\ndata: {"delta":"partial"}\n\n'
              'event: error\ndata: {"code":"RATE_LIMITED",'
              '"message":"slow down"}\n\n',
            ),
          ]),
        );

        expect(
          dataSource.sendMessage('s1', 'hello'),
          emitsInOrder([
            isA<Right<Failure, ChatStreamEvent>>(),
            isA<Left<Failure, ChatStreamEvent>>().having(
              (l) => l.value,
              'failure',
              isA<RateLimited>(),
            ),
            emitsDone,
          ]),
        );
      },
    );

    test(
      'an upstream Left (e.g. offline before any byte streamed) is '
      'forwarded immediately and ends the stream',
      () {
        stubPostStream(
          Stream.fromIterable([
            left(const Failure.networkOffline(message: 'offline')),
          ]),
        );

        expect(
          dataSource.sendMessage('s1', 'hello'),
          emitsInOrder([
            isA<Left<Failure, ChatStreamEvent>>().having(
              (l) => l.value,
              'failure',
              isA<NetworkOffline>(),
            ),
            emitsDone,
          ]),
        );
      },
    );

    test(
      'a malformed token payload maps to Left(MalformedResponse) and ends '
      'the stream, never throwing',
      () {
        stubPostStream(
          Stream.fromIterable([
            right('event: token\ndata: not-json-at-all\n\n'),
          ]),
        );

        expect(
          dataSource.sendMessage('s1', 'hello'),
          emitsInOrder([
            isA<Left<Failure, ChatStreamEvent>>().having(
              (l) => l.value,
              'failure',
              isA<MalformedResponse>(),
            ),
            emitsDone,
          ]),
        );
      },
    );

    test('an unrecognized event name is skipped, not treated as malformed', () {
      stubPostStream(
        Stream.fromIterable([
          right(
            'event: future_event\ndata: {"whatever":true}\n\n'
            'event: done\ndata: {}\n\n',
          ),
        ]),
      );

      expect(
        dataSource.sendMessage('s1', 'hello'),
        emitsInOrder([
          isA<Right<Failure, ChatStreamEvent>>().having(
            (r) => r.getRight().toNullable(),
            'event',
            isA<ChatDoneEvent>(),
          ),
          emitsDone,
        ]),
      );
    });
  });

  group('retryMessage — spec-6-3, shares _consumeSse with sendMessage', () {
    test(
      'calls chat-messages-retry with sessionId then userMessageId as the '
      'two trailing path segments, and an empty body',
      () async {
        stubRetryPostStream(
          Stream.fromIterable([right('event: done\ndata: {}\n\n')]),
        );

        final result = await dataSource
            .retryMessage('s1', 'srv-user-1')
            .toList();

        expect(result.single.isRight(), isTrue);
        verify(
          () => mockApiClient.postStream(
            'chat-messages-retry',
            pathParams: ['s1', 'srv-user-1'],
            data: const {},
          ),
        ).called(1);
      },
    );

    test(
      'same terminal handling as sendMessage: a mid-stream drop (no done/'
      'error event) yields a trailing Left(NetworkTimeout)',
      () {
        stubRetryPostStream(
          Stream.fromIterable([
            right('event: token\ndata: {"delta":"partial"}\n\n'),
          ]),
        );

        expect(
          dataSource.retryMessage('s1', 'srv-user-1'),
          emitsInOrder([
            isA<Right<Failure, ChatStreamEvent>>(),
            isA<Left<Failure, ChatStreamEvent>>().having(
              (l) => l.value,
              'failure',
              isA<NetworkTimeout>(),
            ),
            emitsDone,
          ]),
        );
      },
    );

    test(
      'an upstream Left (e.g. offline) is forwarded immediately and ends '
      'the stream',
      () {
        stubRetryPostStream(
          Stream.fromIterable([
            left(const Failure.networkOffline(message: 'offline')),
          ]),
        );

        expect(
          dataSource.retryMessage('s1', 'srv-user-1'),
          emitsInOrder([
            isA<Left<Failure, ChatStreamEvent>>().having(
              (l) => l.value,
              'failure',
              isA<NetworkOffline>(),
            ),
            emitsDone,
          ]),
        );
      },
    );

    test(
      'review finding: the context event is discarded the same way as '
      'sendMessage\'s own happy path — openapi.yaml documents the same '
      'event order for chat-messages-retry',
      () {
        stubRetryPostStream(
          Stream.fromIterable([
            right(
              'event: context\ndata: {"anything":"ignored"}\n\n'
              'event: token\ndata: {"delta":"nova"}\n\n'
              'event: done\ndata: {}\n\n',
            ),
          ]),
        );

        expect(
          dataSource.retryMessage('s1', 'srv-user-1'),
          emitsInOrder([
            isA<Right<Failure, ChatStreamEvent>>().having(
              (r) => r.getRight().toNullable(),
              'event',
              isA<ChatTokenEvent>().having((e) => e.delta, 'delta', 'nova'),
            ),
            isA<Right<Failure, ChatStreamEvent>>().having(
              (r) => r.getRight().toNullable(),
              'event',
              isA<ChatDoneEvent>(),
            ),
            emitsDone,
          ]),
        );
      },
    );
  });

  group('generateInsight — spec-6-5', () {
    test(
      'sends triggerType/triggerKey with sessionId as the one trailing '
      'path segment, and decodes a ready insight',
      () async {
        when(
          () => mockApiClient.post(
            'chat-insight-create',
            pathParams: ['s1'],
            data: {'triggerType': 'message_count', 'triggerKey': 'key-1'},
          ),
        ).thenAnswer(
          (_) async => right({
            'data': {
              'id': 'ins-1',
              'sessionId': 's1',
              'triggerType': 'message_count',
              'triggerKey': 'key-1',
              'status': 'ready',
              'content': 'Você mencionou gratidão 3 vezes esta semana.',
              'errorCode': null,
              'dismissedAt': null,
              'createdAt': '2026-01-01T00:00:00Z',
            },
          }),
        );

        final result = await dataSource.generateInsight(
          's1',
          triggerType: 'message_count',
          triggerKey: 'key-1',
        );

        expect(result.isRight(), isTrue);
        result.match((_) => fail('expected Right'), (dto) {
          expect(dto.id, 'ins-1');
          expect(dto.status, 'ready');
          expect(
            dto.content,
            'Você mencionou gratidão 3 vezes esta semana.',
          );
        });
      },
    );

    test(
      'a non-ready status still decodes (errorCode/content carried as-is)',
      () async {
        when(
          () => mockApiClient.post(
            'chat-insight-create',
            pathParams: ['s1'],
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async => right({
            'data': {
              'id': 'ins-2',
              'sessionId': 's1',
              'triggerType': 'inactivity',
              'triggerKey': 'key-2',
              'status': 'failed',
              'content': null,
              'errorCode': 'AI_GENERATION_TIMEOUT',
              'dismissedAt': null,
              'createdAt': '2026-01-01T00:00:00Z',
            },
          }),
        );

        final result = await dataSource.generateInsight(
          's1',
          triggerType: 'inactivity',
          triggerKey: 'key-2',
        );

        expect(result.isRight(), isTrue);
        result.match((_) => fail('expected Right'), (dto) {
          expect(dto.status, 'failed');
          expect(dto.content, isNull);
          expect(dto.errorCode, 'AI_GENERATION_TIMEOUT');
        });
      },
    );

    test('a shape mismatch maps to Left(MalformedResponse), never throws', () async {
      when(
        () => mockApiClient.post(
          'chat-insight-create',
          pathParams: ['s1'],
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => right({'data': 'not-a-map'}));

      final result = await dataSource.generateInsight(
        's1',
        triggerType: 'message_count',
        triggerKey: 'key-1',
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('an upstream Failure propagates unchanged — RF08: never an HTTP '
        'error for an in-payload failure, so this only covers a genuine '
        'transport problem', () async {
      when(
        () => mockApiClient.post(
          'chat-insight-create',
          pathParams: ['s1'],
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkTimeout(message: 'timeout')),
      );

      final result = await dataSource.generateInsight(
        's1',
        triggerType: 'message_count',
        triggerKey: 'key-1',
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkTimeout>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
