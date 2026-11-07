// ignore_for_file: prefer_initializing_formals
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'access_token_provider.dart';

/// AD-5 — the one interceptor that owns every outgoing request's headers.
/// `apikey` is sent on every call. `Authorization` carries the anon key only
/// on the three `security: []` operations (signup, login, refresh) and the
/// user's access token on every other (`bearerAuth`) operation.
class HeaderInterceptor extends Interceptor {
  HeaderInterceptor({
    required String anonKey,
    required AccessTokenProvider accessTokenProvider,
  }) : _anonKey = anonKey,
       _accessTokenProvider = accessTokenProvider;

  /// The three operations with `security: []` in the contract — the only
  /// ones that ever send the anon key as the bearer token.
  static const anonKeyOnlyFunctions = {
    'auth-signup',
    'auth-login',
    'auth-refresh',
  };

  final String _anonKey;
  final AccessTokenProvider _accessTokenProvider;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers['apikey'] = _anonKey;

    String function;
    try {
      function = functionNameOf(options.path);
    } catch (error) {
      // A malformed `options.path` must never crash/hang the pipeline (an
      // uncaught throw here, before `handler.next` is called, would leave
      // the request unresolved forever) — proceed as if the function were
      // unrecognized rather than let it propagate.
      debugPrint(
        'HeaderInterceptor: functionNameOf failed ($error) for path '
        '"${options.path}" — treating as unrecognized.',
      );
      function = '';
    }
    if (anonKeyOnlyFunctions.contains(function)) {
      options.headers['Authorization'] = 'Bearer $_anonKey';
    } else {
      String? userToken;
      try {
        userToken = await _accessTokenProvider.readAccessToken();
      } catch (error) {
        // A thrown platform exception from the native secure-storage
        // channel must never crash the request pipeline — proceed as if no
        // token were found rather than let it propagate uncaught. Logged so
        // a genuine bug in a future AccessTokenProvider implementation
        // isn't silently invisible.
        debugPrint(
          'HeaderInterceptor: readAccessToken failed ($error) — proceeding '
          'without an Authorization header.',
        );
        userToken = null;
      }
      if (userToken != null) {
        options.headers['Authorization'] = 'Bearer $userToken';
      }
    }

    handler.next(options);
  }

  /// The `x-cerne-function` name is always the first path segment of a URL
  /// built by `UrlBuilder` (whether [path] is the full absolute URL
  /// `ApiClient` sends to `dio`, or a bare `/function/...` path) — pure, so
  /// it's independently testable.
  static String functionNameOf(String path) {
    final segments = Uri.parse(path).pathSegments;
    return segments.isNotEmpty ? segments.first : '';
  }
}
