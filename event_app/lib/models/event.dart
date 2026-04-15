class Event {
  final int id;
  final String title;
  final String description;
  final String location;
  final String price;
  final String status;
  final String eventDate;
  final int capacity;
  final int availableSeats;
  final String? category;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.price,
    required this.status,
    required this.eventDate,
    required this.capacity,
    required this.availableSeats,
    required this.category,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      price: json['price']?.toString() ?? '0',
      status: json['status'] ?? '',
      eventDate: json['event_date'] ?? '',
      capacity: json['capacity'] ?? 0,
      availableSeats: json['available_seats'] ?? 0,
      category: json['category'],
    );
  }
}