import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/crypto/crypto_service.dart';
import '../../models/message.dart';
import '../../models/peer_contact.dart';
import '../../providers/chat_providers.dart';
import '../theme/app_theme.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final PeerContact peer;

  const ChatScreen({super.key, required this.peer});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    _textController.clear();
    setState(() => _isSending = true);

    try {
      await ref.read(chatProvider(widget.peer).notifier).sendMessage(text);
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider(widget.peer));
    final router = ref.watch(hybridRouterProvider);
    final activeTransport = router?.activeTransport ?? TransportType.websocket;

    // Yeni mesaj gelince otomatik aşağı kaydır
    ref.listen(chatProvider(widget.peer), (previous, next) {
      if (next.length > (previous?.length ?? 0)) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(activeTransport),
      body: Column(
        children: [
          _buildEncryptionNotice(),
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyChat()
                : ListView.builder(
                    controller: _scrollController,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _MessageBubble(
                        message: message,
                        key: ValueKey(message.id),
                      );
                    },
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(TransportType transport) {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 1,
      titleSpacing: 0,
      title: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppTheme.surfaceElevated,
            child: Text(
              widget.peer.alias.substring(0, 2).toUpperCase(),
              style: const TextStyle(
                color: AppTheme.neonCyan,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.peer.alias,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      transport == TransportType.websocket
                          ? Icons.bolt_rounded
                          : Icons.bluetooth_rounded,
                      size: 13,
                      color: transport == TransportType.websocket
                          ? AppTheme.neonCyan
                          : AppTheme.neonPurple,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      transport == TransportType.websocket
                          ? 'İnternet (Aktif)'
                          : 'Bluetooth P2P (Hazır)',
                      style: TextStyle(
                        fontSize: 11,
                        color: transport == TransportType.websocket
                            ? AppTheme.neonCyan
                            : AppTheme.neonPurple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.shield_outlined, color: AppTheme.neonGreen),
          tooltip: 'Şifreleme & Parmak İzi',
          onPressed: _showFingerprintDialog,
        ),
      ],
    );
  }

  Widget _buildEncryptionNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.lock_rounded, size: 14, color: AppTheme.neonCyan),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Uçtan Uca Şifreli (X25519 + AES-GCM). Sunucu mesajları okuyamaz.',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 48, color: AppTheme.textMuted.withOpacity(0.5)),
          const SizedBox(height: 12),
          const Text(
            'İlk mesajınızı gönderin',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Mesajınız cihazınızda şifrelenip doğrudan hedefe iletilir.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Şifreli mesaj yazın...',
                  filled: true,
                  fillColor: AppTheme.surfaceElevated,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppTheme.neonCyan,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _handleSend,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.background,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: AppTheme.background,
                          size: 18,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFingerprintDialog() {
    final fingerprint = CryptoService.toBase64(widget.peer.ed25519PublicKey)
        .substring(0, 24);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.verified_user_rounded, color: AppTheme.neonGreen, size: 20),
            SizedBox(width: 8),
            Text('Kriptografik Güvenlik', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bu kişiyle olan tüm iletişim doğrudan aşağıdaki açık anahtarla şifrelenir:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                fingerprint,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppTheme.neonCyan,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Anonim Kimlik Peer ID:\n',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
            Text(
              widget.peer.peerId,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat', style: TextStyle(color: AppTheme.neonCyan)),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;

  const _MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isOut = message.isOutgoing;
    final timeStr = DateFormat('HH:mm').format(message.sentAt);

    return Align(
      alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOut ? AppTheme.outgoingBubble : AppTheme.incomingBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isOut ? const Radius.circular(16) : Radius.zero,
            bottomRight: isOut ? Radius.zero : const Radius.circular(16),
          ),
          border: Border.all(
            color: isOut
                ? AppTheme.neonPurple.withOpacity(0.3)
                : AppTheme.neonGreen.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.background.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    message.transport.shortLabel,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: message.transport == TransportType.websocket
                          ? AppTheme.neonCyan
                          : AppTheme.neonPurple,
                    ),
                  ),
                ),
                if (isOut) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(message.status),
                ],
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time_rounded,
            size: 11, color: AppTheme.textMuted);
      case MessageStatus.sent:
        return const Icon(Icons.check_rounded,
            size: 12, color: AppTheme.textSecondary);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all_rounded,
            size: 12, color: AppTheme.neonCyan);
      case MessageStatus.received:
        return const SizedBox.shrink();
      case MessageStatus.failed:
        return const Icon(Icons.error_outline_rounded,
            size: 12, color: AppTheme.neonRed);
    }
  }
}
