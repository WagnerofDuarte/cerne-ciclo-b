import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/features/account/data/datasources/account_remote_data_source.dart';
import 'package:cerne/features/account/data/models/account_settings_dto.dart';

import '../../../../support/write_failure_matrix_helper.dart';

class MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _settingsBody({bool biometricEnabled = true}) => {
  'data': {
    'id': 'u1',
    'email': 'a@b.com',
    'displayName': 'Alguém',
    'persona': 'empatico',
    'biometricEnabled': biometricEnabled,
    'serverRevision': 1,
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  },
};

void main() {
  late MockApiClient mockApiClient;
  late AccountRemoteDataSource dataSource;

  setUp(() {
    mockApiClient = MockApiClient();
    dataSource = AccountRemoteDataSource(mockApiClient);
  });

  // RNF09 — this story's slice of the write-failure matrix is
  // `account-settings-update`, 3 failure types, exercised through
  // `fetchSettings()` (a `PATCH {}` call is still a write endpoint per the
  // Boundaries: "no GET endpoint exists").
  runWriteFailureMatrix<AccountSettingsDto>(
    endpointName: 'account-settings-update',
    stubNetworkTimeout: () =>
        when(() => mockApiClient.patch(any(), data: any(named: 'data')))
            .thenAnswer(
              (_) async =>
                  left(const Failure.networkTimeout(message: 'Timed out')),
            ),
    stubMalformedResponse: () =>
        when(() => mockApiClient.patch(any(), data: any(named: 'data')))
            .thenAnswer((_) async => right({'unexpected': 'shape'})),
    stubNoConnection: () =>
        when(() => mockApiClient.patch(any(), data: any(named: 'data')))
            .thenAnswer(
              (_) async =>
                  left(const Failure.networkOffline(message: 'Offline')),
            ),
    invoke: () => dataSource.fetchSettings(),
  );

  group('AccountRemoteDataSource.fetchSettings', () {
    test('calls PATCH account-settings-update with exactly {} (Boundaries: '
        '"called empty to read")', () async {
      when(
        () => mockApiClient.patch(
          'account-settings-update',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => right(_settingsBody()));

      await dataSource.fetchSettings();

      final captured = verify(
        () => mockApiClient.patch(
          'account-settings-update',
          data: captureAny(named: 'data'),
        ),
      ).captured;
      expect(captured.single, <String, dynamic>{});
    });

    test('decodes only biometricEnabled from the response data object, '
        'ignoring every other field (Code Map)', () async {
      when(
        () => mockApiClient.patch(
          'account-settings-update',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => right(_settingsBody(biometricEnabled: false)));

      final result = await dataSource.fetchSettings();

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (dto) => expect(dto.biometricEnabled, isFalse),
      );
    });

    test('a backend error code maps straight through as the matching '
        'Failure', () async {
      when(
        () => mockApiClient.patch(
          'account-settings-update',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.authExpired(message: 'dead token')),
      );

      final result = await dataSource.fetchSettings();

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<AuthExpired>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('AccountRemoteDataSource.updateBiometricEnabled', () {
    test('calls PATCH account-settings-update with exactly '
        '{"biometricEnabled": enabled} — never displayName/persona '
        '(Boundaries: Epic 8\'s scope)', () async {
      when(
        () => mockApiClient.patch(
          'account-settings-update',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => right(_settingsBody(biometricEnabled: false)));

      await dataSource.updateBiometricEnabled(false);

      final captured = verify(
        () => mockApiClient.patch(
          'account-settings-update',
          data: captureAny(named: 'data'),
        ),
      ).captured;
      expect(captured.single, {'biometricEnabled': false});
    });

    test('decodes the written value back from the response', () async {
      when(
        () => mockApiClient.patch(
          'account-settings-update',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => right(_settingsBody(biometricEnabled: true)));

      final result = await dataSource.updateBiometricEnabled(true);

      result.match(
        (_) => fail('expected Right'),
        (dto) => expect(dto.biometricEnabled, isTrue),
      );
    });
  });
}
