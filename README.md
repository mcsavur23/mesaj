# Mesaj — Anonim ve Uçtan Uca Şifreli Hibrit Mesajlaşma Uygulaması

> **Telefon numarası yok. E-posta yok. Kayıt yok. Tamamen anonim.**

---

## Özellikler

| Özellik | Detay |
|---|---|
| 🔐 **Kimlik** | Rastgele Ed25519 kriptografik anahtar çifti (cihaza özgü) |
| 🤝 **Arkadaş Ekleme** | Yalnızca QR kod kamera ile okutarak |
| 🌐 **İnternet Varsa** | WebSocket Relay (RAM-only, sıfır veritabanı) |
| 📶 **İnternet Yoksa** | Bluetooth LE — Doğrudan cihazdan cihaza (P2P) |
| 🔒 **Şifreleme** | X25519 ECDH + ChaCha20-Poly1305 AEAD + Ed25519 İmza |
| ♻️ **İleri Gizlilik** | Her mesaj için Ephemeral Anahtar (Perfect Forward Secrecy) |
| 🛡️ **Replay Koruması** | ±5 dakika zaman penceresi + imza doğrulama |

---

## Proje Yapısı

```
lib/
├── core/
│   ├── crypto/
│   │   ├── crypto_service.dart         # X25519, Ed25519, ChaCha20-Poly1305
│   │   └── key_pair_bundle.dart        # Anahtar sarmalayıcı sınıflar
│   ├── protocol/
│   │   ├── encrypted_envelope.dart     # Şifreli zarf + EnvelopeBuilder
│   │   └── qr_payload.dart             # QR kod eşleşme protokolü
│   └── storage/
│       ├── identity_storage.dart       # Güvenli anahtar saklama
│       └── contact_repository.dart     # SQLite rehber
├── transport/
│   ├── transport_interface.dart        # Ortak taşıyıcı arayüzü
│   ├── websocket_transport.dart        # WebSocket Relay istemcisi
│   ├── bluetooth_p2p_transport.dart    # BLE P2P taşıyıcı
│   └── hybrid_router.dart              # Otomatik taşıyıcı seçici
├── models/
│   ├── message.dart                    # Yerel mesaj modeli
│   └── peer_contact.dart               # Arkadaş veri modeli
├── ui/
│   ├── theme/app_theme.dart            # OLED Neon tema
│   └── screens/
│       ├── home_screen.dart            # Sohbet listesi + nav
│       ├── qr_display_screen.dart      # Kendi QR kodunu göster
│       └── qr_scanner_screen.dart      # Arkadaş QR tara
└── main.dart
server/
└── relay_server.dart                   # RAM-only WebSocket sunucusu
test/
└── crypto_service_test.dart            # Kriptografi birim testleri
```

---

## Şifreleme Protokolü

```
GÖNDERME (Alice → Bob):
  1. Ephemeral X25519 keypair üret (PFS)
  2. ECDH: ephemeral_private × bob_public → shared_secret
  3. HKDF-SHA256: shared_secret → session_key (32 byte)
  4. ChaCha20-Poly1305: encrypt(message, session_key, random_nonce)
  5. Ed25519: sign(envelope_payload, alice_private)
  6. Zarfı gönder: {ephemeral_public, nonce, ciphertext, signature}

ALMA (Bob):
  1. Zaman penceresi kontrolü (±5 dk) → Replay attack koruması
  2. Ed25519: verify(signature, alice_public) → Kimlik doğrulama
  3. ECDH: bob_private × ephemeral_public → shared_secret
  4. HKDF-SHA256: shared_secret → session_key
  5. ChaCha20-Poly1305: decrypt(ciphertext, session_key) → mesaj
```

---

## Kurulum ve Çalıştırma

### Gereksinimler
- Flutter SDK 3.3+
- Android SDK (Android cihaz için) / Xcode (iOS için)

### Kurulum

```bash
cd "c:\Users\EVREN\Saved Games\PROJELERİM\Mesaj"
flutter pub get
```

### Android İzinleri (android/app/src/main/AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
```

### iOS İzinleri (ios/Runner/Info.plist)

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Yakındaki arkadaşlarla şifreli mesajlaşmak için Bluetooth gereklidir.</string>
<key>NSCameraUsageDescription</key>
<string>Arkadaş eklemek için QR kod taramak gereklidir.</string>
```

### Uygulamayı Başlat

```bash
flutter run
```

### Relay Sunucusunu Başlat

```bash
dart run server/relay_server.dart
# PORT=8765 dart run server/relay_server.dart
```

### Testleri Çalıştır

```bash
flutter test test/crypto_service_test.dart
```

---

## Güvenlik Notu

- **Sunucu sıfır veri tutar**: Relay sunucu yalnızca RAM üzerinde çalışır, şifreli paketi alıcıya anında iletir ve hafızasından siler.
- **Sunucu içeriği okuyamaz**: Sunucu şifreleme/çözme anahtarına sahip değildir.
- **Özel anahtarlar cihazda**: iOS Keychain / Android Keystore'da saklanır.
- **Perfect Forward Secrecy**: Her mesaj için yeni ephemeral anahtar çifti kullanılır; bir oturum anahtarı ele geçirilse bile geçmiş mesajlar açılamaz.

---

## Yapılacaklar (Sonraki Adımlar)

- [ ] **Aşama 3**: Riverpod state yönetimi ve tam ChatScreen UI
- [ ] **Aşama 4**: Android BLE Peripheral modu (Kotlin MethodChannel)
- [ ] **Aşama 5**: iOS CBPeripheralManager (Swift MethodChannel)
- [ ] **Aşama 6**: Mesaj geçmişi için yerel SQLite şifrelemesi (SQLCipher)
- [ ] **Aşama 7**: Relay sunucusu için Docker ve TLS/HTTPS
