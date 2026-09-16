import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'transport_interface.dart';
import '../core/protocol/encrypted_envelope.dart';
import '../models/message.dart';

/// Bluetooth Low Energy (BLE) üzerinden doğrudan cihazdan cihaza (P2P) mesaj ileten taşıyıcı.
///
/// Mimari:
/// - PERIPHERAL modu: Kendi BLE servisini yayınlar, gelen şifreli zarfları alır.
/// - CENTRAL modu: Hedef cihazı tarar, bulunca GATT üzerinden şifreli zarfı yazar.
///
/// Mesh ağı KURULMAZ. Sadece 1-e-1, doğrudan bağlantı kurulur.
class BluetoothP2PTransport implements TransportInterface {
  final String myPeerId;
  final String myBleServiceUuid;

  bool _isConnected = false;
  bool _isAdvertising = false;

  final _incomingController = StreamController<EnvelopeReceived>.broadcast();
  final _connectionStateController =
      StreamController<TransportConnectionState>.broadcast();

  /// GATT Karakteristik UUID'si (şifreli zarf yazma/okuma)
  static const _characteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  /// BLE paket boyutu limiti (MTU genellikle 512 byte'a kadar müzakere edilebilir)
  static const _maxChunkSize = 500;

  BluetoothP2PTransport({
    required this.myPeerId,
    required this.myBleServiceUuid,
  });

  // -----------------------------------------------------------------------
  // TransportInterface Implementasyonu
  // -----------------------------------------------------------------------

  @override
  TransportType get type => TransportType.bluetooth;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<EnvelopeReceived> get incomingEnvelopes =>
      _incomingController.stream;

  @override
  Stream<TransportConnectionState> get connectionState =>
      _connectionStateController.stream;

  // -----------------------------------------------------------------------
  // Bağlantı Başlatma (Peripheral Mod — Gelen mesajları dinle)
  // -----------------------------------------------------------------------

  @override
  Future<void> connect() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _connectionStateController.add(TransportConnectionState.error);
      return;
    }

    _isConnected = true;
    _connectionStateController.add(TransportConnectionState.connected);

    // Gelen bağlantıları dinle (Peripheral olarak)
    _listenForIncomingConnections();
  }

  void _listenForIncomingConnections() {
    // flutter_blue_plus v1.x'te Peripheral/Server modu platforma özeldir.
    // Android: BluetoothGattServer API gerekir (Kotlin FFI veya MethodChannel)
    // iOS: CBPeripheralManager gerekir
    //
    // Bu sınıf iskelet/arayüz olarak çalışır.
    // Gerçek Peripheral implementasyonu platform kanallarıyla tamamlanacaktır.
    //
    // Şimdilik sadece Scan & Connect (Central) modu implemente edilmiştir.
  }

  // -----------------------------------------------------------------------
  // Mesaj Gönderme (Central Mod — Hedef cihaza bağlan ve yaz)
  // -----------------------------------------------------------------------

  @override
  Future<TransportResult> send(EncryptedEnvelope envelope) async {
    // Hedefin BLE servis UUID'sini bul (rehberden alınmış olmalı)
    // Bu metod hedef BLE UUID'sini parametre olarak almaz;
    // HybridRouter bu bilgiyi sağlayarak doğru metodu çağırır.
    return TransportResult.failure(
      transport: TransportType.bluetooth,
      reason: 'sendToPeer metodu kullanılmalı.',
    );
  }

  /// Belirli bir BLE servis UUID'sine sahip cihazı tarar, bağlanır ve zarfı iletir.
  ///
  /// [targetBleServiceUuid]: Hedef cihazın BLE servis UUID'si.
  /// [envelope]: Gönderilecek şifreli zarf.
  Future<TransportResult> sendToPeer({
    required String targetBleServiceUuid,
    required EncryptedEnvelope envelope,
  }) async {
    try {
      _connectionStateController.add(TransportConnectionState.connecting);

      // 1. Tarama başlat (hedefin servis UUID'sine göre filtrele)
      final targetDevice = await _scanForDevice(targetBleServiceUuid);
      if (targetDevice == null) {
        return TransportResult.failure(
          transport: TransportType.bluetooth,
          reason: 'Hedef cihaz bulunamadı (kapsama alanı dışı?).',
        );
      }

      // 2. Bağlan
      await targetDevice.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      // 3. GATT servislerini keşfet
      final services = await targetDevice.discoverServices();
      final targetService = services.where((s) {
        return s.uuid.toString().toLowerCase() ==
            targetBleServiceUuid.toLowerCase();
      }).firstOrNull;

      if (targetService == null) {
        await targetDevice.disconnect();
        return TransportResult.failure(
          transport: TransportType.bluetooth,
          reason: 'Hedef servisi bulunamadı.',
        );
      }

      // 4. Yazma karakteristiğini bul
      final characteristic = targetService.characteristics.where((c) {
        return c.uuid.toString().toLowerCase() ==
            _characteristicUuid.toLowerCase();
      }).firstOrNull;

      if (characteristic == null) {
        await targetDevice.disconnect();
        return TransportResult.failure(
          transport: TransportType.bluetooth,
          reason: 'Yazma karakteristiği bulunamadı.',
        );
      }

      // 5. Zarfı JSON olarak serileştir ve parçalara ayırarak gönder
      final envelopeJson = envelope.toJsonString();
      final bytes = Uint8List.fromList(utf8.encode(envelopeJson));

      await _sendChunked(characteristic, bytes);

      // 6. Bağlantıyı kapat (yalnızca bu mesaj için bağlıydık)
      await targetDevice.disconnect();
      _connectionStateController.add(TransportConnectionState.connected);

      return TransportResult.success(transport: TransportType.bluetooth);
    } catch (e) {
      _connectionStateController.add(TransportConnectionState.error);
      return TransportResult.failure(
        transport: TransportType.bluetooth,
        reason: e.toString(),
      );
    }
  }

  Future<BluetoothDevice?> _scanForDevice(String serviceUuid) async {
    final completer = Completer<BluetoothDevice?>();
    late StreamSubscription sub;
    bool found = false;

    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final advertisedUuids = result.advertisementData.serviceUuids
            .map((u) => u.toString().toLowerCase())
            .toList();

        if (advertisedUuids.contains(serviceUuid.toLowerCase())) {
          found = true;
          FlutterBluePlus.stopScan();
          completer.complete(result.device);
          return;
        }
      }
    });

    // 8 saniyelik tarama
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 8),
      withServices: [Guid(serviceUuid)],
    );

    await Future.delayed(const Duration(seconds: 8));

    await sub.cancel();

    if (!found && !completer.isCompleted) {
      completer.complete(null);
    }

    return completer.future;
  }

  /// Büyük byte dizisini BLE MTU sınırına uygun parçalara bölerek gönderir.
  Future<void> _sendChunked(
      BluetoothCharacteristic characteristic, Uint8List data) async {
    // Toplam parça sayısını belirten 4-byte header ekle
    final totalChunks = (data.length / _maxChunkSize).ceil();
    int offset = 0;
    int chunkIndex = 0;

    while (offset < data.length) {
      final end = (offset + _maxChunkSize).clamp(0, data.length);
      final chunk = data.sublist(offset, end);

      // Basit protokol header: [chunkIndex:2][totalChunks:2][data...]
      final packet = Uint8List(4 + chunk.length)
        ..[0] = (chunkIndex >> 8) & 0xFF
        ..[1] = chunkIndex & 0xFF
        ..[2] = (totalChunks >> 8) & 0xFF
        ..[3] = totalChunks & 0xFF;
      packet.setRange(4, 4 + chunk.length, chunk);

      await characteristic.write(packet, withoutResponse: false);

      offset = end;
      chunkIndex++;
    }
  }

  // -----------------------------------------------------------------------
  // Kapatma
  // -----------------------------------------------------------------------

  @override
  Future<void> disconnect() async {
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
