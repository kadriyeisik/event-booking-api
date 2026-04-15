import 'package:flutter_test/flutter_test.dart';
import 'package:event_app/auth_screen.dart';
import 'package:flutter/material.dart';

void main() {
  Widget buildTestApp() {
    return const MaterialApp(
      home: AuthScreen(),
    );
  }

  testWidgets('Auth screen starts in login mode', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp());

    expect(find.text('Giriş Yap'), findsWidgets);
    expect(find.text('Kayıt Ol'), findsOneWidget);
    expect(find.text('Şifremi Unuttum'), findsOneWidget);
  });

  testWidgets('User can switch to register mode', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp());

    await tester.ensureVisible(find.text('Kayıt Ol'));
    await tester.tap(find.text('Kayıt Ol'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Ad Soyad'), findsOneWidget);
    expect(find.text('Şifre Tekrar'), findsOneWidget);
  });

  testWidgets('User can switch to forgot password mode', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp());

    await tester.ensureVisible(find.text('Şifremi Unuttum'));
    await tester.tap(find.text('Şifremi Unuttum'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Kod Gönder'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });
}
