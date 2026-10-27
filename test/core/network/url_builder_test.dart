import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/network/url_builder.dart';

void main() {
  group('UrlBuilder.build — AD-5', () {
    test('builds {baseUrl}/{function} with no path params', () {
      const builder = UrlBuilder('https://host.example.com');
      expect(
        builder.build('auth-signup'),
        'https://host.example.com/auth-signup',
      );
    });

    test('appends path params as trailing segments, in order', () {
      const builder = UrlBuilder('https://host.example.com');
      expect(
        builder.build('chat-messages-retry', ['session-1', 'message-1']),
        'https://host.example.com/chat-messages-retry/session-1/message-1',
      );
    });

    test('strips a trailing slash from baseUrl before joining', () {
      const builder = UrlBuilder('https://host.example.com/');
      expect(
        builder.build('auth-login'),
        'https://host.example.com/auth-login',
      );
    });

    test('URL-encodes a segment that needs it', () {
      const builder = UrlBuilder('https://host.example.com');
      expect(
        builder.build('entries-get', ['id with spaces/slash']),
        'https://host.example.com/entries-get/id%20with%20spaces%2Fslash',
      );
    });
  });
}
