import 'dart:io';

/// WebSocket relay sunucusu (RAM-only, veritabanı YOK).
///
/// Çalıştırma:
///   dart run server/relay_server.dart
///
/// Ortam değişkenleri:
///   PORT       — Dinlenecek port (varsayılan: 8765)
///   HOST       — Bind adresi (varsayılan: 0.0.0.0)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8765;
  final host = Platform.environment['HOST'] ?? '0.0.0.0';

  final server = await HttpServer.bind(host, port);
  print('[MesajRelay] Sunucu başlatıldı: ws://$host:$port');
  print('[MesajRelay] Veritabanı: YOK (Tamamen RAM üzerinde çalışıyor)');
  print('[MesajRelay] Bağlı peer sayısı: 0\n');

  // peerId -> WebSocket eşlemesi (Tek canlı hafıza)
  final Map<String, WebSocket> connectedPeers = {};

  await for (final request in server) {
    if (request.uri.path == '/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      _handleWebSocket(request, connectedPeers);
    } else if (request.method == 'GET' && request.uri.path == '/health') {
      // Sağlık kontrolü endpoint'i
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'connectedPeers': connectedPeers.length,
          'db': false,
          'version': '1.0.0',
        }))
        ..close();
    } else {
      request.response
        ..statusCode = 404
        ..close();
    }
  }
}

Future<void> _handleWebSocket(
  HttpRequest request,
  Map<String, WebSocket> connectedPeers,
) async {
  final peerId = request.uri.queryParameters['peerId'];
  if (peerId == null || peerId.isEmpty) {
    request.response
      ..statusCode = 400
      ..close();
    return;
  }

  final ws = await WebSocketTransformer.upgrade(request);
  connectedPeers[peerId] = ws;

  print('[+] Peer bağlandı: ${_truncate(peerId)} '
      '(Toplam: ${connectedPeers.length})');

  ws.listen(
    (rawData) => _onMessage(rawData, peerId, connectedPeers, ws),
    onDone: () {
      connectedPeers.remove(peerId);
      print('[-] Peer ayrıldı: ${_truncate(peerId)} '
          '(Toplam: ${connectedPeers.length})');
    },
    onError: (_) {
      connectedPeers.remove(peerId);
    },
    cancelOnError: false,
  );
}

void _onMessage(
  dynamic rawData,
  String senderPeerId,
  Map<String, WebSocket> connectedPeers,
  WebSocket senderWs,
) {
  try {
    final json = jsonDecode(rawData as String) as Map<String, dynamic>;
    final type = json['type'] as String?;

    if (type == 'ping') {
      // Pong yanıtı gönder (bağlantıyı canlı tutar)
      senderWs.add(jsonEncode({'type': 'pong'}));
      return;
    }

    if (type == 'envelope') {
      final recipientId = json['recipientId'] as String?;
      if (recipientId == null) return;

      final recipientWs = connectedPeers[recipientId];
      if (recipientWs == null) {
        // Alıcı çevrimiçi değil — paketi iletme, sil.
        // GÜVENLİK: Sunucu mesajı ASLA depolamaz.
        senderWs.add(jsonEncode({
          'type': 'delivery_status',
          'status': 'offline',
          'recipientId': recipientId,
        }));
        print('[→] Alıcı çevrimdışı: ${_truncate(recipientId)} '
            '(Paket silindi, depolanmadı)');
        return;
      }

      // Şifreli paketi olduğu gibi ilet (sunucu içeriği okuyamaz)
      recipientWs.add(jsonEncode({
        'type': 'envelope',
        'payload': json['payload'],
      }));

      // Gönderene onay
      senderWs.add(jsonEncode({
        'type': 'delivery_status',
        'status': 'delivered',
        'recipientId': recipientId,
      }));

      print('[→] İletildi: ${_truncate(senderPeerId)} → '
          '${_truncate(recipientId)} (şifreli, içerik okunmadı)');
    }
  } catch (_) {
    // Geçersiz JSON yoksay
  }
}

/// Peer ID'nin ilk 8 karakterini döner (log okunabilirliği için).
String _truncate(String id) =>
    id.length > 8 ? '${id.substring(0, 8)}...' : id;
