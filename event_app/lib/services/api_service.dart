import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/event.dart';
import '../models/my_booking.dart';
import '../models/admin_booking.dart';
import '../models/chat_message.dart';
import 'auth_service.dart';

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
      return data.map((e) => MyBooking.fromJson(e)).toList();
    }

    final body = _tryDecode(response.body);
    final msg = body is Map
        ? body['message'] ?? 'Rezervasyonlar alınamadı.'
        : 'Rezervasyonlar alınamadı.';
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
