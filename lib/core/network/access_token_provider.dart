import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The port [HeaderInterceptor] reads the current user's access token
/// through. Owned by `core/` (not a feature) since the header-policy rule
/// (AD-5) is core infrastructure; the `auth` feature calls
/// [saveAccessToken]/[clearAccessToken] on login/logout once it exists
/// (Story 1.3/1.4) without this contract changing.
abstract class AccessTokenProvider {
  Future<String?> readAccessToken();

  Future<void> saveAccessToken(String token);

  Future<void> clearAccessToken();
}

/// Default implementation, backed by `flutter_secure_storage` — the same
/// package this story's DI bootstrap integration test proves works end to
/// end through `get_it`.
class SecureStorageAccessTokenProvider implements AccessTokenProvider {
  SecureStorageAccessTokenProvider(this._storage);

  static const _key = 'user_access_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: _key);

  @override
  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clearAccessToken() => _storage.delete(key: _key);
}
