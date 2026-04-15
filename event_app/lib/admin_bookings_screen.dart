import 'package:flutter/material.dart';

import 'models/admin_booking.dart';
import 'services/api_service.dart';
import 'services/csv_export_service.dart';

class AdminBookingsScreen extends StatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  State<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends State<AdminBookingsScreen> {
  late Future<List<AdminBooking>> _future;
  int? _updatingId;
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';
  String _dateSort = 'newest';
  List<AdminBooking> _latestFilteredItems = const [];

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Onaylı';
      case 'cancelled':
        return 'İptal';
      default:
        return 'Beklemede';
    }
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'approved':
        return Colors.green.shade100;
      case 'cancelled':
        return Colors.red.shade100;
      default:
        return Theme.of(context).colorScheme.secondaryContainer;
    }
  }

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchAllBookings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _future = ApiService.fetchAllBookings();
    });
  }

  Future<void> _exportFilteredBookings() async {
    if (_latestFilteredItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışa aktarılacak kayıt bulunamadı.')),
      );
      return;
    }

    try {
      await CsvExportService.shareCsv(
        filenamePrefix: 'admin-bookings',
        headers: const [
          'ID',
          'Etkinlik',
          'Musteri',
          'Email',
          'Konum',
          'Etkinlik Tarihi',
          'Kayit Tarihi',
          'Bilet',
          'Durum',
          'Toplam',
        ],
        rows: _latestFilteredItems
            .map(
              (booking) => [
                booking.id.toString(),
                booking.eventTitle,
                booking.customerName,
                booking.customerEmail,
                booking.eventLocation,
                _formatDate(booking.eventDate),
                _formatDate(booking.createdAt),
                booking.ticketCount.toString(),
                booking.status,
                booking.totalPrice.toStringAsFixed(2),
              ],
            )
            .toList(),
        shareText: 'Filtrelenmis admin rezervasyon listesi CSV dosyasi',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV dışa aktarma başarısız: $e')));
    }
  }

  Future<bool> _confirmStatusChange(
    AdminBooking booking,
    String nextStatus,
  ) async {
    final actionText = nextStatus == 'approved' ? 'onaylamak' : 'iptal etmek';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('İşlemi Onayla'),
          content: Text(
            '"${booking.eventTitle}" etkinliği için ${booking.customerName} rezervasyonunu $actionText istiyor musun?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Evet'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _undoStatusChange({
    required int bookingId,
    required String previousStatus,
  }) async {
    try {
      await ApiService.updateBookingStatus(
        bookingId: bookingId,
        status: previousStatus,
      );
      if (!mounted) {
        return;
      }
      await _reload();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşlem geri alındı.')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Geri alma başarısız: $e')));
    }
  }

  List<AdminBooking> _applyFilters(List<AdminBooking> items) {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = items.where((booking) {
      final statusMatch =
          _statusFilter == 'all' || booking.status == _statusFilter;

      if (!statusMatch) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final haystack = [
        booking.customerName,
        booking.customerEmail,
        booking.eventTitle,
        booking.eventLocation,
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final dateA = DateTime.tryParse(a.createdAt);
      final dateB = DateTime.tryParse(b.createdAt);

      if (dateA == null || dateB == null) {
        return _dateSort == 'newest'
            ? b.id.compareTo(a.id)
            : a.id.compareTo(b.id);
      }

      return _dateSort == 'newest'
          ? dateB.compareTo(dateA)
          : dateA.compareTo(dateB);
    });

    return filtered;
  }

  Future<void> _setStatus(AdminBooking booking, String status) async {
    final confirmed = await _confirmStatusChange(booking, status);
    if (!confirmed) {
      return;
    }

    final previousStatus = booking.status;
    setState(() => _updatingId = booking.id);
    try {
      await ApiService.updateBookingStatus(
        bookingId: booking.id,
        status: status,
      );
      if (!mounted) {
        return;
      }
      await _reload();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rezervasyon ${status == 'approved' ? 'onaylandı' : 'iptal edildi'}',
          ),
          action: SnackBarAction(
            label: 'Geri Al',
            onPressed: () {
              _undoStatusChange(
                bookingId: booking.id,
                previousStatus: previousStatus,
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) {
        setState(() => _updatingId = null);
      }
    }
  }

  String _formatDate(String raw) {
    if (raw.length >= 10) {
      return raw.substring(0, 10);
    }
    return raw;
  }

  Widget _buildToolbar({required int totalCount, required int filteredCount}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 430;

              final filterFields = [
                DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Durum Filtresi',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Tümü')),
                    DropdownMenuItem(value: 'pending', child: Text('Beklemede')),
                    DropdownMenuItem(value: 'approved', child: Text('Onaylı')),
                    DropdownMenuItem(value: 'cancelled', child: Text('İptal')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _statusFilter = value);
                  },
                ),
                DropdownButtonFormField<String>(
                  value: _dateSort,
                  decoration: const InputDecoration(
                    labelText: 'Tarih Sırası',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('Yeniden Eskiye'),
                    ),
                    DropdownMenuItem(
                      value: 'oldest',
                      child: Text('Eskiden Yeniye'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _dateSort = value);
                  },
                ),
              ];

              return Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Ara (ad, email, etkinlik, konum)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (isCompact) ...[
                    filterFields[0],
                    const SizedBox(height: 10),
                    filterFields[1],
                  ] else
                    Row(
                      children: [
                        Expanded(child: filterFields[0]),
                        const SizedBox(width: 10),
                        Expanded(child: filterFields[1]),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$filteredCount / $totalCount kayıt gösteriliyor',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezervasyon Yönetimi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Filtrelenmiş CSV Dışa Aktar',
            onPressed: _exportFilteredBookings,
          ),
        ],
      ),
      body: FutureBuilder<List<AdminBooking>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Hata: ${snapshot.error}'),
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

          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 160),
                  Icon(
                    Icons.inbox_outlined,
                    size: 64,
                    color: Colors.deepPurple,
                  ),
                  SizedBox(height: 12),
                  Center(child: Text('Henüz rezervasyon yok.')),
                ],
              ),
            );
          }

          final filteredItems = _applyFilters(items);
          _latestFilteredItems = filteredItems;

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: filteredItems.isEmpty ? 2 : filteredItems.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildToolbar(
                    totalCount: items.length,
                    filteredCount: filteredItems.length,
                  );
                }

                if (filteredItems.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.filter_alt_off,
                          size: 56,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(height: 10),
                        const Text('Filtreye uygun rezervasyon bulunamadı.'),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _statusFilter = 'all';
                              _searchController.clear();
                            });
                          },
                          child: const Text('Filtreleri Temizle'),
                        ),
                      ],
                    ),
                  );
                }

                final booking = filteredItems[index - 1];
                final busy = _updatingId == booking.id;
                final isApproved = booking.status == 'approved';
                final isCancelled = booking.status == 'cancelled';

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.confirmation_number,
                              color: Colors.deepPurple,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                booking.eventTitle,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Chip(
                              label: Text(_statusLabel(booking.status)),
                              backgroundColor: _statusColor(
                                context,
                                booking.status,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${booking.customerName} • ${booking.customerEmail}',
                        ),
                        Text(
                          'Tarih: ${_formatDate(booking.eventDate)}  •  ${booking.eventLocation}',
                        ),
                        Text(
                          'Bilet: ${booking.ticketCount}  •  Toplam: ₤${booking.totalPrice.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: busy || isApproved
                                    ? null
                                    : () => _setStatus(booking, 'approved'),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Onayla'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: busy || isCancelled
                                    ? null
                                    : () => _setStatus(booking, 'cancelled'),
                                icon: busy
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.cancel_outlined),
                                label: const Text('İptal Et'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
