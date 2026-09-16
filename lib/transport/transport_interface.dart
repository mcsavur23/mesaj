import 'dart:async';
import '../core/protocol/encrypted_envelope.dart';
import '../models/message.dart';

/// Tüm taşıyıcıların (WebSocket, Bluetooth) uygulaması gereken ortak arayüz.
abstract class TransportInterface {
  /// Bu taşıyıcının türü.
  TransportType get type;

  /// Taşıyıcının şu an aktif (bağlı) olup olmadığı.
  bool get isConnected;

  /// Gelen şifreli zarfları yayınlayan stream.
  Stream<EnvelopeReceived> get incomingEnvelopes;

  /// Bağlantı durumu değişikliklerini yayınlayan stream.
  Stream<TransportConnectionState> get connectionState;

  /// Bağlantıyı başlatır.
  Future<void> connect();

  /// Bağlantıyı kapatır.
  Future<void> disconnect();

  /// Kaynakları serbest bırakır.
  Future<void> dispose();

  /// Şifreli zarfı karşıya gönderir.
  Future<TransportResult> send(EncryptedEnvelope envelope);
}

// ---------------------------------------------------------------------------
// Yardımcı Veri Sınıfları
// ---------------------------------------------------------------------------

/// Taşıyıcı üzerinden gelen şifreli zarf ve kaynak bilgisi.
class EnvelopeReceived {
  final EncryptedEnvelope envelope;
  final TransportType transport;
  final DateTime receivedAt;

  EnvelopeReceived({
    required this.envelope,
    required this.transport,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();
}

/// Gönderim işleminin sonucu.
class TransportResult {
  final bool isSuccess;
  final TransportType transport;
  final String? failureReason;

  const TransportResult._({
    required this.isSuccess,
    required this.transport,
    this.failureReason,
  });

  factory TransportResult.success({required TransportType transport}) =>
      TransportResult._(isSuccess: true, transport: transport);

  factory TransportResult.failure({
    required TransportType transport,
    required String reason,
  }) =>
      TransportResult._(
          isSuccess: false, transport: transport, failureReason: reason);

  @override
  String toString() => isSuccess
      ? 'TransportResult.success(${transport.name})'
      : 'TransportResult.failure(${transport.name}: $failureReason)';
}

/// Taşıyıcı bağlantı durumları.
enum TransportConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}
