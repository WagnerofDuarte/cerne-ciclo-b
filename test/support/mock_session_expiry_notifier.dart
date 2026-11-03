import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/session/session_expiry_notifier.dart';

/// Shared `mocktail` mock for [SessionExpiryNotifier] — avoids redeclaring
/// the same class in every test that mocks it (`api_client_test.dart`,
/// `session_repository_impl_test.dart`).
class MockSessionExpiryNotifier extends Mock implements SessionExpiryNotifier {}
