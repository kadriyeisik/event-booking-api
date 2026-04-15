import 'my_booking.dart';

enum BookingNotificationType { today, tomorrow, upcoming, attention }

class BookingNotification {
  final String title;
  final String message;
  final BookingNotificationType type;
  final int daysUntilEvent;
  final MyBooking booking;

  const BookingNotification({
    required this.title,
    required this.message,
    required this.type,
    required this.daysUntilEvent,
    required this.booking,
  });
}
