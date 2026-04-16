import 'package:flutter/material.dart';
import 'dart:async';
import 'models/booking_notification.dart';
import 'models/event.dart';
import 'models/my_booking.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/booking_notification_service.dart';
import 'services/socket_service.dart';
import 'add_edit_event_page.dart';
import 'booking_screen.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';
import 'admin_bookings_screen.dart';
import 'notifications_screen.dart';

enum AuthMode { login, register, forgotPassword, resetPassword }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode _authMode = AuthMode.login;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _captchaController = TextEditingController();
  final TextEditingController _resetTokenController = TextEditingController();

  // forgotPassword modunda email'i resetPassword'a taşımak için
  String _pendingResetEmail = '';

  // Captcha
  int _num1 = 0;
  int _num2 = 0;
  int _captchaResult = 0;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _generateCaptcha();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _captchaController.dispose();
    _resetTokenController.dispose();
    super.dispose();
  }

  void _generateCaptcha() {
    setState(() {
      _num1 = (DateTime.now().millisecondsSinceEpoch % 10) + 1;
      _num2 = (DateTime.now().millisecondsSinceEpoch % 10) + 1;
      _captchaResult = _num1 + _num2;
    });
  }

  void _switchAuthMode(AuthMode mode, {String prefilledEmail = ''}) {
    setState(() {
      _authMode = mode;
      _formKey.currentState?.reset();
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _captchaController.clear();
      _resetTokenController.clear();
      if (prefilledEmail.isNotEmpty) {
        _emailController.text = prefilledEmail;
      }
      _generateCaptcha();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Captcha kontrolü (resetPassword modunda atla)
    if (_authMode != AuthMode.resetPassword) {
      if (int.tryParse(_captchaController.text) != _captchaResult) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Captcha yanlış!')));
        _generateCaptcha();
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_authMode == AuthMode.login) {
        await AuthService.login(
          _emailController.text,
          _passwordController.text,
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } else if (_authMode == AuthMode.register) {
        await AuthService.register(
          _nameController.text,
          _emailController.text,
          _passwordController.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kayıt başarılı! Şimdi giriş yapabilirsiniz.'),
          ),
        );
        _switchAuthMode(AuthMode.login);
      } else if (_authMode == AuthMode.forgotPassword) {
        await AuthService.forgotPassword(_emailController.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kod email adresinize gönderildi!'),
            duration: Duration(seconds: 3),
          ),
        );
        _pendingResetEmail = _emailController.text.trim().toLowerCase();
        _switchAuthMode(
          AuthMode.resetPassword,
          prefilledEmail: _pendingResetEmail,
        );
      } else if (_authMode == AuthMode.resetPassword) {
        await AuthService.resetPassword(
          _emailController.text,
          _resetTokenController.text,
          _passwordController.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şifreniz güncellendi! Giriş yapabilirsiniz.'),
          ),
        );
        _switchAuthMode(AuthMode.login);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getTitle() {
    switch (_authMode) {
      case AuthMode.login:
        return 'Giriş Yap';
      case AuthMode.register:
        return 'Kayıt Ol';
      case AuthMode.forgotPassword:
        return 'Şifremi Unuttum';
      case AuthMode.resetPassword:
        return 'Yeni Şifre Belirle';
    }
  }

  String _getButtonText() {
    switch (_authMode) {
      case AuthMode.login:
        return _isLoading ? 'Giriş yapılıyor...' : 'Giriş Yap';
      case AuthMode.register:
        return _isLoading ? 'Kayıt ediliyor...' : 'Kayıt Ol';
      case AuthMode.forgotPassword:
        return _isLoading ? 'Gönderiliyor...' : 'Kod Gönder';
      case AuthMode.resetPassword:
        return _isLoading ? 'Güncelleniyor...' : 'Şifreyi Güncelle';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_getTitle()), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Logo veya başlık
              const Icon(Icons.event, size: 80, color: Colors.deepPurple),
              const SizedBox(height: 10),
              Text(
                'Event Booking',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),

              // Form fields
              if (_authMode == AuthMode.register) ...[
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ad Soyad gerekli';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              // resetPassword modunda email zaten biliniyor, gösterme
              if (_authMode != AuthMode.resetPassword) ...[
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email gerekli';
                    }
                    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                    if (!emailRegex.hasMatch(value)) {
                      return 'Geçerli bir email adresi girin';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              // login ve register için şifre alanı (resetPassword'da yok, kendi bloğu var)
              if (_authMode != AuthMode.forgotPassword &&
                  _authMode != AuthMode.resetPassword) ...[
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Şifre gerekli';
                    }
                    if (_authMode == AuthMode.register && value.length < 6) {
                      return 'Şifre en az 6 karakter olmalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                if (_authMode == AuthMode.register) ...[
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Şifre Tekrar',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          );
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: _obscureConfirmPassword,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Şifre tekrar gerekli';
                      }
                      if (value != _passwordController.text) {
                        return 'Şifreler eşleşmiyor';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ],

              // ResetPassword: sadece token + yeni şifre
              if (_authMode == AuthMode.resetPassword) ...[
                TextFormField(
                  controller: _resetTokenController,
                  decoration: const InputDecoration(
                    labelText: 'Email\'e gelen 6 haneli kod',
                    prefixIcon: Icon(Icons.verified_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Kod gerekli';
                    }
                    if (value.trim().length != 6) {
                      return 'Kod 6 haneli olmalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Yeni Şifre',
                    prefixIcon: const Icon(Icons.lock_reset),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Yeni şifre gerekli';
                    }
                    if (value.length < 6) {
                      return 'Şifre en az 6 karakter olmalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Captcha (resetPassword modunda gösterme)
              if (_authMode != AuthMode.resetPassword) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Güvenlik Kodu: $_num1 + $_num2 = ?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _captchaController,
                        decoration: const InputDecoration(
                          labelText: 'Cevabı girin',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Captcha gerekli';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _generateCaptcha,
                        child: const Text('Yeni Kod'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Submit button
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _getButtonText(),
                  style: const TextStyle(fontSize: 16),
                ),
              ),

              const SizedBox(height: 16),

              // Switch mode buttons
              if (_authMode == AuthMode.login) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _switchAuthMode(AuthMode.forgotPassword),
                      child: const Text('Şifremi Unuttum'),
                    ),
                    const Text(' | '),
                    TextButton(
                      onPressed: () => _switchAuthMode(AuthMode.register),
                      child: const Text('Kayıt Ol'),
                    ),
                  ],
                ),
              ] else ...[
                Center(
                  child: TextButton(
                    onPressed: () => _switchAuthMode(AuthMode.login),
                    child: const Text('Giriş Yap'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// HomePage sınıfını buraya taşıdık (main.dart'tan)
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Event>> events;
  late Future<List<MyBooking>> _notificationBookings;
  StreamSubscription<Map<String, dynamic>>? _bookingStatusSub;
  StreamSubscription<Map<String, dynamic>>? _chatNotificationSub;
  StreamSubscription<Map<String, dynamic>>? _chatUnreadSub;
  final TextEditingController _eventSearchController = TextEditingController();
  String _eventSeatFilter = 'all';
  Map<int, int> _chatUnreadCounts = const <int, int>{};

  int get _chatUnreadTotal => _chatUnreadCounts.values.fold<int>(0, (sum, count) => sum + count);

  Future<void> _openProfilePage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _openNotificationsPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationBookings = ApiService.fetchMyBookings();
    });
  }

  Future<void> _openMyBookingsPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
    );

    if (!mounted || _isAdmin) {
      return;
    }

    _loadChatUnreadCounts();
  }

  String get _displayName {
    final name = AuthService.currentUser?.name.trim() ?? '';
    if (name.isNotEmpty) {
      return name;
    }

    return AuthService.currentUser?.email ?? 'Kullanıcı';
  }

  bool get _isAdmin => AuthService.currentUser?.role == 'admin';

  @override
  void initState() {
    super.initState();
    loadEvents();
    _notificationBookings = ApiService.fetchMyBookings();
    _bindSocketUpdates();
    if (!_isAdmin) {
      _loadChatUnreadCounts();
    }
  }

  @override
  void dispose() {
    _bookingStatusSub?.cancel();
    _chatNotificationSub?.cancel();
    _chatUnreadSub?.cancel();
    if (!_isAdmin) {
      SocketService.instance.disconnect();
    }
    _eventSearchController.dispose();
    super.dispose();
  }

  void _bindSocketUpdates() {
    if (_isAdmin) {
      return;
    }

    final email = AuthService.currentUser?.email;
    final token = AuthService.token;
    if (email == null || email.trim().isEmpty || token == null || token.trim().isEmpty) {
      return;
    }

    SocketService.instance.connectForUser(email: email, token: token);
    _bookingStatusSub?.cancel();
    _bookingStatusSub = SocketService.instance.bookingStatusUpdates.listen((_) {
      if (!mounted || _isAdmin) {
        return;
      }

      setState(() {
        _notificationBookings = ApiService.fetchMyBookings();
      });
    });

    _chatNotificationSub?.cancel();
    _chatNotificationSub = SocketService.instance.chatNotifications.listen((payload) {
      if (!mounted || _isAdmin) {
        return;
      }

      _loadChatUnreadCounts();

      if (ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      final eventTitle = (payload['eventTitle'] ?? 'Etkinlik sohbeti').toString();
      final senderName = (payload['senderName'] ?? 'Biri').toString();
      final preview = (payload['messagePreview'] ?? '').toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$eventTitle - $senderName: $preview'),
          action: SnackBarAction(
            label: 'Ac',
            onPressed: _openMyBookingsPage,
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    });

    _chatUnreadSub?.cancel();
    _chatUnreadSub = SocketService.instance.chatUnreadUpdates.listen((payload) {
      if (!mounted || _isAdmin) {
        return;
      }

      final eventId = int.tryParse('${payload['eventId'] ?? 0}') ?? 0;
      if (eventId <= 0) {
        return;
      }

      final unreadCount = int.tryParse('${payload['unreadCount'] ?? ''}');
      final unreadDelta = int.tryParse('${payload['unreadDelta'] ?? ''}') ?? 0;

      setState(() {
        final next = Map<int, int>.from(_chatUnreadCounts);
        if (unreadCount != null) {
          if (unreadCount <= 0) {
            next.remove(eventId);
          } else {
            next[eventId] = unreadCount;
          }
        } else {
          final current = next[eventId] ?? 0;
          final updated = current + unreadDelta;
          if (updated <= 0) {
            next.remove(eventId);
          } else {
            next[eventId] = updated;
          }
        }
        _chatUnreadCounts = next;
      });
    });
  }

  Future<void> _loadChatUnreadCounts() async {
    try {
      final rows = await ApiService.fetchEventChatUnreadCounts();
      if (!mounted || _isAdmin) {
        return;
      }

      setState(() {
        _chatUnreadCounts = {
          for (final row in rows)
            if (row.unreadCount > 0) row.eventId: row.unreadCount,
        };
      });
    } catch (_) {
      // Keep current counters if fetch fails.
    }
  }

  Widget _buildChatAction() {
    return IconButton(
      tooltip: 'Sohbet Odaları',
      onPressed: _openMyBookingsPage,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.forum_outlined),
          if (_chatUnreadTotal > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(999),
                ),
                constraints: const BoxConstraints(minWidth: 18),
                child: Text(
                  _chatUnreadTotal > 9 ? '9+' : '$_chatUnreadTotal',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void loadEvents() {
    events = ApiService.fetchEvents();
  }

  Future<void> refreshEvents() async {
    setState(() {
      loadEvents();
      if (!_isAdmin) {
        _notificationBookings = ApiService.fetchMyBookings();
      }
    });
  }

  Future<void> openAddPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddEditEventPage()),
    );
    if (result == true) {
      refreshEvents();
    }
  }

  Widget _buildEventsLoading() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: const [
                  _SkeletonDot(size: 44),
                  SizedBox(width: 12),
                  Expanded(child: _SkeletonBlock(height: 14)),
                ],
              ),
            ),
          ),
        ),
        ...List.generate(
          6,
          (_) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBlock(height: 16, widthFactor: 0.55),
                    SizedBox(height: 10),
                    _SkeletonBlock(height: 12, widthFactor: 0.7),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventsError(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 12),
            const Text(
              'Etkinlikler yüklenemedi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: refreshEvents,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsEmpty() {
    return RefreshIndicator(
      onRefresh: refreshEvents,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        children: const [
          Icon(Icons.event_busy, size: 72, color: Colors.deepPurple),
          SizedBox(height: 14),
          Center(
            child: Text(
              'Henüz etkinlik yok',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Sayfayı aşağı çekerek tekrar deneyebilirsin.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  List<Event> _applyEventFilters(List<Event> source) {
    final query = _eventSearchController.text.trim().toLowerCase();

    return source.where((event) {
      if (_eventSeatFilter == 'available' && event.availableSeats <= 0) {
        return false;
      }
      if (_eventSeatFilter == 'soldout' && event.availableSeats > 0) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final haystack = [
        event.title,
        event.location,
        event.eventDate,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Widget _buildEventFilterBar({
    required int totalCount,
    required int filteredCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _eventSearchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Etkinlik Ara (isim, konum, tarih)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _eventSearchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _eventSearchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _eventSeatFilter,
                decoration: const InputDecoration(
                  labelText: 'Koltuk Durumu',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Tümü')),
                  DropdownMenuItem(
                    value: 'available',
                    child: Text('Sadece Uygun Olanlar'),
                  ),
                  DropdownMenuItem(
                    value: 'soldout',
                    child: Text('Sadece Tükenenler'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _eventSeatFilter = value);
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$filteredCount / $totalCount etkinlik gösteriliyor',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<BookingNotification> _buildNotificationItems(List<MyBooking> bookings) {
    return BookingNotificationService.buildNotifications(bookings);
  }

  Widget _buildNotificationAction() {
    return FutureBuilder<List<MyBooking>>(
      future: _notificationBookings,
      builder: (context, snapshot) {
        final count = snapshot.hasData
            ? _buildNotificationItems(snapshot.data!).length
            : 0;

        return IconButton(
          tooltip: 'Bildirimler',
          onPressed: _openNotificationsPage,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUpcomingReminderSection() {
    if (_isAdmin) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<MyBooking>>(
      future: _notificationBookings,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final notifications = _buildNotificationItems(snapshot.data!);
        if (notifications.isEmpty) {
          return const SizedBox.shrink();
        }

        final next = notifications.first;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Card(
            color: Colors.amber.shade50,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.notifications_active, color: Colors.orange),
              ),
              title: Text(
                next.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(next.message),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openNotificationsPage,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Event Booking'),
            Text(
              'Hoş geldin, $_displayName',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (!_isAdmin) _buildNotificationAction(),
          IconButton(
            icon: const Icon(Icons.manage_accounts),
            tooltip: 'Profilim',
            onPressed: _openProfilePage,
          ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Rezervasyon Yönetimi',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminBookingsScreen(),
                  ),
                );
              },
            ),
          if (!_isAdmin)
            _buildChatAction(),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.forum_outlined),
              tooltip: 'Sohbet Odaları',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              SocketService.instance.disconnect();
              await AuthService.logout();
              if (!context.mounted) {
                return;
              }

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const AuthScreen()),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Event>>(
        future: events,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildEventsLoading();
          } else if (snapshot.hasError) {
            return _buildEventsError(snapshot.error);
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildEventsEmpty();
          } else {
            final items = snapshot.data!;
            final filteredItems = _applyEventFilters(items);
            return RefreshIndicator(
              onRefresh: refreshEvents,
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            title: Text(_displayName),
                            subtitle: Text(
                              AuthService.currentUser?.email ?? '',
                            ),
                            trailing: Chip(
                              label: Text(
                                AuthService.currentUser?.role ?? 'user',
                              ),
                            ),
                            onTap: _openProfilePage,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Icon(
                              _isAdmin
                                  ? Icons.forum_outlined
                                  : Icons.receipt_long,
                              color: Colors.deepPurple,
                            ),
                            title: Text(
                              _isAdmin ? 'Sohbet Odaları' : 'Rezervasyonlarım',
                            ),
                            subtitle: Text(
                              _isAdmin
                                  ? 'Etkinlik sohbet odalarına eriş'
                                  : 'Geçmiş rezervasyonlarını görüntüle',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MyBookingsScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildUpcomingReminderSection(),
                  _buildEventFilterBar(
                    totalCount: items.length,
                    filteredCount: filteredItems.length,
                  ),
                  if (filteredItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.filter_alt_off,
                                size: 48,
                                color: Colors.deepPurple,
                              ),
                              const SizedBox(height: 8),
                              const Text('Filtreye uygun etkinlik bulunamadı.'),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _eventSeatFilter = 'all';
                                    _eventSearchController.clear();
                                  });
                                },
                                child: const Text('Filtreleri Temizle'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ...filteredItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final event = entry.value;

                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 240 + (index * 70)),
                      curve: Curves.easeOutCubic,
                      tween: Tween(begin: 0, end: 1),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 14),
                            child: child,
                          ),
                        );
                      },
                      child: Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.event,
                            color: Colors.deepPurple,
                          ),
                          title: Text(
                            event.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${event.eventDate.length >= 10 ? event.eventDate.substring(0, 10) : event.eventDate}  •  ${event.location}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₤${event.price}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                              if (_isAdmin)
                                Text(
                                  'Düzenle',
                                  style: TextStyle(
                                    color: Colors.green[600],
                                    fontSize: 11,
                                  ),
                                ),
                              if (!_isAdmin)
                                Text(
                                  event.availableSeats > 0
                                      ? 'Rezerve Et'
                                      : 'Tükendi',
                                  style: TextStyle(
                                    color: event.availableSeats > 0
                                        ? Colors.deepPurple[400]
                                        : Colors.red,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                          onTap: _isAdmin
                              ? () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AddEditEventPage(event: event),
                                    ),
                                  );
                                  if (result == true) refreshEvents();
                                }
                              : event.availableSeats > 0
                              ? () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BookingScreen(event: event),
                                    ),
                                  );
                                  if (result == true) refreshEvents();
                                }
                              : null,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }
        },
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              onPressed: openAddPage,
              tooltip: 'Etkinlik Ekle',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _SkeletonBlock extends StatefulWidget {
  final double height;
  final double? widthFactor;

  const _SkeletonBlock({required this.height, this.widthFactor});

  @override
  State<_SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<_SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.35,
      upperBound: 0.9,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.widthFactor != null
        ? MediaQuery.of(context).size.width * widget.widthFactor!
        : double.infinity;

    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _SkeletonDot extends StatelessWidget {
  final double size;

  const _SkeletonDot({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
    );
  }
}
