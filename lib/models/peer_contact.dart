import 'dart:typed_data';

/// Eşleşilen bir arkadaşın kriptografik profili ve meta verisi.
class PeerContact {
  /// Arkadaşın benzersiz Peer ID'si
  final String peerId;

  /// Arkadaşın takma adı (QR okuyunca alınır)
  final String alias;

  /// Arkadaşın Ed25519 açık anahtarı (kimlik doğrulama için)
  final Uint8List ed25519PublicKey;

  /// Arkadaşın X25519 açık anahtarı (mesaj şifreleme için)
  final Uint8List x25519PublicKey;

  /// Arkadaşın BLE servis UUID'si (Bluetooth keşfi için)
  final String bleServiceUuid;

  /// Eşleşme tarihi
  final DateTime addedAt;

  /// En son iletişim tarihi
  final DateTime? lastSeenAt;

  /// QR imzasının doğrulandığını işaretler
  final bool isVerified;

  const PeerContact({
    required this.peerId,
    required this.alias,
    required this.ed25519PublicKey,
    required this.x25519PublicKey,
    required this.bleServiceUuid,
    required this.addedAt,
    this.lastSeenAt,
    this.isVerified = true,
  });

  PeerContact copyWith({
    String? alias,
    DateTime? lastSeenAt,
    bool? isVerified,
  }) {
    return PeerContact(
      peerId: peerId,
      alias: alias ?? this.alias,
      ed25519PublicKey: ed25519PublicKey,
      x25519PublicKey: x25519PublicKey,
      bleServiceUuid: bleServiceUuid,
      addedAt: addedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  @override
  String toString() => 'PeerContact(peerId: $peerId, alias: $alias, verified: $isVerified)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PeerContact && other.peerId == peerId);

  @override
  int get hashCode => peerId.hashCode;
}
