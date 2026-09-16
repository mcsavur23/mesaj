import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/crypto_service.dart';
import '../core/crypto/key_pair_bundle.dart';
import '../core/protocol/encrypted_envelope.dart';
import '../core/storage/contact_repository.dart';
import '../core/storage/identity_storage.dart';
import '../core/storage/message_repository.dart';
import '../models/message.dart';
import '../models/peer_contact.dart';
import '../transport/bluetooth_p2p_transport.dart';
import '../transport/hybrid_router.dart';
import '../transport/transport_interface.dart';
import '../transport/websocket_transport.dart';

// -----------------------------------------------------------------------------
// 1. Kimlik Sağlayıcısı (Identity Provider)
// -----------------------------------------------------------------------------
final identityProvider = FutureProvider<IdentityBundle>((ref) async {
  return IdentityStorageService.loadOrCreate();
});

// -----------------------------------------------------------------------------
// 2. Arkadaşlar Listesi Sağlayıcısı (Contacts Provider)
// -----------------------------------------------------------------------------
class ContactsNotifier extends StateNotifier<AsyncValue<List<PeerContact>>> {
  ContactsNotifier() : super(const AsyncValue.loading()) {
    loadContacts();
  }

  Future<void> loadContacts() async {
    try {
      final contacts = await ContactRepository.getAllContacts();
      state = AsyncValue.data(contacts);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addContact(PeerContact contact) async {
    await ContactRepository.upsertContact(contact);
    await loadContacts();
  }

  Future<void> removeContact(String peerId) async {
    await ContactRepository.removeContact(peerId);
    await loadContacts();
  }
}

final contactsProvider =
    StateNotifierProvider<ContactsNotifier, AsyncValue<List<PeerContact>>>((ref) {
  return ContactsNotifier();
});

// -----------------------------------------------------------------------------
// 3. Hibrit Taşıyıcı ve Router Sağlayıcısı
// -----------------------------------------------------------------------------
final hybridRouterProvider = Provider<HybridRouter?>((ref) {
  final identityAsync = ref.watch(identityProvider);

  return identityAsync.when(
    data: (identity) {
      // Şimdilik yerel relay sunucusuna veya varsayılan adrese bağlanır
      // (Daha sonra deploy edilen wss:// sunucu adresiyle güncellenebilir)
      final ws = WebSocketTransport(
        serverUrl: 'ws://10.0.2.2:8080', // Android emülatör / yerel ağ desteği
        myPeerId: identity.peerId,
      );

      final ble = BluetoothP2PTransport(
        myBleServiceUuid: identity.bleServiceUuid,
      );

      final router = HybridRouter(
        wsTransport: ws,
        bleTransport: ble,
      );

      router.initialize();

      ref.onDispose(() {
        router.dispose();
      });

      return router;
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// -----------------------------------------------------------------------------
// 4. Mesajlaşma Sağlayıcısı (Her sohbet için ayrı state)
// -----------------------------------------------------------------------------
class ChatNotifier extends StateNotifier<List<Message>> {
  final Ref ref;
  final PeerContact peer;
  final IdentityBundle myIdentity;
  StreamSubscription? _incomingSub;

  ChatNotifier({
    required this.ref,
    required this.peer,
    required this.myIdentity,
  }) : super([]) {
    _initChat();
  }

  Future<void> _initChat() async {
    // 1. Veritabanındaki mesaj geçmişini yükle
    final history = await MessageRepository.getMessagesForPeer(
      myPeerId: myIdentity.peerId,
      peerId: peer.peerId,
    );
    state = history;

    // 2. Hibrit yönlendiriciden gelen canlı mesajları dinle
    final router = ref.read(hybridRouterProvider);
    if (router != null) {
      _incomingSub = router.incomingEnvelopes.listen((event) async {
        if (event.envelope.senderId == peer.peerId) {
          await _handleIncomingEnvelope(event);
        }
      });
    }
  }

  /// Karşı taraftan gelen şifreli zarfı çöz ve listeye ekle
  Future<void> _handleIncomingEnvelope(EnvelopeReceived event) async {
    try {
      // 1. Ortak anahtar türet (bizim X25519 priv + karşı tarafın X25519 pub)
      final sessionKey = await CryptoService.deriveSharedKey(
        myPrivateKeyBytes: myIdentity.encryptionKeyPair.privateKeyBytes,
        theirPublicKeyBytes: peer.x25519PublicKey,
      );

      // 2. ChaCha20-Poly1305 ile şifreyi çöz
      // (nonce + payload birleşik format veya zarftaki nonce + payload)
      final encryptedBytes = Uint8List.fromList([
        ...event.envelope.nonce,
        ...event.envelope.payload,
      ]);

      final decryptedBytes = await CryptoService.decryptMessage(
        ciphertext: encryptedBytes,
        sessionKey: sessionKey,
      );

      final content = utf8.decode(decryptedBytes);

      final incomingMessage = Message(
        id: event.envelope.messageId,
        senderId: peer.peerId,
        recipientId: myIdentity.peerId,
        content: content,
        sentAt: event.envelope.timestamp,
        deliveredAt: DateTime.now(),
        status: MessageStatus.received,
        transport: event.transport,
      );

      await MessageRepository.saveMessage(incomingMessage);
      state = [...state, incomingMessage];
    } catch (e) {
      // Şifre çözme hatası veya bozuk paket
    }
  }

  /// Mesaj gönder: E2EE Şifrele -> HybridRouter ile ilet -> Yerel DB'ye kaydet -> Ekrana bas
  Future<bool> sendMessage(String text) async {
    if (text.trim().isEmpty) return false;

    final router = ref.read(hybridRouterProvider);
    if (router == null) return false;

    final messageId = const Uuid().v4();
    final now = DateTime.now();

    // 1. Ortak anahtarı türet
    final sessionKey = await CryptoService.deriveSharedKey(
      myPrivateKeyBytes: myIdentity.encryptionKeyPair.privateKeyBytes,
      theirPublicKeyBytes: peer.x25519PublicKey,
    );

    // 2. ChaCha20-Poly1305 AEAD ile mesajı şifrele
    final encryptedBlob = await CryptoService.encryptMessage(
      plaintext: Uint8List.fromList(utf8.encode(text.trim())),
      sessionKey: sessionKey,
    );

    // encryptedBlob formatı: 12-byte nonce + (kalanı ciphertext + MAC)
    final nonce = encryptedBlob.sublist(0, 12);
    final payload = encryptedBlob.sublist(12);

    // 3. İmzala (Ed25519)
    final signature = await CryptoService.sign(
      payload: payload,
      privateKeyBytes: myIdentity.identityKeyPair.privateKeyBytes,
      publicKeyBytes: myIdentity.identityKeyPair.publicKeyBytes,
    );

    // 4. Şifreli zarfı paketle
    final envelope = EncryptedEnvelope(
      messageId: messageId,
      senderId: myIdentity.peerId,
      recipientId: peer.peerId,
      ephemeralPublicKey: myIdentity.encryptionKeyPair.publicKeyBytes,
      nonce: nonce,
      payload: payload,
      signature: signature,
      timestamp: now,
    );

    // 4. Ön UI durumu ekle (pending)
    final initialMessage = Message(
      id: messageId,
      senderId: myIdentity.peerId,
      recipientId: peer.peerId,
      content: text.trim(),
      sentAt: now,
      status: MessageStatus.pending,
      transport: router.activeTransport,
    );
    state = [...state, initialMessage];

    // 5. İlet
    final result = await router.route(
      envelope: envelope,
      targetBleServiceUuid: peer.bleServiceUuid,
    );

    final finalStatus =
        result.isSuccess ? MessageStatus.sent : MessageStatus.failed;

    final updatedMessage = initialMessage.copyWith(
      status: finalStatus,
      transport: result.transport,
    );

    // 6. DB'ye kaydet ve state güncelle
    await MessageRepository.saveMessage(updatedMessage);

    state = [
      for (final m in state)
        if (m.id == messageId) updatedMessage else m
    ];

    return result.isSuccess;
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }
}

final chatProvider =
    StateNotifierProvider.family<ChatNotifier, List<Message>, PeerContact>(
  (ref, peer) {
    final identity = ref.watch(identityProvider).value;
    if (identity == null) {
      throw Exception('Kimlik henüz yüklenmedi');
    }
    return ChatNotifier(
      ref: ref,
      peer: peer,
      myIdentity: identity,
    );
  },
);
