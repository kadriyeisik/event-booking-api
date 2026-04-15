import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/event.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/fake_payment_service.dart';

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
  final TextEditingController _cardHolderController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();

  bool _isLoading = false;
  bool _obscureCvv = true;

  @override
  void initState() {
    super.initState();
    // Giriş yapan kullanıcının bilgilerini önceden doldur
    final user = AuthService.currentUser;
    if (user != null) {
      _nameController.text = user.name;
      _emailController.text = user.email;
      _cardHolderController.text = user.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _ticketCountController.dispose();
    _cardHolderController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
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
      FakePaymentResult? paymentResult;
      if (_requiresPayment) {
        paymentResult = await FakePaymentService.processCardPayment(
          cardHolder: _cardHolderController.text,
          cardNumber: _cardNumberController.text,
          expiry: _expiryController.text,
          cvv: _cvvController.text,
          amount: _totalPrice,
        );
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
              Text(
                _requiresPayment
                    ? 'Odeme: ${paymentResult?.maskedCard ?? ''}'
                    : 'Odeme: Ucretsiz rezervasyon',
              ),
              if (_requiresPayment) ...[
                const SizedBox(height: 4),
                Text('Referans: ${paymentResult?.reference ?? '-'}'),
              ],
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
                                  ? 'Checkout'
                                  : 'Ucretsiz Rezervasyon',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _requiresPayment
                                  ? 'Rezervasyon odemesi uygulama icinde simule edilir. Test karti olarak 4242 4242 4242 4242 kullanabilirsin.'
                                  : 'Bu etkinlik ucretsiz oldugu icin odeme adimi atlanacak.',
                            ),
                            if (_requiresPayment) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Basarisiz test karti: 4000 0000 0000 0000',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_requiresPayment) ...[
                      Text(
                        'Odeme Bilgileri',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _cardHolderController,
                        decoration: const InputDecoration(
                          labelText: 'Kart Uzerindeki Isim',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (!_requiresPayment) {
                            return null;
                          }
                          if (value == null || value.trim().isEmpty) {
                            return 'Kart uzerindeki isim gerekli';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _cardNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Kart Numarasi',
                          prefixIcon: Icon(Icons.credit_card),
                          border: OutlineInputBorder(),
                          hintText: '4242 4242 4242 4242',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                          LengthLimitingTextInputFormatter(19),
                        ],
                        validator: (value) {
                          if (!_requiresPayment) {
                            return null;
                          }
                          final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
                          if (digits.length != 16) {
                            return 'Kart numarasi 16 haneli olmali';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _expiryController,
                              decoration: const InputDecoration(
                                labelText: 'Son Kullanma',
                                prefixIcon: Icon(Icons.date_range_outlined),
                                border: OutlineInputBorder(),
                                hintText: 'AA/YY',
                              ),
                              keyboardType: TextInputType.datetime,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                                LengthLimitingTextInputFormatter(5),
                              ],
                              validator: (value) {
                                if (!_requiresPayment) {
                                  return null;
                                }
                                if (value == null ||
                                    !RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').hasMatch(value.trim())) {
                                  return 'AA/YY';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _cvvController,
                              decoration: InputDecoration(
                                labelText: 'CVV',
                                prefixIcon: const Icon(Icons.lock_outline),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureCvv ? Icons.visibility : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() => _obscureCvv = !_obscureCvv);
                                  },
                                ),
                              ),
                              obscureText: _obscureCvv,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              validator: (value) {
                                if (!_requiresPayment) {
                                  return null;
                                }
                                if (value == null || value.trim().length != 3) {
                                  return '3 hane';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

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
                              ? 'Odeme aliniyor ve rezervasyon olusturuluyor...'
                              : 'Rezervasyon yapiliyor...')
                            : (_requiresPayment
                              ? 'Odemeyi Simule Et ve Rezerve Et'
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
