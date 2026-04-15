import 'dart:async';

import 'package:flutter/material.dart';

import 'models/chat_message.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart';

class EventChatScreen extends StatefulWidget {
  final int eventId;
  final String eventTitle;

  const EventChatScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<EventChatScreen> createState() => _EventChatScreenState();
}

class _EventChatScreenState extends State<EventChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<ChatMessage>? _messageSub;
  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  String get _myEmail =>
      (AuthService.currentUser?.email ?? '').trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    try {
      if (!SocketService.instance.isConnected) {
        final email = AuthService.currentUser?.email;
        final token = AuthService.token;
        if (email != null && email.trim().isNotEmpty && token != null && token.trim().isNotEmpty) {
          SocketService.instance.connectForUser(email: email, token: token);
        }
      }

      await SocketService.instance.waitUntilConnected();

      final history = await ApiService.fetchEventChatMessages(widget.eventId);
      await SocketService.instance.joinEventRoom(widget.eventId);

      _messageSub?.cancel();
      _messageSub = SocketService.instance.eventMessages.listen((incoming) {
        if (!mounted || incoming.eventId != widget.eventId) {
          return;
        }

        setState(() {
          _messages = [..._messages, incoming];
        });
        _scrollToBottom();
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _messages = history;
        _isLoading = false;
        _error = null;
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    SocketService.instance.leaveEventRoom(widget.eventId);
    _messageSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_isSending) {
      return;
    }

    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await SocketService.instance.sendEventMessage(
        eventId: widget.eventId,
        message: message,
      );
      _messageController.clear();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sohbet • ${widget.eventTitle}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildBody(),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 3,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Mesaj yaz...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isSending ? null : _send,
                    child: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 52),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _initializeChat();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Text('Bu oda için henüz mesaj yok. İlk mesajı sen gönder.'),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMine = message.senderEmail.trim().toLowerCase() == _myEmail;

        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isMine
                  ? Colors.deepPurple.withValues(alpha: 0.16)
                  : Colors.grey.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.senderName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message.message),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
