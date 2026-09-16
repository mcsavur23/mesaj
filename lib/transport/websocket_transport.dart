import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../models/message.dart';
import 'transport_interface.dart';
import '../core/protocol/encrypted_envelope.dart';

/// WebSocket üzerinden relay sunucusuna bağlanan ve şifreli zarfları ileten taşıyıcı.
///
/// Sunucu yalnızca bellek üzerinde çalışır ve veritabanı tutmaz.
/// Alıcı çevrimiçiyse paketi anında iletir, değilse paket kaybolur.
class WebSocketTransport implements TransportInterface {
  final String serverUrl;
  final String myPeerId;

  WebSocketChannel? _channel;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  final _incomingController = StreamController<EnvelopeReceived>.broadcast();
  final _connectionStateController =
      StreamController<TransportConnectionState>.broadcast();

  static const _reconnectDelay = Duration(seconds: 3);
  static const _pingInterval = Duration(seconds: 25);

  WebSocketTransport({
    required this.serverUrl,
    required this.myPeerId,
  });

  // -----------------------------------------------------------------------
  // TransportInterface Implementasyonu
  // -----------------------------------------------------------------------

  @override
  TransportType get type => TransportType.websocket;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<EnvelopeReceived> get incomingEnvelopes =>
      _incomingController.stream;

  @override
  Stream<TransportConnectionState> get connectionState =>
      _connectionStateController.stream;

  // -----------------------------------------------------------------------
  // Bağlantı Yönetimi
  // -----------------------------------------------------------------------

  @override
  Future<void> connect() async {
    if (_isConnected) return;
    await _connectInternal();
  }

  Future<void> _connectInternal() async {
    try {
      _connectionStateController.add(TransportConnectionState.connecting);

      // Sunucuya Peer ID ile bağlan
      final uri = Uri.parse('$serverUrl/ws?peerId=$myPeerId');
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;

      _isConnected = true;
      _connectionStateController.add(TransportConnectionState.connected);

      // Gelen mesajları dinle
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnected,
        cancelOnError: false,
      );

      // Periyodik ping (bağlantıyı canlı tutar)
      _startPing();
    } catch (e) {
      _isConnected = false;
      _connectionStateController.add(TransportConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic rawData) {
    try {
      final json = jsonDecode(rawData as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'envelope') {
        final envelope = EncryptedEnvelope.fromJson(
            json['payload'] as Map<String, dynamic>);
        _incomingController.add(EnvelopeReceived(
          envelope: envelope,
          transport: TransportType.websocket,
        ));
      }
    } catch (_) {
      // Geçersiz paket yoksay
    }
  }

  void _onError(Object error) {
    _isConnected = false;
    _connectionStateController.add(TransportConnectionState.error);
    _stopPing();
  }

  void _onDisconnected() {
    _isConnected = false;
    _connectionStateController.add(TransportConnectionState.disconnected);
    _stopPing();
    _scheduleReconnect();
  }

  // -----------------------------------------------------------------------
  // Mesaj Gönderme
  // -----------------------------------------------------------------------

  @override
  Future<TransportResult> send(EncryptedEnvelope envelope) async {
    if (!_isConnected || _channel == null) {
      return TransportResult.failure(
        transport: TransportType.websocket,
        reason: 'WebSocket bağlı değil.',
      );
    }

    try {
      final payload = jsonEncode({
        'type': 'envelope',
        'recipientId': envelope.recipientId,
        'payload': envelope.toJson(),
      });

      _channel!.sink.add(payload);

      return TransportResult.success(transport: TransportType.websocket);
    } catch (e) {
      return TransportResult.failure(
        transport: TransportType.websocket,
        reason: e.toString(),
      );
    }
  }

  // -----------------------------------------------------------------------
  // Ping & Yeniden Bağlanma
  // -----------------------------------------------------------------------

  void _startPing() {
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_isConnected && _channel != null) {
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _connectInternal);
  }

  // -----------------------------------------------------------------------
  // Kapatma
  // -----------------------------------------------------------------------

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _stopPing();
    await _channel?.sink.close(ws_status.goingAway);
    _isConnected = false;
    _connectionStateController.add(TransportConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _incomingController.close();
    await _connectionStateController.close();
  }
}
