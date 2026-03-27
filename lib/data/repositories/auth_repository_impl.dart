import '../../core/errors/app_exception.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/result/result.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_ds.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;
  User? _currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  Future<Result<User>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _remote.signIn(email: email, password: password);
      final authUser = response.user;
      if (authUser == null) {
        throw const AppException('로그인 응답에 사용자 정보가 없습니다.');
      }
      final user = User(
        id: authUser.id,
        email: authUser.email ?? email,
        displayName: authUser.userMetadata?['name'] as String?,
      );
      _currentUser = user;
      return Success(user);
    } catch (e) {
      return Error(FailureMapper.fromException(e));
    }
  }

  @override
  Future<void> signOut() async {
    await _remote.signOut();
    _currentUser = null;
  }
}
