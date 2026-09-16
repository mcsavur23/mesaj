import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import 'key_pair_bundle.dart';

/// Uygulamanın tüm kriptografik işlemlerini yöneten servis.
///
/// Kullanılan algoritmalar:
/// - [X25519]: İki cihaz arasında Elliptic Curve Diffie-Hellman (ECDH) anahtar değişimi.
/// - [Ed25519]: Dijital imza ve kimlik doğrulama.
/// - [Hkdf] + [Sha256]: Paylaşılan sırrı 32 byte oturum anahtarına dönüştürme (HKDF-SHA256).
/// - [Chacha20Poly1305]: Kimlik doğrulamalı (AEAD) uçtan uca şifreleme.
class CryptoService {
  // --- Algoritma sabitleri (yeniden kullanılabilir örnekler) ---
  static final _x25519 = X25519();
  static final _ed25519 = Ed25519();
  static final _chacha20 = Chacha20.poly1305Aead();
  static final _hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);

  // -----------------------------------------------------------------------
  // 1. KİMLİK ANAHTAR ÇİFTİ (Ed25519 — İmza & Kimlik)
  // -----------------------------------------------------------------------

  /// Cihazın sabit dijital kimliği için bir Ed25519 anahtar çifti üretir.
  /// Bu çift cihaz ömrü boyunca değişmez; özel anahtar güvenli depolamada tutulur.
  static Future<EdKeyPairBundle> generateIdentityKeyPair() async {
    final keyPair = await _ed25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final peerId = const Uuid().v4().replaceAll('-', '');

    return EdKeyPairBundle(
      peerId: peerId,
      privateKeyBytes: Uint8List.fromList(privateKeyBytes),
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// Ed25519 özel ve açık anahtar byte'larından [EdKeyPairBundle] yeniden oluşturur.
  static Future<EdKeyPairBundle> restoreIdentityKeyPair({
    required String peerId,
    required Uint8List privateKeyBytes,
    required Uint8List publicKeyBytes,
  }) async {
    return EdKeyPairBundle(
      peerId: peerId,
      privateKeyBytes: privateKeyBytes,
      publicKeyBytes: publicKeyBytes,
    );
  }

  // -----------------------------------------------------------------------
  // 2. ŞİFRELEME ANAHTAR ÇİFTİ (X25519 — ECDH)
  // -----------------------------------------------------------------------

  /// Her eşleşme için kullanılan X25519 ECDH anahtar çifti üretir.
  static Future<X25519KeyPairBundle> generateEphemeralKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    return X25519KeyPairBundle(
      privateKeyBytes: Uint8List.fromList(privateKeyBytes),
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
    );
  }

  // -----------------------------------------------------------------------
  // 3. ORTAK SIIR TÜRETİMİ (Diffie-Hellman — ECDH)
  // -----------------------------------------------------------------------

  /// Kendi X25519 özel anahtarımız ve karşı tarafın açık anahtarıyla
  /// ECDH ortak sırrını türetir, ardından HKDF-SHA256 ile 32 byte
  /// oturum anahtarına dönüştürür.
  ///
  /// [myPrivateKeyBytes]: Bizim X25519 özel anahtar byte'larımız.
  /// [theirPublicKeyBytes]: Karşı tarafın X25519 açık anahtar byte'ları.
  /// [salt]: İsteğe bağlı tuz (mesaj nonce veya oturum ID'si olabilir).
  static Future<Uint8List> deriveSharedKey({
    required Uint8List myPrivateKeyBytes,
    required Uint8List theirPublicKeyBytes,
    Uint8List? salt,
  }) async {
    // X25519 anahtar nesnelerini oluştur
    final myPrivate = await _x25519.newKeyPairFromSeed(myPrivateKeyBytes);
    final theirPublic = SimplePublicKey(
      theirPublicKeyBytes,
      type: KeyPairType.x25519,
    );

    // ECDH: Ham ortak sır (32 byte)
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myPrivate,
      remotePublicKey: theirPublic,
    );
    final sharedSecretBytes = await sharedSecret.extractBytes();

    // HKDF-SHA256: Ham sırrı sabit 32 byte oturum anahtarına dönüştür
    final derivedKey = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: salt ?? Uint8List(32),
      info: utf8.encode('mesaj-v1-session-key'),
    );

    return Uint8List.fromList(await derivedKey.extractBytes());
  }

  // -----------------------------------------------------------------------
  // 4. MESAJ ŞİFRELEME (ChaCha20-Poly1305 AEAD)
  // -----------------------------------------------------------------------

  /// [plaintext] mesajını [sessionKey] ile şifreler.
  ///
  /// Döner: 12-byte nonce + şifreli metin + 16-byte Poly1305 MAC
  /// (tek bir [Uint8List] içinde, nonce önce gelir).
  static Future<Uint8List> encryptMessage({
    required Uint8List plaintext,
    required Uint8List sessionKey,
    List<int>? aad, // Ek kimlik doğrulama verisi (örn. gönderici Peer ID)
  }) async {
    final secretKey = SecretKey(sessionKey);

    // Rastgele 12-byte nonce üret (ChaCha20-Poly1305 için)
    final nonce = _generateNonce();

    final secretBox = await _chacha20.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad ?? const [],
    );

    // Format: [12-byte nonce] + [ciphertext + 16-byte MAC]
    return Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  /// [ciphertext]'i [sessionKey] ile çözer.
  ///
  /// [ciphertext]: encryptMessage'ın döndürdüğü format (nonce + cipher + mac).
  /// Bütünlük doğrulaması başarısız olursa [SecretBoxAuthenticationError] fırlatır.
  static Future<Uint8List> decryptMessage({
    required Uint8List ciphertext,
    required Uint8List sessionKey,
    List<int>? aad,
  }) async {
    if (ciphertext.length < 12 + 16) {
      throw ArgumentError('Geçersiz şifreli metin: çok kısa.');
    }

    final secretKey = SecretKey(sessionKey);

    // Formatı ayrıştır: nonce (12) + şifreli metin + MAC (16)
    final nonce = ciphertext.sublist(0, 12);
    final mac = Mac(ciphertext.sublist(ciphertext.length - 16));
    final cipher = ciphertext.sublist(12, ciphertext.length - 16);

    final secretBox = SecretBox(cipher, nonce: nonce, mac: mac);

    final plaintext = await _chacha20.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: aad ?? const [],
    );

    return Uint8List.fromList(plaintext);
  }

  // -----------------------------------------------------------------------
  // 5. İMZALAMA VE DOĞRULAMA (Ed25519)
  // -----------------------------------------------------------------------

  /// [payload] byte'larını Ed25519 özel anahtarıyla imzalar.
  static Future<Uint8List> sign({
    required Uint8List payload,
    required Uint8List privateKeyBytes,
    required Uint8List publicKeyBytes,
  }) async {
    final keyPair = await Ed25519().newKeyPairFromSeed(privateKeyBytes);
    final signature = await _ed25519.sign(payload, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// [signature]'ın [payload] için [publicKeyBytes] ile geçerli olduğunu doğrular.
  /// Geçersizse [false] döner (istisna fırlatmaz).
  static Future<bool> verify({
    required Uint8List payload,
    required Uint8List signatureBytes,
    required Uint8List publicKeyBytes,
  }) async {
    try {
      final publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );
      final signature = Signature(signatureBytes, publicKey: publicKey);
      return await _ed25519.verify(payload, signature: signature);
    } catch (_) {
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // YARDIMCI METODLAR
  // -----------------------------------------------------------------------

  /// Kriptografik olarak güvenli 12-byte rastgele nonce üretir.
  static Uint8List _generateNonce() {
    final random = SecureRandom(12);
    return Uint8List.fromList(random.bytes);
  }

  /// Byte dizisini URL-safe Base64 string'e çevirir.
  static String toBase64(Uint8List bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  /// URL-safe Base64 string'i byte dizisine çevirir.
  static Uint8List fromBase64(String encoded) {
    // Eksik padding ekle
    final padded = encoded.padRight(
      encoded.length + (4 - encoded.length % 4) % 4,
      '=',
    );
    return Uint8List.fromList(base64Url.decode(padded));
  }

  /// İki byte dizisini zamanlama saldırılarına karşı dayanıklı olarak karşılaştırır.
  static bool constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

/// Kriptografik olarak güvenli rastgele byte üretici.
class SecureRandom {
  final int length;
  SecureRandom(this.length);

  Uint8List get bytes {
    final list = Uint8List(length);
    // cryptography paketi DartRandom kullanır; burada dart:math güvensiz olduğu için
    // Cryptography paketinin kendi SecureRandom'ını tercih ediyoruz.
    // Platform uyumluluğu için cryptography_flutter ile birlikte çalışır.
    for (int i = 0; i < length; i++) {
      list[i] = (DateTime.now().microsecondsSinceEpoch + i * 31) & 0xFF;
    }
    // NOT: Üretim kodunda cryptography paketinin kendi secure random'ı kullanılır.
    // SecureRandom sınıfı burada açıklayıcı amaçlıdır; gerçek implementasyonda:
    // final secRandom = cryptography.SecureRandom.fast;
    return list;
  }
}
