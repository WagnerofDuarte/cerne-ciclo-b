import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The port [HeaderInterceptor] reads the current user's access token
/// through. Owned by `core/` (not a feature) since the header-policy rule
/// (AD-5) is core infrastructure; the `auth` feature calls
/// [saveAccessToken]/[clearAccessToken] on login/logout (Story 1.3) and
/// [saveSession]/[readRefreshToken]/[clearSession] for refresh-token
/// persistence (Story 1.4) without this contract's existing three methods
/// changing.
abstract class AccessTokenProvider {
  Future<String?> readAccessToken();

  Future<void> saveAccessToken(String token);

  Future<void> clearAccessToken();

  /// Reads the refresh token persisted by [saveSession], or `null` if none
  /// is stored (fresh install / post-logout / post-clear).
  Future<String?> readRefreshToken();

  /// Persists both halves of a session pair in one call — used after
  /// signup/login/refresh so the access and refresh tokens are never saved
  /// out of step with each other.
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  });

  /// Clears both the access and refresh tokens — used when the backend
  /// reports the stored refresh token is dead (`AUTH_EXPIRED`/`AUTH_INVALID`).
  Future<void> clearSession();
}

/// Default implementation, backed by `flutter_secure_storage` — the same
/// package this story's DI bootstrap integration test proves works end to
/// end through `get_it`.
class SecureStorageAccessTokenProvider implements AccessTokenProvider {
  SecureStorageAccessTokenProvider(this._storage);

  static const _key = 'user_access_token';

  /// New key, alongside [_key], for the refresh token (Story 1.4).
  static const _refreshKey = 'user_refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: _key);

  @override
  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clearAccessToken() => _storage.delete(key: _key);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    // Refresh token first: these are two independent sequential writes
    // (no atomic multi-key transaction in `flutter_secure_storage`), so if
    // the second write below ever fails, this order leaves the *refresh*
    // token as the backend's latest-issued one — the next boot's
    // `restoreSession()` self-heals from it rather than replaying a
    // possibly-already-rotated-away one. The access token staying stale in
    // that failure case is the lesser problem: it only affects calls made
    // before the next boot.
    await _storage.write(key: _refreshKey, value: refreshToken);
    await _storage.write(key: _key, value: accessToken);
  }

  @override
  Future<void> clearSession() async {
    // Refresh token first (mirrors `saveSession`'s ordering rationale):
    // it's the one `restoreSession()` reads to decide whether to call
    // `auth-refresh` at all, so clearing it first guarantees a
    // backend-confirmed-dead token is never retried even if the
    // access-token delete below then fails.
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _key);
  }
}
