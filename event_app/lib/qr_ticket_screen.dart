import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'models/qr_ticket.dart';
import 'services/api_service.dart';

class QrTicketScreen extends StatefulWidget {
  final int bookingId;

  const QrTicketScreen({super.key, required this.bookingId});

  @override
  State<QrTicketScreen> createState() => _QrTicketScreenState();
}

class _QrTicketScreenState extends State<QrTicketScreen> {
  late Future<QrTicket> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchMyQrTicket(widget.bookingId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = ApiService.fetchMyQrTicket(widget.bookingId);
    });
  }

  String _formatDate(String raw) {
    if (raw.length >= 10) {
      return raw.substring(0, 10);
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR Biletim')),
      body: FutureBuilder<QrTicket>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.qr_code_2, size: 64, color: Colors.deepPurple),
                    const SizedBox(height: 12),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            );
          }

          final ticket = snapshot.data!;

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        QrImageView(
                          data: ticket.qrToken,
                          version: QrVersions.auto,
                          size: 240,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          ticket.eventTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Tarih: ${_formatDate(ticket.eventDate)}'),
                        Text('Konum: ${ticket.eventLocation}'),
                        Text('Bilet: ${ticket.ticketCount}'),
                        Text('Ödeme: ${ticket.paymentStatus}'),
                        Text('Durum: ${ticket.status}'),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ticket.checkedIn
                                ? Colors.green.shade50
                                : Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            ticket.checkedIn
                                ? 'Bu bilet kullanıldı.'
                                : 'Girişte bu QR kodu görevliye okut.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ticket.checkedIn
                                  ? Colors.green.shade800
                                  : Colors.deepPurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}