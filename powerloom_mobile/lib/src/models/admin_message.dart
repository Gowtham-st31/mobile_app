class AdminMessage {
  final String id;
  final String message;
  final String sender;
  final String createdAt;

  const AdminMessage({
    required this.id,
    required this.message,
    required this.sender,
    required this.createdAt,
  });

  factory AdminMessage.fromJson(Map<String, dynamic> json) {
    return AdminMessage(
      id: (json['id'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      sender: (json['sender'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message': message,
      'sender': sender,
      'createdAt': createdAt,
    };
  }
}
