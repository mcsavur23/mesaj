import 'dart:convert';
import 'dart:typed_data';
import '../crypto/crypto_service.dart';
import '../crypto/key_pair_bundle.dart';

/// QR kod ile paylaşılan cihaz kimlik payload'u.
///
/// Bu payload, arkadaş ekleme sırasında ekranda QR olarak gösterilir
/// ve karşı tarafın kamerasıyla okunur.
///
/// JSON formatı:
/// ```json
/// {
///   "v": 1,
///   "pid": "f8a92...",
///   "alias": "Anon-9341",
///   "epk": "base64url (X25519 açık anahtar)",
///   "ipk": "base64url (Ed25519 açık anahtar)",
///   "ble": "0000ffe0-0000-1000-8000-00805f9b34fb",
///   "sig": "base64url (Ed25519 imzası)"
/// }
/// ```
class QrPayload {
  /// Protokol versiyonu
  final int version;

  /// Cihazın benzersiz Peer ID'si (UUID)
  final String peerId;

  /// İnsan tarafından okunabilir, rastgele üretilen takma ad
  /// Örn: "Anon-7391" veya "Ghost-Alpha"
  final String alias;

  /// Şifreleme için X25519 açık anahtar (ECDH)
  final Uint8List encryptionPublicKey;

  /// Kimlik doğrulama için Ed25519 açık anahtar
  final Uint8List identityPublicKey;

  /// BLE GATT Servis UUID'si (Bluetooth P2P için cihazı bulmaya yarar)
  final String bleServiceUuid;

  /// Ed25519 imzası (yukarıdaki tüm alanların imzası)
  final Uint8List signature;

  const QrPayload({
    required this.version,
    required this.peerId,
    required this.alias,
    required this.encryptionPublicKey,
    required this.identityPublicKey,
    required this.bleServiceUuid,
    required this.signature,
  });

  // -----------------------------------------------------------------------
  // JSON Serileştirme
  // -----------------------------------------------------------------------

  factory QrPayload.fromJson(Map<String, dynamic> json) {
    return QrPayload(
      version: json['v'] as int,
      peerId: json['pid'] as String,
      alias: json['alias'] as String,
      encryptionPublicKey: CryptoService.fromBase64(json['epk'] as String),
      identityPublicKey: CryptoService.fromBase64(json['ipk'] as String),
      bleServiceUuid: json['ble'] as String,
      signature: CryptoService.fromBase64(json['sig'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'pid': peerId,
        'alias': alias,
        'epk': CryptoService.toBase64(encryptionPublicKey),
        'ipk': CryptoService.toBase64(identityPublicKey),
        'ble': bleServiceUuid,
        'sig': CryptoService.toBase64(signature),
      };

  String toJsonString() => jsonEncode(toJson());

  factory QrPayload.fromJsonString(String raw) =>
      QrPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  // -----------------------------------------------------------------------
  // İmzalanacak Payload (imza alanı hariç)
  // -----------------------------------------------------------------------

  Uint8List get signingPayload {
    final map = {
      'v': version,
      'pid': peerId,
      'alias': alias,
      'epk': CryptoService.toBase64(encryptionPublicKey),
      'ipk': CryptoService.toBase64(identityPublicKey),
      'ble': bleServiceUuid,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  // -----------------------------------------------------------------------
  // İmza Doğrulama
  // -----------------------------------------------------------------------

  /// QR payload'undaki imzanın kendi kimlik açık anahtarıyla geçerli olduğunu doğrular.
  /// Bozuk veya manipüle edilmiş QR kodlarını reddeder.
  Future<bool> verifySignature() async {
    return CryptoService.verify(
      payload: signingPayload,
      signatureBytes: signature,
      publicKeyBytes: identityPublicKey,
    );
  }

  @override
  String toString() =>
      'QrPayload(pid: $peerId, alias: $alias, ble: $bleServiceUuid)';
}

// ---------------------------------------------------------------------------
// QR Payload Oluşturucu
// ---------------------------------------------------------------------------

/// Cihazın mevcut kimlik bilgilerinden imzalı bir [QrPayload] üretir.
class QrPayloadBuilder {
  /// Verilen kimlik ve şifreleme anahtarlarından imzalı QR payload üretir.
  static Future<QrPayload> build({
    required EdKeyPairBundle identityKeyPair,
    required X25519KeyPairBundle encryptionKeyPair,
    required String bleServiceUuid,
    String? customAlias,
  }) async {
    final alias = customAlias ?? _generateAlias(identityKeyPair.peerId);

    // İmzasız payload oluştur
    final partial = QrPayload(
      version: 1,
      peerId: identityKeyPair.peerId,
      alias: alias,
      encryptionPublicKey: encryptionKeyPair.publicKeyBytes,
      identityPublicKey: identityKeyPair.publicKeyBytes,
      bleServiceUuid: bleServiceUuid,
      signature: Uint8List(0), // Geçici
    );

    // İmzala
    final sig = await CryptoService.sign(
      payload: partial.signingPayload,
      privateKeyBytes: identityKeyPair.privateKeyBytes,
      publicKeyBytes: identityKeyPair.publicKeyBytes,
    );

    return QrPayload(
      version: partial.version,
      peerId: partial.peerId,
      alias: partial.alias,
      encryptionPublicKey: partial.encryptionPublicKey,
      identityPublicKey: partial.identityPublicKey,
      bleServiceUuid: partial.bleServiceUuid,
      signature: sig,
    );
  }

  /// Peer ID'nin ilk 4 karakterinden rastgele görünümlü bir takma ad üretir.
  static String _generateAlias(String peerId) {
    final adjectives = [
      'Anon', 'Ghost', 'Shadow', 'Silent', 'Dark', 'Cipher',
      'Pixel', 'Static', 'Void', 'Phantom',
    ];
    final code = peerId.substring(0, 4).toUpperCase();
    final adjIdx = peerId.codeUnitAt(0) % adjectives.length;
    return '${adjectives[adjIdx]}-$code';
  }
}
