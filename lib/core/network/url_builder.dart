/// AD-5 — the one URL builder in `core/`. Maps every operation to
/// `{FUNCTIONS_BASE_URL}/<x-cerne-function>/<path-params>` — never the
/// literal `openapi.yaml` REST path, which is not a real URL. Path
/// parameters are appended as trailing segments, in the same order they
/// appear in the contract's path; any literal segment after the last
/// parameter (e.g. the `/retry` of `chat.messages.retry`) does not exist in
/// the real URL and must not be passed here.
class UrlBuilder {
  const UrlBuilder(this.baseUrl);

  /// `FUNCTIONS_BASE_URL`, loaded via `flutter_dotenv` — never hardcoded.
  final String baseUrl;

  /// Builds the real request URL for [function] (the operation's
  /// `x-cerne-function` name), appending [pathParams] as trailing segments.
  String build(String function, [List<String> pathParams = const []]) {
    final trimmedBase =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final segments = [function, ...pathParams].map(Uri.encodeComponent);
    return '$trimmedBase/${segments.join('/')}';
  }
}
