import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';

class AuthService {
  static String get baseUrl {
    const overrideUrl = String.fromEnvironment('API_BASE_URL');
    if (overrideUrl.isNotEmpty) {
      return overrideUrl;
    }

    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:3000'
        : 'http://localhost:3000';
  }
  static const String _tokenStorageKey = 'auth_token';
  static const String _userStorageKey = 'auth_user';

  static String? token;
  static AuthUser? currentUser;

  static bool get isLoggedIn => token != null && token!.isNotEmpty;

  static Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenStorageKey);

    final userJson = prefs.getString(_userStorageKey);
    if (userJson == null || userJson.isEmpty) {
      currentUser = null;
      return;
    }

    try {
      final decodedUser = jsonDecode(userJson);
      if (decodedUser is Map<String, dynamic>) {
        currentUser = AuthUser.fromJson(decodedUser);
      }
    } on FormatException {
      currentUser = null;
    }
  }

  static Future<void> _persistSession() async {
    final prefs = await SharedPreferences.getInstance();

    if (token != null && token!.isNotEmpty) {
      await prefs.setString(_tokenStorageKey, token!);
    } else {
      await prefs.remove(_tokenStorageKey);
    }

    if (currentUser != null) {
      await prefs.setString(_userStorageKey, jsonEncode(currentUser!.toJson()));
    } else {
      await prefs.remove(_userStorageKey);
    }
  }

  static dynamic _tryDecodeBody(http.Response response) {
    if (response.body.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return null;
    }
  }

  static String _buildErrorMessage(http.Response response, String fallback) {
    final decodedBody = _tryDecodeBody(response);

    if (decodedBody is Map<String, dynamic> &&
        decodedBody['message'] is String) {
      return decodedBody['message'] as String;
    }

    final trimmedBody = response.body.trim();
    if (trimmedBody.isNotEmpty) {
      return '$fallback (HTTP ${response.statusCode})';
    }

    return '$fallback (HTTP ${response.statusCode})';
  }

  static Future<void> register(
    String name,
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "name": name.trim(),
        "email": email.trim(),
        "password": password.trim(),
      }),
    );

    if (response.statusCode == 201) {
      return;
    } else {
      throw Exception(_buildErrorMessage(response, "Kayıt yapılamadı."));
    }
  }

  static Future<void> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/forgot-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email.trim()}),
    );

    if (response.statusCode == 200) {
      return;
    } else {
      throw Exception(
        _buildErrorMessage(response, "Şifre sıfırlama başarısız."),
      );
    }
  }

  static Future<void> resetPassword(
    String email,
    String token,
    String newPassword,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/reset-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email.trim().toLowerCase(),
        "token": token.trim(),
        "newPassword": newPassword,
      }),
    );

    if (response.statusCode == 200) {
      return;
    } else {
      throw Exception(_buildErrorMessage(response, "Şifre sıfırlanamadı."));
    }
  }

  static Future<void> login(String email, String password) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email.trim(), "password": password.trim()}),
    );

    if (response.statusCode == 200) {
      final data = _tryDecodeBody(response);
      if (data is! Map<String, dynamic>) {
        throw Exception("Sunucudan beklenmeyen bir cevap geldi.");
      }

      token = data['token'];
      if (token == null || token!.isEmpty) {
        throw Exception("Geçerli bir token alınamadı.");
      }

      final userData = data['user'];
      if (userData is! Map<String, dynamic>) {
        throw Exception("Kullanıcı bilgisi alınamadı.");
      }

      currentUser = AuthUser.fromJson(userData);
      await _persistSession();
    } else {
      throw Exception(_buildErrorMessage(response, "Giriş yapılamadı."));
    }
  }

  static Future<void> updateProfile({
    String? name,
    String? currentPassword,
    String? newPassword,
  }) async {
    if (token == null || token!.isEmpty) {
      throw Exception("Oturum bulunamadı. Lütfen tekrar giriş yapın.");
    }

    final body = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) {
      body['name'] = name.trim();
    }
    if (currentPassword != null && currentPassword.isNotEmpty) {
      body['currentPassword'] = currentPassword;
    }
    if (newPassword != null && newPassword.isNotEmpty) {
      body['newPassword'] = newPassword;
    }

    final response = await http.put(
      Uri.parse("$baseUrl/auth/profile"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 401) {
      await logout();
      throw Exception("Oturum süresi doldu. Lütfen tekrar giriş yapın.");
    }

    if (response.statusCode != 200) {
      throw Exception(_buildErrorMessage(response, "Profil güncellenemedi."));
    }

    final data = _tryDecodeBody(response);
    if (data is! Map<String, dynamic>) {
      throw Exception("Sunucudan beklenmeyen bir cevap geldi.");
    }

    final userData = data['user'];
    if (userData is Map<String, dynamic>) {
      currentUser = AuthUser.fromJson(userData);
      await _persistSession();
    }
  }

  static Future<void> logout() async {
    token = null;
    currentUser = null;
    await _persistSession();
  }
}
