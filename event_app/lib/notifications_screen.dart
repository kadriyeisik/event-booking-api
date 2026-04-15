import 'package:flutter/material.dart';

import 'models/booking_notification.dart';
import 'models/my_booking.dart';
import 'services/api_service.dart';
import 'services/booking_notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<MyBooking>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchMyBookings();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ApiService.fetchMyBookings();
    });
  }

  Color _colorFor(BookingNotificationType type) {
    switch (type) {
      case BookingNotificationType.today:
        return Colors.redAccent;
      case BookingNotificationType.tomorrow:
        return Colors.orange;
      case BookingNotificationType.upcoming:
        return Colors.deepPurple;
      case BookingNotificationType.attention:
        return Colors.blueGrey;
    }
  }

  IconData _iconFor(BookingNotificationType type) {
    switch (type) {
      case BookingNotificationType.today:
        return Icons.notifications_active;
      case BookingNotificationType.tomorrow:
        return Icons.alarm;
      case BookingNotificationType.upcoming:
        return Icons.upcoming;
      case BookingNotificationType.attention:
        return Icons.info_outline;
    }
  }

  String _formatDate(String raw) {
    if (raw.length >= 10) {
      return raw.substring(0, 10);
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bildirimler')),
      body: FutureBuilder<List<MyBooking>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.notifications_off, size: 56, color: Colors.deepPurple),
                    const SizedBox(height: 10),
                    Text('Hata: ${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            );
          }

          final notifications = BookingNotificationService.buildNotifications(snapshot.data ?? []);
          if (notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 90),
                children: const [
                  Icon(Icons.notifications_none, size: 72, color: Colors.deepPurple),
                  SizedBox(height: 14),
                  Center(
                    child: Text(
                      'Yaklasan bildirimin yok',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Onumuzdeki 7 gun icindeki rezervasyonlar burada gorunecek.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final item = notifications[index];
                final color = _colorFor(item.type);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(_iconFor(item.type), color: color),
                    ),
                    title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(item.message),
                        const SizedBox(height: 6),
                        Text('${item.booking.eventTitle}  •  ${_formatDate(item.booking.eventDate)}'),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
