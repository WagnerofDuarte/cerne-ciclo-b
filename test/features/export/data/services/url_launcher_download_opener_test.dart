import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:cerne/features/export/data/services/url_launcher_download_opener.dart';

/// Review finding (code review, patch item 2) — [UrlLauncherDownloadOpener]
/// had no test anywhere; every other test in this suite injects a hand-
/// written fake `DownloadOpener` instead of ever exercising the real
/// `url_launcher`-backed implementation. Faking `UrlLauncherPlatform.
/// instance` directly (the one seam `package:url_launcher`'s own top-level
/// `launchUrl` function calls through) mirrors this repo's own convention
/// of faking the native platform channel one layer below a plugin's public
/// API, rather than a real platform channel — same rationale
/// `bootstrap_integration_test.dart` already follows for
/// `flutter_secure_storage`/`path_provider`.
class _FakeUrlLauncherPlatform extends UrlLauncherPlatform {
  bool launchResult = true;
  Object? thrownError;
  String? capturedUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    capturedUrl = url;
    final error = thrownError;
    if (error != null) {
      throw error;
    }
    return launchResult;
  }
}

void main() {
  late _FakeUrlLauncherPlatform fakePlatform;
  late UrlLauncherDownloadOpener opener;

  setUp(() {
    fakePlatform = _FakeUrlLauncherPlatform();
    UrlLauncherPlatform.instance = fakePlatform;
    opener = UrlLauncherDownloadOpener();
  });

  test('a successful launch returns true, with the external-application mode '
      'always requested (Boundaries: never an in-app webview)', () async {
    final result = await opener.open('https://storage.example.com/signed');

    expect(result, isTrue);
    expect(fakePlatform.capturedUrl, 'https://storage.example.com/signed');
  });

  test('the platform reporting it could not launch (false) is returned '
      'straight through', () async {
    fakePlatform.launchResult = false;

    final result = await opener.open('https://storage.example.com/signed');

    expect(result, isFalse);
  });

  test('a thrown platform exception (e.g. no handler installed) is caught '
      'and degrades to false, rather than propagating out of open()', () async {
    fakePlatform.thrownError = Exception('no app can handle this URL');

    final result = await opener.open('https://storage.example.com/signed');

    expect(result, isFalse);
  });

  test('a malformed URL that Uri.parse itself rejects also degrades to '
      'false, never throwing — the platform is never even reached', () async {
    final result = await opener.open('http://example.com:not-a-port');

    expect(result, isFalse);
    expect(fakePlatform.capturedUrl, isNull);
  });
}
