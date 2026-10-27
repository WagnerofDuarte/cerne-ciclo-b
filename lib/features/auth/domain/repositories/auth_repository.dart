import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/authenticated_user.dart';

/// Abstract port for Tela 0.1a's two write calls (RNF09 — every repository
/// method returns `Either<Failure, T>`, no exception ever escapes). Signup
/// and login post exactly `{email, password}` — no confirmation/display-name
/// field exists anywhere on this contract (PRD OQ-2).
abstract class AuthRepository {
  Future<Either<Failure, AuthenticatedUser>> signUp({
    required String email,
    required String password,
  });

  Future<Either<Failure, AuthenticatedUser>> logIn({
    required String email,
    required String password,
  });
}
