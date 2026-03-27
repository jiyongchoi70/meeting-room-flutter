import 'app_exception.dart';
import 'failure.dart';

class FailureMapper {
  static Failure fromException(Object error) {
    if (error is AppException) {
      return Failure(error.message, code: error.code);
    }
    return Failure(error.toString());
  }
}
