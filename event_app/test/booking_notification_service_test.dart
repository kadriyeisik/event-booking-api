import 'package:event_app/models/my_booking.dart';
import 'package:event_app/services/booking_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildNotifications returns only upcoming reminders within 7 days', () {
    final now = DateTime(2026, 4, 11);
    final bookings = [
      MyBooking(
        id: 1,
        eventId: 1,
        customerName: 'User',
        customerEmail: 'user@test.com',
        ticketCount: 1,
        eventTitle: 'Tomorrow Event',
        eventLocation: 'Istanbul',
        eventDate: '2026-04-12 10:00:00',
        eventPrice: '150',
        eventStatus: 'active',
      ),
      MyBooking(
        id: 2,
        eventId: 2,
        customerName: 'User',
        customerEmail: 'user@test.com',
        ticketCount: 1,
        eventTitle: 'Far Event',
        eventLocation: 'Ankara',
        eventDate: '2026-04-25 10:00:00',
        eventPrice: '0',
        eventStatus: 'active',
      ),
    ];

    final notifications = BookingNotificationService.buildNotifications(bookings, now: now);

    expect(notifications.length, 1);
    expect(notifications.first.title, 'Yarin etkinligin var');
  });
}
