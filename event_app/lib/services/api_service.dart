import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/event.dart';
import '../models/my_booking.dart';
import '../models/admin_booking.dart';
import '../models/chat_message.dart';
import '../models/payment_checkout_session.dart';
import '../models/qr_ticket.dart';
import 'auth_service.dart';

class ChatMessagePage {
  final List<ChatMessage> messages;
  final bool hasMore;
  final int? nextBeforeId;

  ChatMessagePage({
    required this.messages,
    required this.hasMore,
    required this.nextBeforeId,
  });
}

class ChatUnreadCount {
  final int eventId;
  final int unreadCount;

  ChatUnreadCount({
    required this.eventId,
    required this.unreadCount,
  });
}

class ApiService {
  static String get baseUrl {
    const overrideUrl = String.fromEnvironment('API_BASE_URL');
    if (overrideUrl.isNotEmpty) {
      return overrideUrl;
    }

    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:3000'
        : 'http://localhost:3000';
  }

  // 401 gelirse oturumu kapat ve null döndür → çağıran logout akışını tetikler
  static bool _isUnauthorized(http.Response response) =>
      response.statusCode == 401;

  static Future<void> _handleUnauthorized() async {
    await AuthService.logout();
  }

  static Map<String, String> _buildHeaders({bool withAuth = false}) {
    final headers = <String, String>{"Content-Type": "application/json"};

    if (withAuth && AuthService.token != null) {
      headers["Authorization"] = "Bearer ${AuthService.token}";
    }

    return headers;
  }

  static Future<List<Event>> fetchEvents() async {
    final response = await http.get(Uri.parse("$baseUrl/events"));

    if (response.statusCode == 200) {
      final Map<String, dynamic> decoded = jsonDecode(response.body);
      final List data = decoded['data'];
      return data.map((e) => Event.fromJson(e)).toList();
    } else {
      throw Exception("Failed to load events");
    }
  }

  static Future<List<MyBooking>> fetchMyBookings() async {
    // Best-effort sync so paid Stripe sessions update even if webhook is delayed.
    try {
      await syncMyPayments();
    } catch (_) {}

    final response = await http.get(
      Uri.parse("$baseUrl/events/my-bookings"),
      headers: _buildHeaders(withAuth: true),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception("Oturum süresi doldu. Lütfen tekrar giriş yapın.");
    }

    if (response.statusCode == 200) {
      final body = _tryDecode(response.body);
      final List data =
          (body is Map<String, dynamic> ? body['data'] : null) ?? [];
      final bookings = data.map((e) => MyBooking.fromJson(e)).toList();

      final paidApprovedEventIds = bookings
          .where(
            (b) =>
                b.eventStatus.trim().toLowerCase() == 'approved' &&
                b.paymentStatus.trim().toLowerCase() == 'paid',
          )
          .map((b) => b.eventId)
          .toSet();

      return bookings.where((b) {
        final isPendingUnpaid =
            b.eventStatus.trim().toLowerCase() == 'pending' &&
            b.paymentStatus.trim().toLowerCase() == 'unpaid';

        if (!isPendingUnpaid) {
          return true;
        }

        // Hide stale failed attempts if a successful paid booking exists
        // for the same event.
        return !paidApprovedEventIds.contains(b.eventId);
      }).toList();
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? 'Rezervasyonlar alınamadı.'
        : 'Rezervasyonlar alınamadı.';
    throw Exception(msg);
  }

  static Future<void> syncMyPayments() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/payments/sync-my-payments'),
      headers: _buildHeaders(withAuth: true),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception('Oturum süresi doldu. Lütfen tekrar giriş yapın.');
    }

    // Sync endpoint is best-effort; non-200 responses are ignored by caller.
    if (response.statusCode == 200) {
      return;
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? 'Odeme senkronizasyonu basarisiz.'
        : 'Odeme senkronizasyonu basarisiz.';
    throw Exception(msg);
  }

  static Future<List<AdminBooking>> fetchAllBookings() async {
    final response = await http.get(
      Uri.parse("$baseUrl/events/bookings"),
      headers: _buildHeaders(withAuth: true),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception("Oturum süresi doldu. Lütfen tekrar giriş yapın.");
    }

    if (response.statusCode == 200) {
      final body = _tryDecode(response.body);
      final List data =
          (body is Map<String, dynamic> ? body['data'] : null) ?? [];
      return data.map((e) => AdminBooking.fromJson(e)).toList();
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? 'Rezervasyonlar alınamadı.'
        : 'Rezervasyonlar alınamadı.';
    throw Exception(msg);
  }

  static Future<List<ChatMessage>> fetchEventChatMessages(int eventId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/events/$eventId/chat-messages'),
      headers: _buildHeaders(withAuth: true),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception('Oturum süresi doldu. Lütfen tekrar giriş yapın.');
    }

    if (response.statusCode == 200) {
      final body = _tryDecode(response.body);
      final List data =
          (body is Map<String, dynamic> ? body['data'] : null) ?? [];
      return data
          .whereType<Map>()
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? 'Sohbet mesajları alınamadı.'
        : 'Sohbet mesajları alınamadı.';
    throw Exception(msg);
  }

  static Future<ChatMessagePage> fetchEventChatMessagePage({
    required int eventId,
    int limit = 30,
    int? beforeId,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (beforeId != null && beforeId > 0) {
      query['beforeId'] = '$beforeId';
    }

    final uri = Uri.parse('$baseUrl/events/$eventId/chat-messages')
        .replace(queryParameters: query);

    final response = await http.get(
      uri,
      headers: _buildHeaders(withAuth: true),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception('Oturum süresi doldu. Lütfen tekrar giriş yapın.');
    }

    if (response.statusCode == 200) {
      final body = _tryDecode(response.body);
      final List rawData =
          (body is Map<String, dynamic> ? body['data'] : null) ?? [];
      final messages = rawData
          .whereType<Map>()
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final meta = body is Map<String, dynamic>
          ? Map<String, dynamic>.from(body['meta'] ?? const {})
          : const <String, dynamic>{};

      final hasMore = meta['hasMore'] == true;
      final nextBeforeId = int.tryParse('${meta['nextBeforeId'] ?? ''}');

      return ChatMessagePage(
        messages: messages,
        hasMore: hasMore,
        nextBeforeId: nextBeforeId,
      );
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? 'Sohbet mesajları alınamadı.'
        : 'Sohbet mesajları alınamadı.';
    throw Exception(msg);
  }

  static Future<List<ChatUnreadCount>> fetchEventChatUnreadCounts() async {
    final response = await http.get(
      Uri.parse('$baseUrl/events/chat-unread-counts'),
      headers: _buildHeaders(withAuth: true),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception('Oturum süresi doldu. Lütfen tekrar giriş yapın.');
    }

    if (response.statusCode == 200) {
      final body = _tryDecode(response.body);
      final List rawData =
          (body is Map<String, dynamic> ? body['data'] : null) ?? [];
      return rawData
          .whereType<Map>()
          .map((item) {
            final map = Map<String, dynamic>.from(item);
            return ChatUnreadCount(
              eventId: int.tryParse('${map['eventId'] ?? map['event_id'] ?? 0}') ?? 0,
              unreadCount: int.tryParse('${map['unreadCount'] ?? map['unread_count'] ?? 0}') ?? 0,
            );
          })
          .where((item) => item.eventId > 0)
          .toList();
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? 'Sohbet okunmamis sayilari alinamadi.'
        : 'Sohbet okunmamis sayilari alinamadi.';
    throw Exception(msg);
  }

  static Future<void> markEventChatAsRead(int eventId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/events/$eventId/chat-read'),
      headers: _buildHeaders(withAuth: true),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception('Oturum süresi doldu. Lütfen tekrar giriş yapın.');
    }

    if (response.statusCode == 200) {
      return;
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? 'Sohbet okundu olarak işaretlenemedi.'
        : 'Sohbet okundu olarak işaretlenemedi.';
    throw Exception(msg);
  }

  static Future<void> updateBookingStatus({
    required int bookingId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse("$baseUrl/events/bookings/$bookingId/status"),
      headers: _buildHeaders(withAuth: true),
      body: jsonEncode({"status": status}),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception("Oturum süresi doldu. Lütfen tekrar giriş yapın.");
    }

    if (response.statusCode == 200) {
      return;
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? 'Rezervasyon güncellenemedi.'
        : 'Rezervasyon güncellenemedi.';
    throw Exception(msg);
  }

  static Future<QrTicket> fetchMyQrTicket(int bookingId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/payments/my-qr/$bookingId'),
      headers: _buildHeaders(withAuth: true),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception('Oturum süresi doldu. Lütfen tekrar giriş yapın.');
    }

    final body = _tryDecode(response.body);

    if (response.statusCode == 200) {
      final data = (body is Map<String, dynamic> ? body['data'] : null);
      if (data is Map<String, dynamic>) {
        return QrTicket.fromJson(data);
      }
      throw Exception('QR bileti okunamadı.');
    }

    final msg = body is Map
        ? body['message'] ?? 'QR bileti alınamadı.'
        : 'QR bileti alınamadı.';
    throw Exception(msg);
  }

  static Future<QrTicket> verifyQrTicket(String qrToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/payments/verify-qr'),
      headers: _buildHeaders(withAuth: true),
      body: jsonEncode({'qrToken': qrToken}),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception('Oturum süresi doldu. Lütfen tekrar giriş yapın.');
    }

    final body = _tryDecode(response.body);

    if (response.statusCode == 200) {
      final data = (body is Map<String, dynamic> ? body['data'] : null);
      if (data is Map<String, dynamic>) {
        return QrTicket.fromJson(data);
      }
      throw Exception('QR doğrulama sonucu okunamadı.');
    }

    final msg = body is Map
        ? body['message'] ?? 'QR doğrulama başarısız.'
        : 'QR doğrulama başarısız.';
    throw Exception(msg);
  }

  static Future<PaymentCheckoutSession> createCheckoutSession({
    required int eventId,
    required int ticketCount,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/payments/create-checkout-session'),
      headers: _buildHeaders(withAuth: true),
      body: jsonEncode({
        'eventId': eventId,
        'ticketCount': ticketCount,
      }),
    );

    if (_isUnauthorized(response)) {
      await _handleUnauthorized();
      throw Exception('Oturum süresi doldu. Lütfen tekrar giriş yapın.');
    }

    final body = _tryDecode(response.body);

    if (response.statusCode == 200) {
      final data = (body is Map<String, dynamic> ? body['data'] : null);
      if (data is Map<String, dynamic>) {
        return PaymentCheckoutSession.fromJson(data);
      }
      throw Exception('Checkout oturumu okunamadı.');
    }

    final msg = body is Map
        ? body['message'] ?? 'Ödeme oturumu oluşturulamadı.'
        : 'Ödeme oturumu oluşturulamadı.';
    throw Exception(msg);
  }

  static Future<void> createEvent(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse("$baseUrl/events"),
      headers: _buildHeaders(withAuth: true),
      body: jsonEncode(body),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      if (_isUnauthorized(response)) {
        await _handleUnauthorized();
        throw Exception("Oturum süresi doldu. Lütfen tekrar giriş yapın.");
      }
      throw Exception("Event eklenemedi: ${response.body}");
    }
  }

  static Future<void> updateEvent(int id, Map<String, dynamic> body) async {
    final response = await http.put(
      Uri.parse("$baseUrl/events/$id"),
      headers: _buildHeaders(withAuth: true),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      if (_isUnauthorized(response)) {
        await _handleUnauthorized();
        throw Exception("Oturum süresi doldu. Lütfen tekrar giriş yapın.");
      }
      throw Exception("Event güncellenemedi: ${response.body}");
    }
  }

  static Future<void> deleteEvent(int id) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/events/$id"),
      headers: _buildHeaders(withAuth: true),
    );

    if (response.statusCode != 200) {
      if (_isUnauthorized(response)) {
        await _handleUnauthorized();
        throw Exception("Oturum süresi doldu. Lütfen tekrar giriş yapın.");
      }
      throw Exception("Event silinemedi: ${response.body}");
    }
  }

  static Future<void> bookEvent({
    required int eventId,
    required String customerName,
    required String customerEmail,
    required int ticketCount,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/events/$eventId/book"),
      headers: _buildHeaders(withAuth: false),
      body: jsonEncode({
        "customer_name": customerName.trim(),
        "customer_email": customerEmail.trim(),
        "ticket_count": ticketCount,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return;
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? "Rezervasyon başarısız."
        : "Rezervasyon başarısız.";
    throw Exception(msg);
  }

  static dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
