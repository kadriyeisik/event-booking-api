import 'package:flutter/material.dart';
import 'dart:async';

import 'models/my_booking.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/csv_export_service.dart';
import 'services/socket_service.dart';
import 'event_chat_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  late Future<List<MyBooking>> _bookingsFuture;
  List<MyBooking> _latestBookings = const [];
  StreamSubscription<Map<String, dynamic>>? _bookingStatusSub;
  StreamSubscription<Map<String, dynamic>>? _chatNotificationSub;
  StreamSubscription<Map<String, dynamic>>? _chatUnreadSub;
  Map<int, int> _chatUnreadCounts = const <int, int>{};

  @override
  void initState() {
    super.initState();
    _bookingsFuture = ApiService.fetchMyBookings();
    _loadUnreadCounts();

    _bookingStatusSub = SocketService.instance.bookingStatusUpdates.listen((_) {
      if (!mounted) {
        return;
      }
      _refresh();
    });

    _chatNotificationSub = SocketService.instance.chatNotifications.listen((payload) {
      if (!mounted) {
        return;
      }

      _loadUnreadCounts();

      if (ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      final senderName = (payload['senderName'] ?? 'Biri').toString();
      final preview = (payload['messagePreview'] ?? '').toString();
      final eventId = int.tryParse('${payload['eventId'] ?? 0}') ?? 0;
      final eventTitle = _latestBookings
          .where((booking) => booking.eventId == eventId)
          .map((booking) => booking.eventTitle)
          .firstWhere(
            (title) => title.trim().isNotEmpty,
            orElse: () => 'Etkinlik sohbeti',
          );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$eventTitle - $senderName: $preview'),
          duration: const Duration(seconds: 3),
        ),
      );
    });

    _chatUnreadSub = SocketService.instance.chatUnreadUpdates.listen((payload) {
      final eventId = int.tryParse('${payload['eventId'] ?? 0}') ?? 0;
      if (eventId <= 0 || !mounted) {
        return;
      }

      final unreadCount = int.tryParse('${payload['unreadCount'] ?? ''}');
      final unreadDelta = int.tryParse('${payload['unreadDelta'] ?? ''}') ?? 0;

      setState(() {
        final next = Map<int, int>.from(_chatUnreadCounts);
        if (unreadCount != null) {
          if (unreadCount <= 0) {
            next.remove(eventId);
          } else {
            next[eventId] = unreadCount;
          }
        } else {
          final current = next[eventId] ?? 0;
          final updated = current + unreadDelta;
          if (updated <= 0) {
            next.remove(eventId);
          } else {
            next[eventId] = updated;
          }
        }
        _chatUnreadCounts = next;
      });
    });
  }

  @override
  void dispose() {
    _bookingStatusSub?.cancel();
    _chatNotificationSub?.cancel();
    _chatUnreadSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadCounts() async {
    try {
      final rows = await ApiService.fetchEventChatUnreadCounts();
      if (!mounted) {
        return;
      }

      setState(() {
        _chatUnreadCounts = {
          for (final row in rows)
            if (row.unreadCount > 0) row.eventId: row.unreadCount,
        };
      });
    } catch (_) {
      // Keep current counters if unread request fails.
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _bookingsFuture = ApiService.fetchMyBookings();
    });
  }

  Future<void> _exportBookings() async {
    if (_latestBookings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dışa aktarılacak rezervasyon bulunamadı.'),
        ),
      );
      return;
    }

    try {
      await CsvExportService.shareCsv(
        filenamePrefix: 'my-bookings',
        headers: const [
          'ID',
          'Etkinlik',
          'Konum',
          'Tarih',
          'Bilet',
          'Durum',
          'Toplam',
        ],
        rows: _latestBookings
            .map(
              (booking) => [
                booking.id.toString(),
                booking.eventTitle,
                booking.eventLocation,
                _formatDate(booking.eventDate),
                booking.ticketCount.toString(),
                booking.eventStatus,
                booking.totalPrice.toStringAsFixed(2),
              ],
            )
            .toList(),
        shareText: 'Rezervasyonlarim CSV dosyasi',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV dışa aktarma başarısız: $e')));
    }
  }

  String _formatDate(String raw) {
    if (raw.length >= 10) {
      return raw.substring(0, 10);
    }
    return raw;
  }

  bool _canOpenChat(MyBooking booking) {
    final isAdmin = AuthService.currentUser?.role == 'admin';
    return isAdmin || booking.eventStatus.trim().toLowerCase() == 'approved';
  }

  int _chatUnreadForEvent(int eventId) {
    return _chatUnreadCounts[eventId] ?? 0;
  }

  Widget _buildLoadingState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: List.generate(
        6,
        (_) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _BookingSkeleton(height: 16, widthFactor: 0.5),
                SizedBox(height: 10),
                _BookingSkeleton(height: 12, widthFactor: 0.65),
                SizedBox(height: 8),
                _BookingSkeleton(height: 12, widthFactor: 0.4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.deepPurple),
            const SizedBox(height: 12),
            const Text(
              'Rezervasyonlar alınamadı',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
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

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 90),
        children: const [
          Icon(
            Icons.bookmark_outline_rounded,
            size: 72,
            color: Colors.deepPurple,
          ),
          SizedBox(height: 14),
          Center(
            child: Text(
              'Henüz rezervasyonun yok',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Etkinlik kartından rezervasyon yaptığında burada listelenecek.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezervasyonlarım'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'CSV Dışa Aktar',
            onPressed: _exportBookings,
          ),
        ],
      ),
      body: FutureBuilder<List<MyBooking>>(
        future: _bookingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error);
          }

          final bookings = snapshot.data ?? [];
          _latestBookings = bookings;
          if (bookings.isEmpty) {
            return _buildEmptyState();
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: bookings.length,
              itemBuilder: (context, index) {
                final booking = bookings[index];
                return TweenAnimationBuilder<double>(
                  duration: Duration(milliseconds: 220 + (index * 65)),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0, end: 1),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 12),
                        child: child,
                      ),
                    );
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.confirmation_number,
                                color: Colors.deepPurple,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  booking.eventTitle,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Chip(label: Text('${booking.ticketCount} bilet')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Tarih: ${_formatDate(booking.eventDate)}'),
                          Text('Konum: ${booking.eventLocation}'),
                          Text('Durum: ${booking.eventStatus}'),
                          const SizedBox(height: 8),
                          Text(
                            'Toplam: ₤${booking.totalPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _canOpenChat(booking)
                                  ? () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EventChatScreen(
                                            eventId: booking.eventId,
                                            eventTitle: booking.eventTitle,
                                          ),
                                        ),
                                      );

                                      if (!mounted) {
                                        return;
                                      }

                                      _loadUnreadCounts();
                                    }
                                  : null,
                              icon: const Icon(Icons.forum_outlined),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Sohbet Odası'),
                                  if (_chatUnreadForEvent(booking.eventId) > 0) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _chatUnreadForEvent(booking.eventId).toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _BookingSkeleton extends StatefulWidget {
  final double height;
  final double widthFactor;

  const _BookingSkeleton({required this.height, required this.widthFactor});

  @override
  State<_BookingSkeleton> createState() => _BookingSkeletonState();
}

class _BookingSkeletonState extends State<_BookingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.35,
      upperBound: 0.9,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: MediaQuery.of(context).size.width * widget.widthFactor,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
