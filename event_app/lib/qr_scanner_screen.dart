import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'models/qr_ticket.dart';
import 'services/api_service.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isHandling = false;
  String? _lastValue;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleQr(String qrToken) async {
    if (_isHandling || qrToken.isEmpty) {
      return;
    }

    setState(() {
      _isHandling = true;
      _lastValue = qrToken;
    });

    try {
      final result = await ApiService.verifyQrTicket(qrToken);
      if (!mounted) {
        return;
      }
      await _showResult(
        title: 'Giriş Onaylandı',
        color: Colors.green,
        ticket: result,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Doğrulama Hatası'),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isHandling = false;
        });
      }
    }
  }

  Future<void> _showResult({
    required String title,
    required Color color,
    required QrTicket ticket,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ticket.eventTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Katılımcı: ${ticket.customerName}'),
              Text('Email: ${ticket.customerEmail}'),
              Text('Bilet: ${ticket.ticketCount}'),
              Text('Durum: ${ticket.status}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Kapat', style: TextStyle(color: color)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR Tarayıcı')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final barcode = capture.barcodes.isNotEmpty
                  ? capture.barcodes.first.rawValue ?? ''
                  : '';
              _handleQr(barcode);
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black.withValues(alpha: 0.6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isHandling
                        ? 'Doğrulanıyor...'
                        : 'Bilet QR kodunu kameraya göster.',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  if (_lastValue != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _lastValue!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}