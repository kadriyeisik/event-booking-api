class QrTicket {
  final int id;
  final int eventId;
  final String customerName;
  final String customerEmail;
  final int ticketCount;
  final String status;
  final String paymentStatus;
  final String qrToken;
  final bool checkedIn;
  final String checkedInAt;
  final String eventTitle;
  final String eventLocation;
  final String eventDate;

  QrTicket({
    required this.id,
    required this.eventId,
    required this.customerName,
    required this.customerEmail,
    required this.ticketCount,
    required this.status,
    required this.paymentStatus,
    required this.qrToken,
    required this.checkedIn,
    required this.checkedInAt,
    required this.eventTitle,
    required this.eventLocation,
    required this.eventDate,
  });

  factory QrTicket.fromJson(Map<String, dynamic> json) {
    return QrTicket(
      id: json['id'] ?? 0,
      eventId: json['event_id'] ?? 0,
      customerName: json['customer_name'] ?? '',
      customerEmail: json['customer_email'] ?? '',
      ticketCount: json['ticket_count'] ?? 0,
      status: json['status']?.toString() ?? 'pending',
      paymentStatus: json['payment_status']?.toString() ?? 'unpaid',
      qrToken: json['qr_token']?.toString() ?? '',
      checkedIn: json['checked_in'] == 1 || json['checked_in'] == true,
      checkedInAt: json['checked_in_at']?.toString() ?? '',
      eventTitle: json['title'] ?? '',
      eventLocation: json['location'] ?? '',
      eventDate: json['event_date']?.toString() ?? '',
    );
  }
}