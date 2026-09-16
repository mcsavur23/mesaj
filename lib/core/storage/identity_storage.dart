import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../crypto/crypto_service.dart';
import '../crypto/key_pair_bundle.dart';
import '../protocol/qr_payload.dart';

/// Cihazın kriptografik kimliğini ve oluşturulan şifreleme anahtarlarını
/// güvenli yerel depoda (iOS Keychain / Android Keystore) yöneten servis.
class IdentityStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Depolama anahtarları
  static const _kPeerId = 'mesaj.identity.peer_id';
  static const _kEdPrivate = 'mesaj.identity.ed25519.private';
  static const _kEdPublic = 'mesaj.identity.ed25519.public';
  static const _kX25519Private = 'mesaj.identity.x25519.private';
  static const _kX25519Public = 'mesaj.identity.x25519.public';
  static const _kBleUuid = 'mesaj.identity.ble_uuid';
  static const _kAlias = 'mesaj.identity.alias';

  // -----------------------------------------------------------------------
  // 1. KİMLİK OLUŞTURMA VE YÜKLEME
  // -----------------------------------------------------------------------

  /// Cihazın kimliği mevcutsa yükler, yoksa yeni üretir.
  static Future<IdentityBundle> loadOrCreate() async {
    final existingPeerId = await _storage.read(key: _kPeerId);

    if (existingPeerId != null) {
      return _load(existingPeerId);
    }

    return _createAndStore();
  }

  /// Mevcut kimliği siler ve tamamen yeni bir kimlik üretir.
  /// DİKKAT: Bu işlem geri alınamaz. Tüm eşleşmeler sıfırlanır.
  static Future<IdentityBundle> resetIdentity() async {
    await _storage.deleteAll();
    return _createAndStore();
  }

  // -----------------------------------------------------------------------
  // 2. ÖZEL YARDIMCI METODLAR
  // -----------------------------------------------------------------------

  static Future<IdentityBundle> _createAndStore() async {
    // Ed25519 Kimlik Anahtar Çifti
    final identity = await CryptoService.generateIdentityKeyPair();

    // X25519 Şifreleme Anahtar Çifti
    final encryption = await CryptoService.generateEphemeralKeyPair();

    // BLE Servis UUID'si (cihaza özgü)
    final bleUuid = _generateBleServiceUuid(identity.peerId);

    // Alias
    final alias = QrPayloadBuilder.build(
      identityKeyPair: identity,
      encryptionKeyPair: encryption,
      bleServiceUuid: bleUuid,
    ).then((p) => p.alias);

    // Güvenli depoya yaz
    await Future.wait([
      _storage.write(key: _kPeerId, value: identity.peerId),
      _storage.write(
          key: _kEdPrivate,
          value: CryptoService.toBase64(identity.privateKeyBytes)),
      _storage.write(
          key: _kEdPublic,
          value: CryptoService.toBase64(identity.publicKeyBytes)),
      _storage.write(
          key: _kX25519Private,
          value: CryptoService.toBase64(encryption.privateKeyBytes)),
      _storage.write(
          key: _kX25519Public,
          value: CryptoService.toBase64(encryption.publicKeyBytes)),
      _storage.write(key: _kBleUuid, value: bleUuid),
    ]);

    final resolvedAlias = await alias;
    await _storage.write(key: _kAlias, value: resolvedAlias);

    return IdentityBundle(
      peerId: identity.peerId,
      identityKeyPair: identity,
      encryptionKeyPair: encryption,
      bleServiceUuid: bleUuid,
      alias: resolvedAlias,
    );
  }

  static Future<IdentityBundle> _load(String peerId) async {
    final edPriv = await _storage.read(key: _kEdPrivate);
    final edPub = await _storage.read(key: _kEdPublic);
    final x25519Priv = await _storage.read(key: _kX25519Private);
    final x25519Pub = await _storage.read(key: _kX25519Public);
    final bleUuid = await _storage.read(key: _kBleUuid);
    final alias = await _storage.read(key: _kAlias);

    if (edPriv == null ||
        edPub == null ||
        x25519Priv == null ||
        x25519Pub == null ||
        bleUuid == null ||
        alias == null) {
      // Eksik veri → yeniden oluştur
      return _createAndStore();
    }

    final identity = EdKeyPairBundle(
      peerId: peerId,
      privateKeyBytes: CryptoService.fromBase64(edPriv),
      publicKeyBytes: CryptoService.fromBase64(edPub),
    );

    final encryption = X25519KeyPairBundle(
      privateKeyBytes: CryptoService.fromBase64(x25519Priv),
      publicKeyBytes: CryptoService.fromBase64(x25519Pub),
    );

    return IdentityBundle(
      peerId: peerId,
      identityKeyPair: identity,
      encryptionKeyPair: encryption,
      bleServiceUuid: bleUuid,
      alias: alias,
    );
  }

  /// Peer ID'nin ilk 8 karakterini kullanarak cihaza özgü BLE servis UUID üretir.
  static String _generateBleServiceUuid(String peerId) {
    // Format: 0000XXXX-0000-1000-8000-00805f9b34fb
    // Peer ID'nin ilk 4 byte'ından UUID segmenti türet
    final segment = peerId.replaceAll('-', '').substring(0, 4).toUpperCase();
    return '0000$segment-0000-1000-8000-00805f9b34fb';
  }
}

// ---------------------------------------------------------------------------
// Kimlik Bundle
// ---------------------------------------------------------------------------

/// Cihazın tam kriptografik kimliğini bir arada tutan veri sınıfı.
class IdentityBundle {
  /// Cihazın benzersiz Peer ID'si
  final String peerId;

  /// Ed25519 kimlik anahtar çifti (imzalama + kimlik doğrulama)
  final EdKeyPairBundle identityKeyPair;

  /// X25519 şifreleme anahtar çifti (ECDH + mesaj şifreleme)
  final X25519KeyPairBundle encryptionKeyPair;

  /// Bluetooth LE servis UUID'si
  final String bleServiceUuid;

  /// İnsan tarafından okunabilir takma ad (Örn: "Ghost-A3F2")
  final String alias;

  const IdentityBundle({
    required this.peerId,
    required this.identityKeyPair,
    required this.encryptionKeyPair,
    required this.bleServiceUuid,
    required this.alias,
  });

  @override
  String toString() =>
      'IdentityBundle(peerId: $peerId, alias: $alias, ble: $bleServiceUuid)';
}
