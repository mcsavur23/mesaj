import 'dart:typed_data';

/// Ed25519 kimlik anahtar çiftini saran immutable veri sınıfı.
///
/// [peerId]: UUID tabanlı benzersiz peer kimliği.
/// [privateKeyBytes]: Özel anahtar — ASLA ağa gönderilmez, yalnızca güvenli depoda tutulur.
/// [publicKeyBytes]: Açık anahtar — QR kod ve rehberde paylaşılır.
class EdKeyPairBundle {
  final String peerId;
  final Uint8List privateKeyBytes;
  final Uint8List publicKeyBytes;

  const EdKeyPairBundle({
    required this.peerId,
    required this.privateKeyBytes,
    required this.publicKeyBytes,
  });

  @override
  String toString() =>
      'EdKeyPairBundle(peerId: $peerId, publicKey: ${publicKeyBytes.length} bytes)';
}

/// X25519 ECDH anahtar çiftini saran immutable veri sınıfı.
///
/// [privateKeyBytes]: Özel anahtar — yalnızca ECDH için kullanılır.
/// [publicKeyBytes]: Açık anahtar — QR payload'a dahil edilir.
class X25519KeyPairBundle {
  final Uint8List privateKeyBytes;
  final Uint8List publicKeyBytes;

  const X25519KeyPairBundle({
    required this.privateKeyBytes,
    required this.publicKeyBytes,
  });

  @override
  String toString() =>
      'X25519KeyPairBundle(publicKey: ${publicKeyBytes.length} bytes)';
}
