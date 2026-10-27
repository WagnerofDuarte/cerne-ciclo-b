// The constructor keeps public named params (`dio`, `urlBuilder`) distinct
// from the private fields they initialize, so an initializing formal
// (which would force the external name to match) isn't a clean fit here.
// ignore_for_file: prefer_initializing_formals
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../failure/failure.dart';
import 'url_builder.dart';

/// AD-2/AD-5 — the one network façade every repository's data source calls
/// through. Builds the real URL via `UrlBuilder`, sends the request through
/// `dio` (header + retry interceptors already attached in DI), and maps
/// every outcome — success or failure — to `Either<Failure, T>`; no
/// dio/native exception ever escapes unmapped (RNF09).
///
/// Tests mock this interface directly (per the architecture spine's testing
/// convention), not a fake transport layer underneath it.
class ApiClient {
  ApiClient({required Dio dio, required UrlBuilder urlBuilder})
      : _dio = dio,
        _urlBuilder = urlBuilder;

  final Dio _dio;
  final UrlBuilder _urlBuilder;

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
    final data = e.response?.data;
    if (data is Map && data['code'] is String) {
      final message = data['message'];
      return Failure.fromCode(
        data['code'] as String,
        (message is String ? message : null) ?? e.message ?? 'Unknown error',
      );
    }
    if (e.response == null) {
      // NETWORK_OFFLINE never produces an HTTP response at all
      // (error-taxonomy.md) — every connection-level dio error without a
      // response maps here.
      return Failure.networkOffline(
        message: e.message ?? 'No connection',
      );
    }
    return Failure.malformedResponse(message: e.message ?? 'Malformed response');
  }
}
