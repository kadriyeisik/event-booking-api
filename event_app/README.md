# Event App

Flutter istemcisi, Node.js tabanlı Event Booking API ile konuşur ve kullanıcı ile admin için ayrı akışlar sunar.

## Öne Çıkan Özellikler

- Giriş yap, kayıt ol, şifremi unuttum, token ile şifre sıfırla
- SharedPreferences ile kalıcı oturum
- Kullanıcı tarafında etkinlik listeleme, arama ve koltuk durumuna göre filtreleme
- Etkinlik rezervasyonu oluşturma
- Ucretli etkinliklerde sahte odeme / checkout simülasyonu
- Rezervasyonlarım ekranı
- Profil güncelleme ve şifre değiştirme
- Admin tarafında rezervasyon yönetimi
- Admin rezervasyon ekranında arama, durum filtresi, tarih sıralaması, onay, iptal ve undo
- Kullanıcı ve admin ekranlarında CSV dışa aktarma

## Gereksinimler

- Flutter SDK 3.8+
- Çalışan backend API: http://10.0.2.2:3000
- Android emulator veya fiziksel cihaz

## Çalıştırma

1. Backend sunucusunu başlat:

```bash
cd event-booking-api
npm start
```

2. Flutter bağımlılıklarını yükle:

```bash
cd event_app
flutter pub get
```

3. Uygulamayı çalıştır:

```bash
flutter run
```

## Demo Hesaplar

- Admin:
	- Email: admin@test.com
	- Şifre: 123456

- Normal kullanıcı:
	- Uygulama içinden kayıt ol ekranıyla oluşturulabilir

## CSV Export

- Kullanıcı tarafında Rezervasyonlarım ekranından tüm mevcut kayıtlar CSV olarak paylaşılabilir.
- Admin tarafında Rezervasyon Yönetimi ekranından filtrelenmiş kayıtlar CSV olarak paylaşılabilir.

## Sahte Checkout

- Ucretli etkinliklerde kart bilgisi alan bir checkout adımı gösterilir.
- Basarili test kartı: `4242 4242 4242 4242`
- Basarisiz test kartı: `4000 0000 0000 0000`
- Ucretsiz etkinliklerde odeme adımı atlanır.

## Notlar

- Android emulator için backend adresi 10.0.2.2 kullanılır.
- Token süresi dolarsa uygulama ilgili korumalı işlemlerde oturumu kapatır.
- Şifre sıfırlama akışı email ile gelen 6 haneli kod üzerinden çalışır.
