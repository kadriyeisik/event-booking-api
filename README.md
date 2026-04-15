# Event Booking Platform

Bu depo iki ana parçadan oluşur:

- Node.js + Express tabanlı backend API
- Flutter tabanlı mobil istemci

## Özellikler

- Kayıt ol, giriş yap, şifre sıfırla
- JWT tabanlı yetkilendirme
- Kalıcı oturum yönetimi
- Etkinlik listeleme, oluşturma, düzenleme, silme
- Kullanıcı rezervasyonu oluşturma ve rezervasyon geçmişi görüntüleme
- Sahte ödeme / checkout simülasyonu
- Profil güncelleme ve şifre değiştirme
- Admin rezervasyon yönetimi
- Arama, filtreleme, sıralama ve CSV export
- Cron tabanlı hatırlatma ve süresi geçen etkinlik işlemleri

## Klasör Yapısı

- `src/`: Express API, controller, route, middleware ve servisler
- `event_app/`: Flutter mobil uygulaması
- `test/`: Backend testleri

## Backend Çalıştırma

```bash
cd event-booking-api
npm install
npm start
```

Varsayılan adres:

- `http://localhost:3000`

## Flutter Çalıştırma

```bash
cd event_app
flutter pub get
flutter run
```

Android emulator için backend adresi uygulamada `10.0.2.2:3000` olarak kullanılır.

## Test Komutları

Backend:

```bash
npm test
```

Flutter:

```bash
cd event_app
flutter test
flutter analyze
```

## Demo Hesap

- Admin email: `admin@test.com`
- Admin şifre: `123456`

## Notlar

- Şifre sıfırlama email tabanlı 6 haneli kod ile çalışır.
- Admin rezervasyon yönetimi ekranında onay, iptal ve geri alma akışı bulunur.
- CSV export kullanıcı ve admin ekranlarında paylaşım sayfası üzerinden çalışır.
- Ucretli etkinliklerde sahte checkout akışı bulunur. `4242 4242 4242 4242` basarili, `4000 0000 0000 0000` basarisiz test kartıdır.