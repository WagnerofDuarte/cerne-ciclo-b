// The constructor keeps public named params (`dio`, `urlBuilder`) distinct
// from the private fields they initialize, so an initializing formal
// (which would force the external name to match) isn't a clean fit here.
// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../failure/failure.dart';
import '../session/session_expiry_notifier.dart';
import 'dio_error_code.dart';
import 'header_interceptor.dart';
import 'url_builder.dart';

/// AD-2/AD-5 — the one network façade every repository's data source calls
/// through. Builds the real URL via `UrlBuilder`, sends the request through
/// `dio` (header + retry interceptors already attached in DI), and maps
/// every outcome — success or failure — to `Either<Failure, T>`; no
/// dio/native exception ever escapes unmapped (RNF09).
///
/// Story 1.5: also the one detection point for a mid-session `AUTH_EXPIRED`
/// — signals [SessionExpiryNotifier] when one is seen outside
/// `HeaderInterceptor.anonKeyOnlyFunctions`, so the boot-time `auth-refresh`
/// call (Story 1.4's `restoreSession()`) never triggers it.
///
/// Tests mock this interface directly (per the architecture spine's testing
/// convention), not a fake transport layer underneath it.
class ApiClient {
  ApiClient({
    required Dio dio,
    required UrlBuilder urlBuilder,
    required SessionExpiryNotifier sessionExpiryNotifier,
  })  : _dio = dio,
        _urlBuilder = urlBuilder,
        _sessionExpiryNotifier = sessionExpiryNotifier;

  final Dio _dio;
  final UrlBuilder _urlBuilder;
  final SessionExpiryNotifier _sessionExpiryNotifier;

  Future<Either<Failure, Map<String, dynamic>>> get(
    String function, {
    List<String> pathParams = const [],
    Map<String, dynamic>? queryParameters,
  }) =>
      _send(
        () => _dio.get<Map<String, dynamic>>(
          _urlBuilder.build(function, pathParams),
          queryParameters: queryParameters,
        ),
      );

  Future<Either<Failure, Map<String, dynamic>>> post(
    String function, {
    List<String> pathParams = const [],
    Object? data,
  }) =>
      _send(
        () => _dio.post<Map<String, dynamic>>(
          _urlBuilder.build(function, pathParams),
          data: data,
        ),
      );

  Future<Either<Failure, Map<String, dynamic>>> patch(
    String function, {
    List<String> pathParams = const [],
    Object? data,
  }) =>
      _send(
        () => _dio.patch<Map<String, dynamic>>(
          _urlBuilder.build(function, pathParams),
          data: data,
        ),
      );

  Future<Either<Failure, Map<String, dynamic>>> delete(
    String function, {
    List<String> pathParams = const [],
    Object? data,
  }) =>
      _send(
        () => _dio.delete<Map<String, dynamic>>(
          _urlBuilder.build(function, pathParams),
          data: data,
        ),
      );

  /// spec-6-1 — streaming companion to [post]: sent with
  /// `ResponseType.stream` so the SSE response body never gets buffered
  /// into a single in-memory JSON blob the way [post]'s own
  /// `Dio.post<Map<String, dynamic>>` would. Each emitted `Right` is one
  /// raw, UTF-8-decoded chunk straight off the wire — SSE `event:`/`data:`
  /// line-splitting stays feature-local (`ChatRemoteDataSource`), this
  /// façade only owns the transport + error-mapping step (Boundaries:
  /// "ApiClient stays the one façade every datasource calls through").
  /// `allowMalformed: true` mirrors every other decode step in this app
  /// (RNF09: never throw on a malformed byte sequence) — a chunk that
  /// can't be exactly transcoded still degrades to the replacement
  /// character rather than crashing the stream.
  ///
  /// A connection that closes cleanly with no further error is simply a
  /// stream that ends with no further `Right`/`Left` emitted — detecting
  /// that as a "mid-stream drop" (no `done`/`error` SSE event ever seen)
  /// is the caller's job, not this method's; `ApiClient` has no notion of
  /// the SSE event grammar.
  Stream<Either<Failure, String>> postStream(
    String function, {
    List<String> pathParams = const [],
    Object? data,
  }) async* {
    try {
      final response = await _dio.post<ResponseBody>(
        _urlBuilder.build(function, pathParams),
        data: data,
        options: Options(responseType: ResponseType.stream),
      );
      final body = response.data;
      if (body == null) {
        yield left(
          const Failure.malformedResponse(message: 'Empty stream body'),
        );
        return;
      }
      // `Utf8Decoder.bind` (not a per-chunk `utf8.decode`) carries any
      // incomplete trailing multi-byte sequence over to the next chunk —
      // required here since dio's own chunk boundaries split on byte
      // count, not on character boundaries, and this app's primary
      // language (pt-BR) uses multi-byte UTF-8 characters constantly.
      await for (final text in const Utf8Decoder(
        allowMalformed: true,
      ).bind(body.stream)) {
        yield right(text);
      }
    } on DioException catch (e) {
      yield left(await _mapStreamDioException(e));
    } catch (e) {
      yield left(Failure.malformedResponse(message: e.toString()));
    }
  }

  /// [postStream]'s own error-mapping step. A non-2xx response to a
  /// `ResponseType.stream` request is never auto-decoded into a `Map` by
  /// dio's default transformer (dio's own contract: "you must return the
  /// responseBody when Options.responseType is stream") — [e.response]'s
  /// `data` is still the raw, undrained [ResponseBody] at this point, so
  /// [_mapDioException]'s own `data is Map` check always misses it and
  /// would otherwise collapse every real backend error code on this one
  /// streaming endpoint into [Failure.malformedResponse]. Draining and
  /// decoding it here, once, keeps that same `{code, message}` mapping
  /// (`error-taxonomy.md`) correct for the stream path too, without
  /// changing [_mapDioException]/`dioErrorCodeOf` themselves — both are
  /// shared with `RetryInterceptor`, which never sees a stream response at
  /// all (it retries before dio's transformer runs), so widening their
  /// `Map`-only contract isn't needed here. Any failure to drain/decode
  /// (including a non-JSON body) falls back to [_mapDioException]'s own
  /// generic mapping unchanged.
  Future<Failure> _mapStreamDioException(DioException e) async {
    final data = e.response?.data;
    if (data is ResponseBody) {
      try {
        final bytes = await data.stream.expand((chunk) => chunk).toList();
        final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
        if (decoded is Map && decoded['code'] is String) {
          final message = decoded['message'];
          final failure = Failure.fromCode(
            decoded['code'] as String,
            (message is String ? message : null) ?? 'Unknown error',
          );
          if (failure is AuthExpired && !_isAnonKeyOnlyCall(e)) {
            _sessionExpiryNotifier.notifyExpired();
          }
          return failure;
        }
      } catch (_) {
        // Falls through to the generic mapping below — same "never throw"
        // rationale every other decode step in this file already follows.
      }
    }
    return _mapDioException(e);
  }

  Future<Either<Failure, Map<String, dynamic>>> _send(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      final response = await request();
      final data = response.data;
      if (data == null) {
        return left(
          const Failure.malformedResponse(message: 'Empty response body'),
        );
      }
      return right(data);
    } on DioException catch (e) {
      return left(_mapDioException(e));
    } catch (e) {
      return left(Failure.malformedResponse(message: e.toString()));
    }
  }

  Failure _mapDioException(DioException e) {
    final code = dioErrorCodeOf(e);
    if (code == null) {
      // Covers a cancelled request and an HTTP response that doesn't carry
      // the expected `{code, message, retryable}` body — neither is one of
      // the 13 backend codes, so neither is retryable (dioErrorCodeOf).
      return Failure.malformedResponse(
        message: e.message ?? 'Malformed response',
      );
    }
    final data = e.response?.data;
    final message = data is Map ? data['message'] : null;
    final failure = Failure.fromCode(
      code,
      (message is String ? message : null) ?? e.message ?? 'Unknown error',
    );
    if (failure is AuthExpired && !_isAnonKeyOnlyCall(e)) {
      _sessionExpiryNotifier.notifyExpired();
    }
    return failure;
  }

  /// Whether [e]'s request targeted one of the three `security: []`
  /// operations (signup, login, refresh) — the only calls `AUTH_EXPIRED`
  /// must never be treated as a mid-session expiry for, since those are the
  /// anon-keyed calls Story 1.4's `restoreSession()` itself makes.
  ///
  /// Mirrors `HeaderInterceptor.onRequest`'s own fail-open behavior: a
  /// malformed `requestOptions.path` (shouldn't happen — `UrlBuilder`
  /// always produces a valid URL) is treated as "not anon-key-only" rather
  /// than letting a `FormatException` escape this mapping step unmapped
  /// (RNF09).
  bool _isAnonKeyOnlyCall(DioException e) {
    String function;
    try {
      function = HeaderInterceptor.functionNameOf(e.requestOptions.path);
    } catch (_) {
      function = '';
    }
    return HeaderInterceptor.anonKeyOnlyFunctions.contains(function);
  }
}
