/// The authenticated user — plain `{id, email}`, no `freezed` (the feature
/// has no need for the union/copyWith machinery `Failure` uses). Returned by
/// `AuthRepository.signUp`/`logIn` on success (RNF06 — domain, no
/// `flutter`/`data/` import).
class AuthenticatedUser {
  const AuthenticatedUser({required this.id, required this.email});

  final String id;
  final String email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthenticatedUser &&
          other.id == id &&
          other.email == email);

  @override
  int get hashCode => Object.hash(id, email);

  @override
  String toString() => 'AuthenticatedUser(id: $id, email: $email)';
}
