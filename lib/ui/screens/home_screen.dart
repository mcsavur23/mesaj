import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'qr_display_screen.dart';
import 'qr_scanner_screen.dart';

/// Uygulama ana ekranı — sohbet listesi, bağlantı durumu ve navigasyon.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;

  // TODO: Gerçek verilerle değiştir (Riverpod provider)
  final List<_ConversationPreview> _conversations = [
    _ConversationPreview(
      alias: 'Ghost-A3F2',
      lastMessage: 'Tamam, yarın görüşürüz.',
      timestamp: '22:14',
      unread: 2,
      transport: '⚡',
    ),
    _ConversationPreview(
      alias: 'Cipher-B8E1',
      lastMessage: 'Dosyayı aldım, teşekkürler.',
      timestamp: 'Dün',
      unread: 0,
      transport: '📶',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: _selectedTab == 0 ? _buildConversationList() : _buildProfileTab(),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _selectedTab == 0 ? _buildFab() : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.background,
      title: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) =>
                AppTheme.neonGradient.createShader(bounds),
            child: const Text(
              'M E S A J',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Aktif taşıyıcı rozeti
          _TransportBadge(isOnline: true),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.qr_code_scanner_rounded,
              color: AppTheme.neonCyan),
          tooltip: 'QR ile arkadaş ekle',
          onPressed: () => _openQrScanner(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildConversationList() {
    if (_conversations.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _conversations.length,
      separatorBuilder: (_, __) => const Divider(indent: 72, endIndent: 16),
      itemBuilder: (context, index) {
        final conv = _conversations[index];
        return _ConversationTile(
          preview: conv,
          onTap: () => _openChat(conv),
        )
            .animate(delay: Duration(milliseconds: 50 * index))
            .fadeIn(duration: 300.ms)
            .slideX(begin: 0.05, end: 0);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 64, color: AppTheme.neonCyan.withOpacity(0.3)),
          const SizedBox(height: 20),
          const Text(
            'Henüz sohbet yok',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'QR kodunuzu arkadaşınıza okutarak başlayın.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => _openMyQr(),
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('QR Kodumu Göster'),
          ),
        ],
      ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95)),
    );
  }

  Widget _buildProfileTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.neonCyan.withOpacity(0.3),
                  AppTheme.neonPurple.withOpacity(0.3),
                ],
              ),
              border: Border.all(color: AppTheme.neonCyan, width: 2),
            ),
            child: const Icon(Icons.person_outline_rounded,
                color: AppTheme.neonCyan, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Ghost-A3F2',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Anonim Kimlik — Kayıt gerekmiyor',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 32),
          _buildProfileAction(
            icon: Icons.qr_code_2_rounded,
            label: 'QR Kodumu Göster',
            color: AppTheme.neonCyan,
            onTap: _openMyQr,
          ),
          _buildProfileAction(
            icon: Icons.qr_code_scanner_rounded,
            label: 'QR Tara — Arkadaş Ekle',
            color: AppTheme.neonPurple,
            onTap: _openQrScanner,
          ),
          _buildProfileAction(
            icon: Icons.delete_outline_rounded,
            label: 'Kimliği Sıfırla',
            color: AppTheme.neonRed,
            onTap: _confirmResetIdentity,
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  Widget _buildProfileAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 14),
                Text(label,
                    style: TextStyle(
                        color: color, fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedTab,
      onTap: (i) => setState(() => _selectedTab = i),
      backgroundColor: AppTheme.surface,
      selectedItemColor: AppTheme.neonCyan,
      unselectedItemColor: AppTheme.textMuted,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.chat_bubble_outline_rounded),
          activeIcon: Icon(Icons.chat_bubble_rounded),
          label: 'Sohbetler',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.shield_outlined),
          activeIcon: Icon(Icons.shield_rounded),
          label: 'Kimliğim',
        ),
      ],
    );
  }

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _openMyQr,
      backgroundColor: AppTheme.neonCyan,
      foregroundColor: AppTheme.background,
      tooltip: 'QR Kodumu Göster',
      child: const Icon(Icons.qr_code_2_rounded),
    );
  }

  void _openMyQr() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const QrDisplayScreen()));
  }

  void _openQrScanner() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const QrScannerScreen()));
  }

  void _openChat(_ConversationPreview conv) {
    // TODO: ChatScreen'e git
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${conv.alias} sohbeti açılıyor...'),
        backgroundColor: AppTheme.surface,
      ),
    );
  }

  void _confirmResetIdentity() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('Kimliği Sıfırla',
            style: TextStyle(color: AppTheme.neonRed)),
        content: const Text(
          'Bu işlem geri alınamaz. Tüm anahtarlar ve eşleşmeler kalıcı olarak silinir.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: IdentityStorageService.resetIdentity()
            },
            child: const Text('Sıfırla',
                style: TextStyle(color: AppTheme.neonRed)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Yardımcı Widget'lar
// ---------------------------------------------------------------------------

class _TransportBadge extends StatelessWidget {
  final bool isOnline;
  const _TransportBadge({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isOnline ? AppTheme.neonCyan : AppTheme.neonPurple)
            .withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isOnline ? AppTheme.neonCyan : AppTheme.neonPurple)
              .withOpacity(0.4),
        ),
      ),
      child: Text(
        isOnline ? '⚡ WS' : '📶 BLE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isOnline ? AppTheme.neonCyan : AppTheme.neonPurple,
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
          duration: 2.seconds,
          color: (isOnline ? AppTheme.neonCyan : AppTheme.neonPurple)
              .withOpacity(0.3),
        );
  }
}

class _ConversationTile extends StatelessWidget {
  final _ConversationPreview preview;
  final VoidCallback onTap;

  const _ConversationTile({required this.preview, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.surfaceElevated,
        child: Text(
          preview.alias.substring(0, 2),
          style: const TextStyle(
            color: AppTheme.neonCyan,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(preview.alias,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ),
          Text(preview.timestamp,
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
      subtitle: Row(
        children: [
          Text(
            '${preview.transport} ',
            style: const TextStyle(fontSize: 11),
          ),
          Expanded(
            child: Text(
              preview.lastMessage,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (preview.unread > 0)
            Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: AppTheme.neonCyan,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${preview.unread}',
                style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.background,
                    fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ConversationPreview {
  final String alias;
  final String lastMessage;
  final String timestamp;
  final int unread;
  final String transport;

  const _ConversationPreview({
    required this.alias,
    required this.lastMessage,
    required this.timestamp,
    required this.unread,
    required this.transport,
  });
}
