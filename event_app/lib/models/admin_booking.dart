class AdminBooking {
  final int id;
  final int eventId;
  final String customerName;
  final String customerEmail;
  final int ticketCount;
  final String status;
  final String createdAt;
  final String eventTitle;
  final String eventLocation;
  final String eventDate;
  final String eventPrice;

  AdminBooking({
    required this.id,
    required this.eventId,
    required this.customerName,
    required this.customerEmail,
    required this.ticketCount,
    required this.status,
    required this.createdAt,
    required this.eventTitle,
    required this.eventLocation,
    required this.eventDate,
    required this.eventPrice,
  });

  factory AdminBooking.fromJson(Map<String, dynamic> json) {
    return AdminBooking(
      id: json['id'] ?? 0,
      eventId: json['event_id'] ?? 0,
      customerName: json['customer_name'] ?? '',
      customerEmail: json['customer_email'] ?? '',
      ticketCount: json['ticket_count'] ?? 0,
      status: json['status'] ?? 'pending',
      createdAt: json['created_at']?.toString() ?? '',
      eventTitle: json['title'] ?? '',
      eventLocation: json['location'] ?? '',
      eventDate: json['event_date'] ?? '',
      eventPrice: json['price']?.toString() ?? '0',
    );
  }

  double get totalPrice {
    final p = double.tryParse(eventPrice) ?? 0;
    return p * ticketCount;
  }
}
