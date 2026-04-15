class MyBooking {
  final int id;
  final int eventId;
  final String customerName;
  final String customerEmail;
  final int ticketCount;
  final String eventTitle;
  final String eventLocation;
  final String eventDate;
  final String eventPrice;
  final String eventStatus;

  MyBooking({
    required this.id,
    required this.eventId,
    required this.customerName,
    required this.customerEmail,
    required this.ticketCount,
    required this.eventTitle,
    required this.eventLocation,
    required this.eventDate,
    required this.eventPrice,
    required this.eventStatus,
  });

  factory MyBooking.fromJson(Map<String, dynamic> json) {
    return MyBooking(
      id: json['id'] ?? 0,
      eventId: json['event_id'] ?? 0,
      customerName: json['customer_name'] ?? '',
      customerEmail: json['customer_email'] ?? '',
      ticketCount: json['ticket_count'] ?? 0,
      eventTitle: json['title'] ?? '',
      eventLocation: json['location'] ?? '',
      eventDate: json['event_date'] ?? '',
      eventPrice: json['price']?.toString() ?? '0',
      eventStatus: json['status'] ?? '',
    );
  }

  double get totalPrice {
    final unitPrice = double.tryParse(eventPrice) ?? 0;
    return unitPrice * ticketCount;
  }

  DateTime? get eventDateTime {
    return DateTime.tryParse(eventDate);
  }
}
