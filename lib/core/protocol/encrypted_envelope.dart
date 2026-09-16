import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../crypto/crypto_service.dart';

/// Ağ üzerinden iletilen şifreli mesaj zarfı.
///
/// Bu zarfın içeriği sadece alıcı cihaz tarafından çözülebilir.
/// Relay sunucusu bile içeriği okuyamaz.
///
/// Protokol formatı (JSON):
/// ```json
/// {
///   "v": 1,
///   "sid": "...",
///   "rid": "...",
///   "epk": "base64url",
///   "nonce": "base64url",
///   "ct": "base64url",
///   "sig": "base64url",
///   "ts": 1234567890
/// }
/// ```
class EncryptedEnvelope {
  /// Protokol versiyonu
  final int version;

  /// Gönderici Peer ID (UUID)
  final String senderId;

  /// Alıcı Peer ID (UUID)
  final String recipientId;

  /// Ephemeral X25519 Açık Anahtar (Perfect Forward Secrecy için)
  /// Her mesaj için yeni bir anahtar çifti üretilir.
  final Uint8List ephemeralPublicKey;

  /// ChaCha20-Poly1305 Nonce (12 byte, şifreli metnin içinde zaten var,
  /// ancak zarf seviyesinde de saklanır).
  final Uint8List nonce;

  /// Şifreli metin (ciphertext + Poly1305 MAC)
  final Uint8List ciphertext;

  /// Ed25519 İmzası — zarfın bütününü doğrular
  final Uint8List signature;

  /// Unix timestamp (milliseconds) — replay attack koruması için
  final int timestamp;

  const EncryptedEnvelope({
    required this.version,
    required this.senderId,
    required this.recipientId,
    required this.ephemeralPublicKey,
    required this.nonce,
    required this.ciphertext,
    required this.signature,
    required this.timestamp,
  });

  // -----------------------------------------------------------------------
  // JSON Serileştirme
  // -----------------------------------------------------------------------

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) {
    return EncryptedEnvelope(
      version: json['v'] as int,
      senderId: json['sid'] as String,
      recipientId: json['rid'] as String,
      ephemeralPublicKey: CryptoService.fromBase64(json['epk'] as String),
      nonce: CryptoService.fromBase64(json['nonce'] as String),
      ciphertext: CryptoService.fromBase64(json['ct'] as String),
      signature: CryptoService.fromBase64(json['sig'] as String),
      timestamp: json['ts'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'sid': senderId,
        'rid': recipientId,
        'epk': CryptoService.toBase64(ephemeralPublicKey),
        'nonce': CryptoService.toBase64(nonce),
        'ct': CryptoService.toBase64(ciphertext),
        'sig': CryptoService.toBase64(signature),
        'ts': timestamp,
      };

  String toJsonString() => jsonEncode(toJson());

  factory EncryptedEnvelope.fromJsonString(String raw) =>
      EncryptedEnvelope.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  // -----------------------------------------------------------------------
  // İmzalanacak Payload (İmza dahil olmadan tüm alanlar)
  // -----------------------------------------------------------------------

  /// İmza doğrulaması ve oluşturması için kullanılan canonical byte payload.
  Uint8List get signingPayload {
    final map = {
      'v': version,
      'sid': senderId,
      'rid': recipientId,
      'epk': CryptoService.toBase64(ephemeralPublicKey),
      'nonce': CryptoService.toBase64(nonce),
      'ct': CryptoService.toBase64(ciphertext),
      'ts': timestamp,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  // -----------------------------------------------------------------------
  // Zaman Penceresi Kontrolü (Replay Attack Koruması)
  // -----------------------------------------------------------------------

  /// Zarfın geçerli zaman penceresinde olup olmadığını kontrol eder.
  /// Varsayılan: ±5 dakika
  bool isWithinTimeWindow({Duration window = const Duration(minutes: 5)}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = (now - timestamp).abs();
    return diff <= window.inMilliseconds;
  }

  @override
  String toString() =>
      'EncryptedEnvelope(v: $version, sid: $senderId, rid: $recipientId, ts: $timestamp)';
}

// ---------------------------------------------------------------------------
// Zarf Oluşturma ve Çözme Yardımcısı
// ---------------------------------------------------------------------------

/// [EncryptedEnvelope] oluşturma ve çözme işlemlerini koordine eden yardımcı sınıf.
class EnvelopeBuilder {
  /// Düz metin mesajı şifreler, imzalar ve bir [EncryptedEnvelope] döner.
  ///
  /// [plaintext]: Gönderilecek UTF-8 mesaj.
  /// [senderPrivateKeyBytes]: Gönderici Ed25519 özel anahtarı (imzalama için).
  /// [senderPublicKeyBytes]: Gönderici Ed25519 açık anahtarı.
  /// [senderId]: Gönderici Peer ID.
  /// [recipientId]: Alıcı Peer ID.
  /// [recipientX25519PublicKeyBytes]: Alıcının X25519 açık anahtarı.
  static Future<EncryptedEnvelope> seal({
    required String plaintext,
    required Uint8List senderPrivateKeyBytes,
    required Uint8List senderPublicKeyBytes,
    required String senderId,
    required String recipientId,
    required Uint8List recipientX25519PublicKeyBytes,
  }) async {
    // 1. Ephemeral X25519 anahtar çifti oluştur (PFS)
    final ephemeral = await CryptoService.generateEphemeralKeyPair();

    // 2. ECDH ile oturum anahtarı türet
    final sessionKey = await CryptoService.deriveSharedKey(
      myPrivateKeyBytes: ephemeral.privateKeyBytes,
      theirPublicKeyBytes: recipientX25519PublicKeyBytes,
    );

    // 3. Mesajı şifrele
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final aad = Uint8List.fromList(utf8.encode('$senderId:$recipientId'));
    final encryptedBlob = await CryptoService.encryptMessage(
      plaintext: plaintextBytes,
      sessionKey: sessionKey,
      aad: aad,
    );

    // Format: [12-byte nonce] + [ciphertext + mac]
    final nonce = encryptedBlob.sublist(0, 12);
    final ciphertext = encryptedBlob.sublist(12);

    final ts = DateTime.now().millisecondsSinceEpoch;

    // 4. Zarfı oluştur (imzasız)
    final partialEnvelope = EncryptedEnvelope(
      version: 1,
      senderId: senderId,
      recipientId: recipientId,
      ephemeralPublicKey: ephemeral.publicKeyBytes,
      nonce: nonce,
      ciphertext: ciphertext,
      signature: Uint8List(0), // Geçici boş imza
      timestamp: ts,
    );

    // 5. İmzala
    final sig = await CryptoService.sign(
      payload: partialEnvelope.signingPayload,
      privateKeyBytes: senderPrivateKeyBytes,
      publicKeyBytes: senderPublicKeyBytes,
    );

    // 6. Tam zarf döndür
    return EncryptedEnvelope(
      version: partialEnvelope.version,
      senderId: partialEnvelope.senderId,
      recipientId: partialEnvelope.recipientId,
      ephemeralPublicKey: partialEnvelope.ephemeralPublicKey,
      nonce: partialEnvelope.nonce,
      ciphertext: partialEnvelope.ciphertext,
      signature: sig,
      timestamp: partialEnvelope.timestamp,
    );
  }

  /// [EncryptedEnvelope]'i doğrular ve şifresini çözerek düz metin mesajı döner.
  ///
  /// [envelope]: Çözülecek zarf.
  /// [myX25519PrivateKeyBytes]: Alıcının X25519 özel anahtarı.
  /// [senderEd25519PublicKeyBytes]: Gönderici Ed25519 açık anahtarı (imza doğrulama).
  static Future<String> open({
    required EncryptedEnvelope envelope,
    required Uint8List myX25519PrivateKeyBytes,
    required Uint8List senderEd25519PublicKeyBytes,
  }) async {
    // 1. Zaman penceresi kontrolü
    if (!envelope.isWithinTimeWindow()) {
      throw SecurityException('Zarfın zaman penceresi dışında (Replay Attack?)');
    }

    // 2. İmza doğrulama
    final isValid = await CryptoService.verify(
      payload: envelope.signingPayload,
      signatureBytes: envelope.signature,
      publicKeyBytes: senderEd25519PublicKeyBytes,
    );
    if (!isValid) {
      throw SecurityException('Geçersiz imza: Zarf manipüle edilmiş olabilir.');
    }

    // 3. ECDH ile oturum anahtarı türet (ephemeral public key + bizim özel anahtar)
    final sessionKey = await CryptoService.deriveSharedKey(
      myPrivateKeyBytes: myX25519PrivateKeyBytes,
      theirPublicKeyBytes: envelope.ephemeralPublicKey,
    );

    // 4. Şifreyi çöz
    final aad = Uint8List.fromList(
        utf8.encode('${envelope.senderId}:${envelope.recipientId}'));

    // Format yeniden birleştir: nonce + ciphertext
    final fullBlob = Uint8List.fromList([
      ...envelope.nonce,
      ...envelope.ciphertext,
    ]);

    final plaintextBytes = await CryptoService.decryptMessage(
      ciphertext: fullBlob,
      sessionKey: sessionKey,
      aad: aad,
    );

    return utf8.decode(plaintextBytes);
  }
}

/// Güvenlik ihlali durumunda fırlatılan özel istisna.
class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}
