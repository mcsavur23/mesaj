import 'dart:typed_data';

/// Yerel veritabanında saklanan çözülmüş mesaj modeli.
///
/// Ağ üzerinde bu haliyle GİTMEZ. Sadece cihazda okunabilir biçimde saklanır.
class Message {
  final String id;
  final String senderId;
  final String recipientId;
  final String content;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final MessageStatus status;
  final TransportType transport;

  const Message({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.sentAt,
    this.deliveredAt,
    required this.status,
    required this.transport,
  });

  bool get isOutgoing => status != MessageStatus.received;

  Message copyWith({
    MessageStatus? status,
    DateTime? deliveredAt,
    TransportType? transport,
  }) {
    return Message(
      id: id,
      senderId: senderId,
      recipientId: recipientId,
      content: content,
      sentAt: sentAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      status: status ?? this.status,
      transport: transport ?? this.transport,
    );
  }
}

/// Mesajın gönderim durumu.
enum MessageStatus {
  /// Gönderilmeyi bekliyor
  pending,

  /// Relay/Bluetooth'a iletildi
  sent,

  /// Alıcıya ulaştı
  delivered,

  /// Alıcı tarafından alındı
  received,

  /// Gönderim başarısız
  failed,
}

/// Mesajın hangi taşıyıcı üzerinden gittiği.
enum TransportType {
  /// WebSocket (internet üzerinden relay)
  websocket,

  /// Bluetooth Low Energy (P2P, doğrudan cihazdan cihaza)
  bluetooth,

  /// Belirsiz / henüz iletilmedi
  unknown,
}

extension TransportTypeExtension on TransportType {
  String get displayLabel {
    switch (this) {
      case TransportType.websocket:
        return '⚡ WebSocket';
      case TransportType.bluetooth:
        return '📶 Bluetooth P2P';
      case TransportType.unknown:
        return '⏳ Bekliyor';
    }
  }

  String get shortLabel {
    switch (this) {
      case TransportType.websocket:
        return 'WS';
      case TransportType.bluetooth:
        return 'BLE';
      case TransportType.unknown:
        return '?';
    }
  }
}
