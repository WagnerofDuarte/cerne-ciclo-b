// The constructor keeps public named params (`dio`, `urlBuilder`) distinct
// from the private fields they initialize, so an initializing formal
// (which would force the external name to match) isn't a clean fit here.
// ignore_for_file: prefer_initializing_formals
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
