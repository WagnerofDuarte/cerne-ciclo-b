import 'package:url_launcher/url_launcher.dart';

import '../../domain/services/download_opener.dart';

/// [DownloadOpener]'s concrete, `url_launcher`-backed implementation (Code
/// Map) — `LaunchMode.externalApplication` always opens [url] outside this
/// app (the OS's own browser tab/share sheet/PDF viewer), never inside an
/// in-app webview, which would effectively buffer the file instead of
/// handing it off (Boundaries).
class UrlLauncherDownloadOpener implements DownloadOpener {
  @override
  Future<bool> open(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // A malformed URL (`Uri.parse`) or a platform-channel failure
      // (`launchUrl`) must never crash the cubit's own download flow
      // (RNF09) — both degrade to the same "couldn't open it" signal a
      // plain `false` already carries.
      return false;
    }
  }
}
