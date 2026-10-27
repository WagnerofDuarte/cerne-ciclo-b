/// Pure local validators (RNF06/07) — no `flutter` import, no network call.
/// Tela 0.1a blocks submit locally on a malformed email *before* any round
/// trip (epics.md Story 1.3 AC).
library;

/// Deliberately permissive-but-structural: `local@domain.tld` shape, no
/// backend round trip required to catch an obviously malformed address.
final RegExp _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Returns a Portuguese inline error message, or `null` when [value] is a
/// structurally valid email.
String? validateEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || !_emailShape.hasMatch(trimmed)) {
    return 'E-mail inválido';
  }
  return null;
}

/// Returns a Portuguese inline error message, or `null` when [value] is a
/// non-empty password. The backend contract requires only `minLength: 1` —
/// no further local strength rule is invented (docs/input is silent).
String? validatePassword(String value) {
  if (value.isEmpty) {
    return 'Senha obrigatória';
  }
  return null;
}
