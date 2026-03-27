import '../../core/result/result.dart';
import '../entities/user.dart';

abstract class AuthRepository {
  Future<Result<User>> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();

  User? get currentUser;
}
