class Announcement {
  final String id;
  final String message;
  final String sender;
  final String createdAt;

  const Announcement({
    required this.id,
    required this.message,
    required this.sender,
    required this.createdAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: (json['_id'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      sender: (json['sender'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}
