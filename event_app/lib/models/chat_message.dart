class ChatMessage {
  final int id;
  final int eventId;
  final String senderEmail;
  final String senderName;
  final String message;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.eventId,
    required this.senderEmail,
    required this.senderName,
    required this.message,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      eventId: int.tryParse('${json['event_id'] ?? json['eventId'] ?? 0}') ?? 0,
      senderEmail: (json['sender_email'] ?? json['senderEmail'] ?? '').toString(),
      senderName: (json['sender_name'] ?? json['senderName'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}