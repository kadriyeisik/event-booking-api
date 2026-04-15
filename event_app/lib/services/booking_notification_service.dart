import '../models/booking_notification.dart';
import '../models/my_booking.dart';

class BookingNotificationService {
  static List<BookingNotification> buildNotifications(
    List<MyBooking> bookings, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final startOfToday = DateTime(reference.year, reference.month, reference.day);

    final notifications = <BookingNotification>[];

    for (final booking in bookings) {
      final eventDate = booking.eventDateTime;
      if (eventDate == null) {
        continue;
      }

      final startOfEventDay = DateTime(eventDate.year, eventDate.month, eventDate.day);
      final daysUntil = startOfEventDay.difference(startOfToday).inDays;

      if (booking.eventStatus == 'cancelled' || booking.eventStatus == 'inactive') {
        notifications.add(
          BookingNotification(
            title: 'Etkinlik durumu degisti',
            message: '${booking.eventTitle} etkinliginin durumu ${booking.eventStatus}.',
            type: BookingNotificationType.attention,
            daysUntilEvent: daysUntil,
            booking: booking,
          ),
        );
        continue;
      }

      if (daysUntil < 0 || daysUntil > 7) {
        continue;
      }

      if (daysUntil == 0) {
        notifications.add(
          BookingNotification(
            title: 'Bugun etkinligin var',
            message: '${booking.eventTitle} bugun ${booking.eventLocation} konumunda.',
            type: BookingNotificationType.today,
            daysUntilEvent: daysUntil,
            booking: booking,
          ),
        );
      } else if (daysUntil == 1) {
        notifications.add(
          BookingNotification(
            title: 'Yarin etkinligin var',
            message: '${booking.eventTitle} icin yarin hazir ol. ${booking.ticketCount} bilet ayirttin.',
            type: BookingNotificationType.tomorrow,
            daysUntilEvent: daysUntil,
            booking: booking,
          ),
        );
      } else {
        notifications.add(
          BookingNotification(
            title: 'Yaklasan etkinlik',
            message: '${booking.eventTitle} $daysUntil gun sonra basliyor.',
            type: BookingNotificationType.upcoming,
            daysUntilEvent: daysUntil,
            booking: booking,
          ),
        );
      }
    }

    notifications.sort((a, b) {
      final compareDays = a.daysUntilEvent.compareTo(b.daysUntilEvent);
      if (compareDays != 0) {
        return compareDays;
      }
      return a.booking.id.compareTo(b.booking.id);
    });

    return notifications;
  }
}
