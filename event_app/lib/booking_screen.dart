import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/event.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';

class BookingScreen extends StatefulWidget {
  final Event event;

  const BookingScreen({super.key, required this.event});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _ticketCountController = TextEditingController(
    text: '1',
  );

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Giriş yapan kullanıcının bilgilerini önceden doldur
    final user = AuthService.currentUser;
    if (user != null) {
      _nameController.text = user.name;
      _emailController.text = user.email;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _ticketCountController.dispose();
    super.dispose();
  }

  int get _availableSeats => widget.event.availableSeats;
  int get _ticketCount => int.tryParse(_ticketCountController.text) ?? 1;
  double get _unitPrice => double.tryParse(widget.event.price) ?? 0;
  double get _totalPrice => _unitPrice * _ticketCount;
  bool get _requiresPayment => _totalPrice > 0;

  Future<void> _book() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_requiresPayment) {
        if (!AuthService.isLoggedIn) {
          throw Exception('Ücretli etkinlikler için önce giriş yapmalısın.');
        }

        final session = await ApiService.createCheckoutSession(
          eventId: widget.event.id,
          ticketCount: _ticketCount,
        );

        final uri = Uri.tryParse(session.checkoutUrl);
        if (uri == null) {
          throw Exception('Geçersiz checkout bağlantısı döndü.');
        }

        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (!launched) {
          throw Exception('Stripe ödeme sayfası açılamadı.');
        }

        if (!mounted) {
          return;
        }

        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.open_in_browser, color: Colors.deepPurple, size: 56),
            title: const Text('Ödeme Sayfası Açıldı'),
            content: const Text(
              'Stripe ödeme sayfası tarayıcıda açıldı. Ödemeyi tamamladıktan sonra uygulamaya dönüp Rezervasyonlarım ekranından durumunu ve QR biletini kontrol edebilirsin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );

        return;
      }

      await ApiService.bookEvent(
        eventId: widget.event.id,
        customerName: _nameController.text,
        customerEmail: _emailController.text,
        ticketCount: _ticketCount,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 56),
          title: const Text('Rezervasyon Başarılı!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Etkinlik: ${widget.event.title}'),
              const SizedBox(height: 4),
              Text('Bilet: $_ticketCount adet'),
              const SizedBox(height: 4),
              Text('Email: ${_emailController.text}'),
              const SizedBox(height: 4),
              const Text('Odeme: Ucretsiz rezervasyon'),
              const SizedBox(height: 12),
              const Text(
                'Rezervasyon bilgileri email adresinize gönderilecektir.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // dialog
                Navigator.of(context).pop(true); // screen → refresh
              },
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red[700]),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final isSoldOut = _availableSeats <= 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Etkinlik Rezervasyonu'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Etkinlik özet kartı
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event, color: Colors.deepPurple),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _infoRow(Icons.location_on, event.location),
                    const SizedBox(height: 6),
                    _infoRow(
                      Icons.calendar_today,
                      event.eventDate.length >= 10
                          ? event.eventDate.substring(0, 10)
                          : event.eventDate,
                    ),
                    const SizedBox(height: 6),
                    _infoRow(Icons.attach_money, '₺${event.price} / bilet'),
                    const SizedBox(height: 6),
                    _infoRow(
                      Icons.chair_outlined,
                      '$_availableSeats koltuk mevcut',
                      color: _availableSeats < 10
                          ? Colors.orange
                          : Colors.green,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            if (isSoldOut)
              const Center(
                child: Chip(
                  label: Text(
                    'TÜKENDI',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: Colors.red,
                ),
              )
            else
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Rezervasyon Bilgileri',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Ad Soyad',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Ad Soyad gerekli'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Email gerekli';
                        }
                        final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                        if (!re.hasMatch(v)) {
                          return 'Geçerli bir email girin';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _ticketCountController,
                      decoration: const InputDecoration(
                        labelText: 'Bilet Sayısı',
                        prefixIcon: Icon(Icons.confirmation_number),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n <= 0) {
                          return 'Geçerli bir sayı girin';
                        }
                        if (n > _availableSeats) {
                          return 'En fazla $_availableSeats bilet alabilirsiniz';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),

                    // Toplam fiyat
                    if (_ticketCount > 0) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Toplam: ₺${(double.tryParse(event.price) ?? 0) * _ticketCount}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    Card(
                      color: Colors.deepPurple.withValues(alpha: 0.05),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _requiresPayment
                                  ? 'Stripe Checkout'
                                  : 'Ucretsiz Rezervasyon',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _requiresPayment
                                  ? 'Odeme tarayicida acilan guvenli Stripe Checkout sayfasinda tamamlanir. Odeme tamamlandiginda rezervasyonun onaylanir ve QR biletin olusur.'
                                  : 'Bu etkinlik ucretsiz oldugu icin odeme adimi atlanacak.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _book,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.book_online),
                      label: Text(
                        _isLoading
                            ? (_requiresPayment
                              ? 'Stripe odeme sayfasi hazirlaniyor...'
                              : 'Rezervasyon yapiliyor...')
                            : (_requiresPayment
                              ? 'Stripe ile Ode ve Rezerve Et'
                              : 'Ucretsiz Rezervasyonu Onayla'),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(color: color ?? Colors.grey[800])),
        ),
      ],
    );
  }
}
