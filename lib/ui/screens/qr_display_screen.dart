import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

/// Cihazın kendi QR kodunu gösteren ekran.
/// Arkadaşlar bu kodu kamerasıyla okutarak eşleşme başlatır.
class QrDisplayScreen extends StatefulWidget {
  const QrDisplayScreen({super.key});

  @override
  State<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends State<QrDisplayScreen>
    with SingleTickerProviderStateMixin {
  // TODO: Gerçek payload Riverpod provider'dan gelecek
  // Şimdilik örnek JSON yapısı gösterilir
  static const _samplePayload = '''
{
  "v": 1,
  "pid": "f8a92b1c3d4e5f6a",
  "alias": "Ghost-A3F2",
  "epk": "YWJjZGVmZ2hpamtsbW5vcHFycw==",
  "ipk": "dHV2d3h5ejAxMjM0NTY3ODlhYmM=",
  "ble": "0000f8a9-0000-1000-8000-00805f9b34fb",
  "sig": "c2lnbmF0dXJlYnl0ZXNnb2hlcmU="
}''';

  bool _isAnimating = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Benim QR Kodum'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),

            // Başlık
            const Text(
              'Bu kodu arkadaşına okut',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (bounds) =>
                  AppTheme.neonGradient.createShader(bounds),
              child: const Text(
                'Ghost-A3F2',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // QR Kodu
            _QrCard(payload: _samplePayload, isAnimating: _isAnimating)
                .animate()
                .fadeIn(duration: 500.ms)
                .scale(begin: const Offset(0.85, 0.85)),

            const SizedBox(height: 32),

            // Güvenlik notu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppTheme.neonCyan.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        color: AppTheme.neonCyan, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Bu QR kodunda yalnızca açık anahtarlar bulunur. '
                        'Özel anahtarın hiçbir zaman paylaşılmaz.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Payload detayları
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _PayloadInfo(),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  final String payload;
  final bool isAnimating;

  const _QrCard({required this.payload, required this.isAnimating});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withOpacity(0.3),
            blurRadius: 40,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: AppTheme.neonPurple.withOpacity(0.2),
            blurRadius: 60,
            spreadRadius: -10,
          ),
        ],
      ),
      child: QrImageView(
        data: payload,
        version: QrVersions.auto,
        size: 240,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF0A0A0F),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF0A0A0F),
        ),
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(
          duration: 3.seconds,
          color: AppTheme.neonCyan.withOpacity(0.1),
        );
  }
}

class _PayloadInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _InfoChip(label: 'Ed25519', icon: Icons.fingerprint_rounded),
        const SizedBox(width: 8),
        _InfoChip(label: 'X25519', icon: Icons.vpn_key_outlined),
        const SizedBox(width: 8),
        _InfoChip(label: 'BLE UUID', icon: Icons.bluetooth_rounded),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _InfoChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.neonCyan),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
