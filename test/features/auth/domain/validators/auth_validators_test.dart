import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/features/auth/domain/validators/auth_validators.dart';

void main() {
  group('validateEmail', () {
    for (final valid in [
      'wagner@cerne.app',
      'a@b.co',
      'nome.sobrenome@dominio.com.br',
    ]) {
      test('"$valid" is accepted', () {
        expect(validateEmail(valid), isNull);
      });
    }

    for (final invalid in [
      '',
      '   ',
      'nao-e-email',
      'sem-arroba.com',
      '@sem-usuario.com',
      'sem-dominio@',
      'espacos @dominio.com',
    ]) {
      test('"$invalid" is rejected with "E-mail inválido"', () {
        expect(validateEmail(invalid), 'E-mail inválido');
      });
    }
  });

  group('validatePassword', () {
    test('a non-empty password is accepted', () {
      expect(validatePassword('segredo123'), isNull);
    });

    test('an empty password is rejected', () {
      expect(validatePassword(''), isNotNull);
    });
  });
}
