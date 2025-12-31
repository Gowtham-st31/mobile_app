import 'package:socket_io_client/socket_io_client.dart' as io;

class RealtimeService {
  io.Socket? _socket;

  void connect({
    required String baseUrl,
    required void Function(Map<String, dynamic>) onAdminMessage,
    required void Function(Map<String, dynamic>) onAdminMessageDeleted,
  }) {
    disconnect();

    // Flask-SocketIO default path is /socket.io
    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );

    socket.onConnect((_) {});
    socket.onDisconnect((_) {});
    socket.on('admin_message', (data) {
      // socket_io_client sometimes delivers event arguments as a List.
      dynamic payload = data;
      if (payload is List && payload.isNotEmpty) {
        payload = payload.first;
      }

      if (payload is Map) {
        onAdminMessage(payload.cast<String, dynamic>());
      }
    });

    socket.on('admin_message_deleted', (data) {
      dynamic payload = data;
      if (payload is List && payload.isNotEmpty) {
        payload = payload.first;
      }

      if (payload is Map) {
        onAdminMessageDeleted(payload.cast<String, dynamic>());
      }
    });

    socket.connect();
    _socket = socket;
  }

  void disconnect() {
    final socket = _socket;
    if (socket != null) {
      socket.dispose();
    }
    _socket = null;
  }
}
