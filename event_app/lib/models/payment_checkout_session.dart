class PaymentCheckoutSession {
  final int bookingId;
  final String sessionId;
  final String checkoutUrl;

  PaymentCheckoutSession({
    required this.bookingId,
    required this.sessionId,
    required this.checkoutUrl,
  });

  factory PaymentCheckoutSession.fromJson(Map<String, dynamic> json) {
    return PaymentCheckoutSession(
      bookingId: json['bookingId'] ?? 0,
      sessionId: json['sessionId']?.toString() ?? '',
      checkoutUrl: json['checkoutUrl']?.toString() ?? '',
    );
  }
}