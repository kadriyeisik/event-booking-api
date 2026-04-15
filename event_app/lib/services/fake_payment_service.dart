class FakePaymentResult {
  final String reference;
  final String maskedCard;
  final double amount;

  const FakePaymentResult({
    required this.reference,
    required this.maskedCard,
    required this.amount,
  });
}

class FakePaymentService {
  static Future<FakePaymentResult> processCardPayment({
    required String cardHolder,
    required String cardNumber,
    required String expiry,
    required String cvv,
    required double amount,
  }) async {
    final normalizedCardNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
    final normalizedHolder = cardHolder.trim();
    final normalizedExpiry = expiry.trim();
    final normalizedCvv = cvv.trim();

    if (normalizedHolder.isEmpty) {
      throw Exception('Kart üzerindeki isim gerekli.');
    }

    if (normalizedCardNumber.length != 16) {
      throw Exception('Kart numarası 16 haneli olmalı.');
    }

    if (!RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').hasMatch(normalizedExpiry)) {
      throw Exception('Son kullanma tarihi AA/YY formatında olmalı.');
    }

    if (!RegExp(r'^\d{3}$').hasMatch(normalizedCvv)) {
      throw Exception('CVV 3 haneli olmalı.');
    }

    await Future<void>.delayed(const Duration(milliseconds: 1200));

    if (normalizedCardNumber == '4000000000000000' || normalizedCardNumber.endsWith('0000')) {
      throw Exception('Banka işlemi reddetti. Başka bir test kartı deneyin.');
    }

    final last4 = normalizedCardNumber.substring(normalizedCardNumber.length - 4);
    final reference = 'PAY-${DateTime.now().millisecondsSinceEpoch}';

    return FakePaymentResult(
      reference: reference,
      maskedCard: '**** **** **** $last4',
      amount: amount,
    );
  }
}