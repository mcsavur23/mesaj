import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../../core/protocol/qr_payload.dart';
import '../../models/peer_contact.dart';
import '../../providers/chat_providers.dart';

/// Arkadaşın QR kodunu kamera ile tarayan ve eşleşme başlatan ekran.
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Arkadaş Ekle'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _scannerController.torchState,
              builder: (_, state, __) => Icon(
                state == TorchState.on
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
                color: AppTheme.neonCyan,
              ),
            ),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Kamera önizleme
          MobileScanner(
            controller: _scannerController,
            onDetect: _isProcessing ? null : _onDetect,
          ),

          // Tarama çerçevesi ve kılavuzu
          _ScanOverlay(),

          // Durum mesajı
          if (_statusMessage != null)
            Positioned(
              bottom: 80,
              left: 24,
              right: 24,
              child: _StatusCard(
                message: _statusMessage!,
                isSuccess: _isSuccess,
              ).animate().fadeIn().slideY(begin: 0.2),
            ),

          // Alt bilgi
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  'Arkadaşının QR kodunu çerçeveye getir',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'QR kodu işleniyor...';
      _isSuccess = false;
    });

    await _scannerController.stop();

    try {
      // QR payload'u ayrıştır
      final payload = QrPayload.fromJsonString(raw);

      // İmzayı doğrula
      final isValid = await payload.verifySignature();

      if (!isValid) {
        _showError('Geçersiz imza — QR kodu manipüle edilmiş olabilir!');
        return;
      }

      // Arkadaşı SQLite'a kaydet ve Provider'ı güncelle
      final newContact = PeerContact(
        peerId: payload.peerId,
        alias: payload.alias,
        ed25519PublicKey: payload.identityPublicKey,
        x25519PublicKey: payload.encryptionPublicKey,
        bleServiceUuid: payload.bleServiceUuid,
        addedAt: DateTime.now(),
        isVerified: true,
      );

      await ref.read(contactsProvider.notifier).addContact(newContact);

      setState(() {
        _statusMessage = '✓ ${payload.alias} başarıyla eklendi!';
        _isSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 1200));

      if (mounted) Navigator.pop(context, newContact);
    } catch (e) {
      _showError('Geçersiz QR kodu. Mesaj uygulamasına ait değil.');
    }
  }

  void _showError(String message) {
    setState(() {
      _statusMessage = '✗ $message';
      _isSuccess = false;
      _isProcessing = false;
    });

    // 3 saniye sonra tekrar tara
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _statusMessage = null);
        _scannerController.start();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Yardımcı Widget'lar
// ---------------------------------------------------------------------------

class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Koyu kenarlık overlay
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.6),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration:
                    const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut),
              ),
              Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Neon çerçeve köşeleri
        Center(
          child: SizedBox(
            width: 260,
            height: 260,
            child: CustomPaint(
              painter: _CornerPainter(),
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(duration: 2.seconds, color: AppTheme.neonCyan.withOpacity(0.5)),
      ],
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.neonCyan
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 28.0;
    const r = 12.0;

    final corners = [
      // Sol üst
      [Offset(r, 0), Offset(cornerLen, 0), Offset(0, r), Offset(0, cornerLen)],
      // Sağ üst
      [
        Offset(size.width - cornerLen, 0),
        Offset(size.width - r, 0),
        Offset(size.width, r),
        Offset(size.width, cornerLen)
      ],
      // Sol alt
      [
        Offset(0, size.height - cornerLen),
        Offset(0, size.height - r),
        Offset(r, size.height),
        Offset(cornerLen, size.height)
      ],
      // Sağ alt
      [
        Offset(size.width, size.height - cornerLen),
        Offset(size.width, size.height - r),
        Offset(size.width - r, size.height),
        Offset(size.width - cornerLen, size.height)
      ],
    ];

    for (final corner in corners) {
      canvas.drawLine(corner[0], corner[1], paint);
      canvas.drawLine(corner[2], corner[3], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatusCard extends StatelessWidget {
  final String message;
  final bool isSuccess;

  const _StatusCard({required this.message, required this.isSuccess});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isSuccess
            ? AppTheme.neonGreen.withOpacity(0.15)
            : AppTheme.neonRed.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSuccess
              ? AppTheme.neonGreen.withOpacity(0.5)
              : AppTheme.neonRed.withOpacity(0.5),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isSuccess ? AppTheme.neonGreen : AppTheme.neonRed,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
