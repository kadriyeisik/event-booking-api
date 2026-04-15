import 'package:event_app/booking_screen.dart';
import 'package:event_app/models/auth_user.dart';
import 'package:event_app/models/event.dart';
import 'package:event_app/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AuthService.currentUser = const AuthUser(
      email: 'user@test.com',
      name: 'Test User',
      role: 'user',
    );
  });

  tearDown(() {
    AuthService.currentUser = null;
    AuthService.token = null;
  });

  Widget buildApp(Event event) {
    return MaterialApp(
      home: BookingScreen(event: event),
    );
  }

  testWidgets('Paid event shows fake checkout fields', (tester) async {
    final event = Event(
      id: 1,
      title: 'Paid Event',
      description: 'Desc',
      location: 'Istanbul',
      price: '150',
      status: 'active',
      eventDate: '2026-06-13 10:00:00',
      capacity: 100,
      availableSeats: 50,
      category: 'tech',
    );

    await tester.pumpWidget(buildApp(event));

    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('Odeme Bilgileri'), findsOneWidget);
    expect(find.text('Kart Numarasi'), findsOneWidget);
    expect(find.text('Odemeyi Simule Et ve Rezerve Et'), findsOneWidget);
  });

  testWidgets('Free event skips payment section', (tester) async {
    final event = Event(
      id: 2,
      title: 'Free Event',
      description: 'Desc',
      location: 'Ankara',
      price: '0',
      status: 'active',
      eventDate: '2026-07-01 10:00:00',
      capacity: 100,
      availableSeats: 50,
      category: 'community',
    );

    await tester.pumpWidget(buildApp(event));

    expect(find.text('Ucretsiz Rezervasyon'), findsOneWidget);
    expect(find.text('Odeme Bilgileri'), findsNothing);
    expect(find.text('Ucretsiz Rezervasyonu Onayla'), findsOneWidget);
  });
}