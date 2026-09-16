import 'dart:async';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'transport_interface.dart';
import 'websocket_transport.dart';
import 'bluetooth_p2p_transport.dart';
import '../core/protocol/encrypted_envelope.dart';
import '../core/storage/contact_repository.dart';
import '../models/message.dart';

/// Mesajı en uygun taşıyıcıya yönlendiren hibrit yönlendirici.
///
/// Öncelik:
/// 1. İnternet varsa → [WebSocketTransport]
/// 2. İnternet yoksa  → [BluetoothP2PTransport]
///
/// Her iki durumda da mesaj aynı [EncryptedEnvelope] formatında ve
/// aynı E2EE şifreleme algoritmasıyla gönderilir.
class HybridRouter {
  final WebSocketTransport _wsTransport;
  final BluetoothP2PTransport _bleTransport;

  bool _hasInternet = false;

  late final StreamSubscription _connectivitySub;
  final _incomingController = StreamController<EnvelopeReceived>.broadcast();
  final _routingEventController = StreamController<RoutingEvent>.broadcast();

  HybridRouter({
    required WebSocketTransport wsTransport,
    required BluetoothP2PTransport bleTransport,
  })  : _wsTransport = wsTransport,
        _bleTransport = bleTransport;

  // -----------------------------------------------------------------------
  // Başlatma
  // -----------------------------------------------------------------------

  Future<void> initialize() async {
    // Bağlantı durumunu izle
    final status = await Connectivity().checkConnectivity();
    _hasInternet = _isOnline(status);

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _hasInternet;
      _hasInternet = _isOnline(results);

      if (wasOnline != _hasInternet) {
        _routingEventController.add(RoutingEvent(
          type: _hasInternet
              ? RoutingEventType.switchedToWebSocket
              : RoutingEventType.switchedToBluetooth,
        ));
      }
    });

    // Her iki taşıyıcıdan gelen mesajları tek stream'de topla
    _wsTransport.incomingEnvelopes.listen(_incomingController.add);
    _bleTransport.incomingEnvelopes.listen(_incomingController.add);

    // WebSocket'i hemen bağla
    await _wsTransport.connect();

    // BLE'yi her zaman dinleme modunda başlat
    await _bleTransport.connect();
  }

  // -----------------------------------------------------------------------
  // Mesaj Gönderme
  // -----------------------------------------------------------------------

  /// Şifreli zarfı hedef peer'e en uygun yoldan iletir.
  ///
  /// [envelope]: Gönderilecek şifreli zarf.
  /// [targetBleServiceUuid]: BLE fallback için hedefin servis UUID'si.
  Future<TransportResult> route({
    required EncryptedEnvelope envelope,
    required String targetBleServiceUuid,
  }) async {
    if (_hasInternet && _wsTransport.isConnected) {
      // --- İnternet yolu ---
      final result = await _wsTransport.send(envelope);
      if (result.isSuccess) {
        _routingEventController.add(RoutingEvent(
          type: RoutingEventType.sentViaWebSocket,
          peerId: envelope.recipientId,
        ));
        return result;
      }
      // WebSocket başarısız → BLE'ye düş
    }

    // --- Bluetooth yolu ---
    _routingEventController.add(RoutingEvent(
      type: RoutingEventType.attemptingBluetooth,
      peerId: envelope.recipientId,
    ));

    final result = await _bleTransport.sendToPeer(
      targetBleServiceUuid: targetBleServiceUuid,
      envelope: envelope,
    );

    if (result.isSuccess) {
      _routingEventController.add(RoutingEvent(
        type: RoutingEventType.sentViaBluetooth,
        peerId: envelope.recipientId,
      ));
    } else {
      _routingEventController.add(RoutingEvent(
        type: RoutingEventType.deliveryFailed,
        peerId: envelope.recipientId,
      ));
    }

    return result;
  }

  // -----------------------------------------------------------------------
  // Streams
  // -----------------------------------------------------------------------

  /// Tüm taşıyıcılardan gelen şifreli zarfları yayınlar.
  Stream<EnvelopeReceived> get incomingEnvelopes => _incomingController.stream;

  /// Yönlendirme olaylarını yayınlar (UI güncellemesi için).
  Stream<RoutingEvent> get routingEvents => _routingEventController.stream;

  /// Şu an hangi taşıyıcının aktif olduğunu döner.
  TransportType get activeTransport =>
      (_hasInternet && _wsTransport.isConnected)
          ? TransportType.websocket
          : TransportType.bluetooth;

  // -----------------------------------------------------------------------
  // Yardımcı
  // -----------------------------------------------------------------------

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
  }

  // -----------------------------------------------------------------------
  // Kapatma
  // -----------------------------------------------------------------------

  Future<void> dispose() async {
    await _connectivitySub.cancel();
    await _wsTransport.dispose();
    await _bleTransport.dispose();
    await _incomingController.close();
    await _routingEventController.close();
  }
}

// ---------------------------------------------------------------------------
// Yönlendirme Olayı
// ---------------------------------------------------------------------------

class RoutingEvent {
  final RoutingEventType type;
  final String? peerId;
  final DateTime timestamp;

  RoutingEvent({
    required this.type,
    this.peerId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

enum RoutingEventType {
  switchedToWebSocket,
  switchedToBluetooth,
  sentViaWebSocket,
  attemptingBluetooth,
  sentViaBluetooth,
  deliveryFailed,
}
