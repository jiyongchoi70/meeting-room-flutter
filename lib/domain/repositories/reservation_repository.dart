import '../../core/result/result.dart';
import '../entities/reservation.dart';

abstract class ReservationRepository {
  Future<Result<List<Reservation>>> fetchReservations({
    required DateTime from,
    required DateTime to,
  });
}
