import 'dart:async';
import 'dart:developer' as developer;

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_service.dart';
import '../models/chat_message.dart';

class SocketService {
  SocketService._();

  static final SocketService instance = SocketService._();

  io.Socket? _socket;
  String? _joinedEmail;

  final StreamController<Map<String, dynamic>> _bookingStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
    final StreamController<ChatMessage> _eventMessageController =
      StreamController<ChatMessage>.broadcast();
    final StreamController<Map<String, dynamic>> _chatNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();
    final StreamController<Map<String, dynamic>> _chatUnreadUpdatedController =
      StreamController<Map<String, dynamic>>.broadcast();
    final StreamController<Map<String, dynamic>> _eventTypingController =
      StreamController<Map<String, dynamic>>.broadcast();

    final Set<int> _joinedEventRooms = <int>{};

  Stream<Map<String, dynamic>> get bookingStatusUpdates =>
      _bookingStatusController.stream;
  Stream<ChatMessage> get eventMessages => _eventMessageController.stream;
    Stream<Map<String, dynamic>> get chatNotifications =>
      _chatNotificationController.stream;
    Stream<Map<String, dynamic>> get chatUnreadUpdates =>
      _chatUnreadUpdatedController.stream;
    Stream<Map<String, dynamic>> get eventTypingUpdates =>
      _eventTypingController.stream;

  void connectForUser({required String email, required String token}) {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedToken = token.trim();
    if (normalizedEmail.isEmpty || normalizedToken.isEmpty) {
      return;
    }

    if (_socket == null) {
      _socket = io.io(
        ApiService.baseUrl,
        io.OptionBuilder()
            .setAuth({'token': normalizedToken})
            .setTransports(['websocket'])
            .enableReconnection()
            .disableAutoConnect()
            .build(),
      );

      _socket!.onConnect((_) {
        developer.log('Socket connected', name: 'SocketService');
        if (_joinedEmail != null && _joinedEmail!.isNotEmpty) {
          _socket!.emit('join-room', _joinedEmail);
          developer.log(
            'Joined room request sent for $_joinedEmail',
            name: 'SocketService',
          );
        }
      });

      _socket!.onConnectError((error) {
        developer.log(
          'Socket connect error: $error',
          name: 'SocketService',
          error: error,
        );
      });

      _socket!.onError((error) {
        developer.log(
          'Socket error: $error',
          name: 'SocketService',
          error: error,
        );
      });

      _socket!.onDisconnect((reason) {
        developer.log(
          'Socket disconnected: $reason',
          name: 'SocketService',
        );
      });

      _socket!.on('booking-status-updated', (payload) {
        developer.log(
          'Received booking-status-updated: $payload',
          name: 'SocketService',
        );
        if (payload is Map) {
          _bookingStatusController.add(Map<String, dynamic>.from(payload));
        }
      });

      _socket!.on('event-message', (payload) {
        developer.log(
          'Received event-message: $payload',
          name: 'SocketService',
        );
        if (payload is Map) {
          _eventMessageController.add(
            ChatMessage.fromJson(Map<String, dynamic>.from(payload)),
          );
        }
      });

      _socket!.on('chat-notification', (payload) {
        developer.log(
          'Received chat-notification: $payload',
          name: 'SocketService',
        );
        if (payload is Map) {
          _chatNotificationController.add(Map<String, dynamic>.from(payload));
        }
      });

      _socket!.on('chat-unread-updated', (payload) {
        developer.log(
          'Received chat-unread-updated: $payload',
          name: 'SocketService',
        );
        if (payload is Map) {
          _chatUnreadUpdatedController.add(Map<String, dynamic>.from(payload));
        }
      });

      _socket!.on('chat-unread-reset', (payload) {
        developer.log(
          'Received chat-unread-reset: $payload',
          name: 'SocketService',
        );
        if (payload is Map) {
          final map = Map<String, dynamic>.from(payload);
          map['unreadDelta'] = 0;
          map['unreadCount'] = 0;
          _chatUnreadUpdatedController.add(map);
        }
      });

      _socket!.on('event-typing', (payload) {
        developer.log(
          'Received event-typing: $payload',
          name: 'SocketService',
        );
        if (payload is Map) {
          _eventTypingController.add(Map<String, dynamic>.from(payload));
        }
      });

      _socket!.connect();
    }

    _joinedEmail = normalizedEmail;

    _socket!.auth = {'token': normalizedToken};

    if (_socket!.connected) {
      _socket!.emit('join-room', normalizedEmail);
    } else {
      _socket!.connect();
    }
  }

  bool get isConnected => _socket?.connected ?? false;

  Future<void> waitUntilConnected({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (isConnected) {
      return;
    }

    if (_socket == null) {
      throw Exception('Socket bağlantısı kurulamadı.');
    }

    final startedAt = DateTime.now();
    while (!isConnected) {
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed >= timeout) {
        throw Exception('Socket bağlantı zaman aşımı.');
      }

      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> joinEventRoom(int eventId) {
    final completer = Completer<void>();

    if (eventId <= 0) {
      return Future.error(Exception('Geçersiz event id.'));
    }

    if (_socket == null || !isConnected) {
      return Future.error(Exception('Socket bağlantısı hazır değil.'));
    }

    _socket!.emitWithAck('join-event-room', eventId, ack: (response) {
      final map = response is Map ? Map<String, dynamic>.from(response) : const <String, dynamic>{};
      if (map['ok'] == true) {
        _joinedEventRooms.add(eventId);
        completer.complete();
      } else {
        completer.completeError(
          Exception((map['message'] ?? 'Etkinlik odasına katılım başarısız.').toString()),
        );
      }
    });

    return completer.future;
  }

  void leaveEventRoom(int eventId) {
    if (eventId <= 0 || _socket == null || !isConnected) {
      return;
    }

    _socket!.emitWithAck('leave-event-room', eventId, ack: (_) {});
    _joinedEventRooms.remove(eventId);
  }

  void setEventTyping({required int eventId, required bool isTyping}) {
    if (eventId <= 0 || _socket == null || !isConnected) {
      return;
    }

    _socket!.emit('event-typing', {
      'eventId': eventId,
      'isTyping': isTyping,
    });
  }

  Future<void> sendEventMessage({required int eventId, required String message}) {
    final completer = Completer<void>();

    final trimmedMessage = message.trim();
    if (eventId <= 0) {
      return Future.error(Exception('Geçersiz event id.'));
    }

    if (trimmedMessage.isEmpty) {
      return Future.error(Exception('Mesaj boş olamaz.'));
    }

    if (_socket == null || !isConnected) {
      return Future.error(Exception('Socket bağlantısı hazır değil.'));
    }

    final payload = {'eventId': eventId, 'message': trimmedMessage};

    _socket!.emitWithAck('send-event-message', payload, ack: (response) {
      final map = response is Map ? Map<String, dynamic>.from(response) : const <String, dynamic>{};
      if (map['ok'] == true) {
        completer.complete();
      } else {
        completer.completeError(
          Exception((map['message'] ?? 'Mesaj gönderilemedi.').toString()),
        );
      }
    });

    return completer.future;
  }

  void disconnect() {
    _joinedEmail = null;
    _joinedEventRooms.clear();
    _socket?.dispose();
    _socket = null;
  }
}
