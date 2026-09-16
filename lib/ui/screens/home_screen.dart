import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/identity_storage.dart';
import '../../core/storage/message_repository.dart';
import '../../models/message.dart';
import '../../models/peer_contact.dart';
import '../../providers/chat_providers.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'qr_display_screen.dart';
import 'qr_scanner_screen.dart';

/// Uygulama ana ekranı — sohbet listesi, bağlantı durumu ve navigasyon.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(identityProvider);
    final router = ref.watch(hybridRouterProvider);
    final isOnline = router?.activeTransport == TransportType.websocket;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(isOnline),
      body: _selectedTab == 0
          ? _buildConversationList()
          : _buildProfileTab(identityAsync),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _selectedTab == 0 ? _buildFab() : null,
    );
  }

  PreferredSizeWidget _buildAppBar(bool isOnline) {
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
          _TransportBadge(isOnline: isOnline),
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
    final contactsAsync = ref.watch(contactsProvider);

    return contactsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.neonCyan),
      ),
      error: (e, _) => Center(
        child: Text('Kişiler yüklenemedi: $e',
            style: const TextStyle(color: AppTheme.neonRed)),
      ),
      data: (contacts) {
        if (contacts.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: contacts.length,
          separatorBuilder: (_, __) =>
              const Divider(indent: 72, endIndent: 16),
          itemBuilder: (context, index) {
            final contact = contacts[index];
            return _ConversationTile(
              contact: contact,
              onTap: () => _openChat(contact),
            )
                .animate(delay: Duration(milliseconds: 50 * index))
                .fadeIn(duration: 300.ms)
                .slideX(begin: 0.05, end: 0);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
              'Kayıt ve numara yok. Arkadaşınızın QR kodunu tarayarak veya kendi kodunuzu göstererek başlayın.',
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
      ),
    );
  }

  Widget _buildProfileTab(AsyncValue<IdentityBundle> identityAsync) {
    return identityAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.neonCyan),
      ),
      error: (e, _) => Center(
        child: Text('Kimlik yüklenemedi: $e',
            style: const TextStyle(color: AppTheme.neonRed)),
      ),
      data: (identity) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
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
                child: Center(
                  child: Text(
                    identity.alias.substring(0, 2).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.neonCyan,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(identity.alias,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Anonim Kriptografik Kimlik',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
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
        ),
      ),
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
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrDisplayScreen()),
    );
  }

  Future<void> _openQrScanner() async {
    final result = await Navigator.push<PeerContact?>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (result != null && mounted) {
      _openChat(result);
    }
  }

  void _openChat(PeerContact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(peer: contact)),
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
          'Bu işlem geri alınamaz. Tüm anahtarlarınız, sohbet geçmişiniz ve eşleşmeleriniz silinir.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await IdentityStorageService.resetIdentity();
              await MessageRepository.clearAll();
              ref.invalidate(identityProvider);
              ref.invalidate(contactsProvider);
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
  final PeerContact contact;
  final VoidCallback onTap;

  const _ConversationTile({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.surfaceElevated,
        child: Text(
          contact.alias.substring(0, 2).toUpperCase(),
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
            child: Text(
              contact.alias,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          const Icon(Icons.verified_user_rounded,
              color: AppTheme.neonGreen, size: 14),
        ],
      ),
      subtitle: Row(
        children: const [
          Icon(Icons.lock_rounded, size: 12, color: AppTheme.textMuted),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              'Uçtan Uca Şifreli Sohbet',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppTheme.textMuted,
        size: 18,
      ),
      onTap: onTap,
    );
  }
}
