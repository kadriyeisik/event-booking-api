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
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  List<ChatMessage> _messages = const [];
  final Set<int> _messageIds = <int>{};
  final Map<String, String> _typingUsers = <String, String>{};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int? _nextBeforeId;
  bool _isSending = false;
  String? _error;
  Timer? _typingDebounceTimer;
  bool _isTypingSent = false;

  String get _myEmail =>
      (AuthService.currentUser?.email ?? '').trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

      final page = await ApiService.fetchEventChatMessagePage(
        eventId: widget.eventId,
        limit: 30,
      );
      await SocketService.instance.joinEventRoom(widget.eventId);

      _messageSub?.cancel();
      _messageSub = SocketService.instance.eventMessages.listen((incoming) {
        if (!mounted || incoming.eventId != widget.eventId) {
          return;
        }

        if (_messageIds.contains(incoming.id)) {
          return;
        }

        setState(() {
          _messageIds.add(incoming.id);
          _messages = [..._messages, incoming];
        });
        if (incoming.senderEmail.trim().toLowerCase() != _myEmail) {
          _markCurrentRoomAsRead();
        }
        _scrollToBottom();
      });

      _typingSub?.cancel();
      _typingSub = SocketService.instance.eventTypingUpdates.listen((payload) {
        if (!mounted) {
          return;
        }

        final incomingEventId = int.tryParse('${payload['eventId'] ?? 0}') ?? 0;
        if (incomingEventId != widget.eventId) {
          return;
        }

        final senderEmail = (payload['senderEmail'] ?? '').toString().trim().toLowerCase();
        if (senderEmail.isEmpty || senderEmail == _myEmail) {
          return;
        }

        final senderName = (payload['senderName'] ?? 'Kullanici').toString().trim();
        final isTyping = payload['isTyping'] == true;

        setState(() {
          if (isTyping) {
            _typingUsers[senderEmail] = senderName;
          } else {
            _typingUsers.remove(senderEmail);
          }
        });
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _messages = page.messages;
        _messageIds
          ..clear()
          ..addAll(page.messages.map((item) => item.id));
        _hasMore = page.hasMore;
        _nextBeforeId = page.nextBeforeId;
        _isLoading = false;
        _error = null;
      });

      _markCurrentRoomAsRead();
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
    _setTyping(false);
    SocketService.instance.leaveEventRoom(widget.eventId);
    _messageSub?.cancel();
    _typingSub?.cancel();
    _typingDebounceTimer?.cancel();
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    if (_scrollController.offset <= 120) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoading || _isLoadingMore || !_hasMore) {
      return;
    }

    final beforeId = _nextBeforeId;
    if (beforeId == null || beforeId <= 0) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final oldMax = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;

      final page = await ApiService.fetchEventChatMessagePage(
        eventId: widget.eventId,
        limit: 30,
        beforeId: beforeId,
      );

      if (!mounted) {
        return;
      }

      final incoming =
          page.messages.where((item) => !_messageIds.contains(item.id)).toList();
      for (final message in incoming) {
        _messageIds.add(message.id);
      }

      setState(() {
        _messages = [...incoming, ..._messages];
        _hasMore = page.hasMore;
        _nextBeforeId = page.nextBeforeId;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) {
          return;
        }

        final newMax = _scrollController.position.maxScrollExtent;
        final delta = newMax - oldMax;
        final target = _scrollController.offset + delta;
        final clamped =
            target.clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(clamped.toDouble());
      });
    } catch (_) {
      // Keep UI stable if pagination request fails; user can retry by scrolling.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
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
      _setTyping(false);
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

  Future<void> _markCurrentRoomAsRead() async {
    try {
      await ApiService.markEventChatAsRead(widget.eventId);
    } catch (_) {
      // Best effort sync; chat screen should continue even if this call fails.
    }
  }

  void _onTypingInputChanged(String value) {
    final hasText = value.trim().isNotEmpty;

    if (hasText) {
      _setTyping(true);
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
        _setTyping(false);
      });
    } else {
      _typingDebounceTimer?.cancel();
      _setTyping(false);
    }
  }

  void _setTyping(bool isTyping) {
    if (_isTypingSent == isTyping) {
      return;
    }

    _isTypingSent = isTyping;
    SocketService.instance.setEventTyping(
      eventId: widget.eventId,
      isTyping: isTyping,
    );
  }

  String? _typingText() {
    if (_typingUsers.isEmpty) {
      return null;
    }

    final names = _typingUsers.values.toList(growable: false);
    if (names.length == 1) {
      return '${names.first} yaziyor...';
    }

    return '${names.length} kisi yaziyor...';
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
                      onChanged: _onTypingInputChanged,
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
          if (_typingText() != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _typingText()!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
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

    return Column(
      children: [
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Expanded(
          child: ListView.builder(
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
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
