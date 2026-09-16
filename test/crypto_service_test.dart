import 'dart:typed_data';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:mesaj/core/crypto/crypto_service.dart';
import 'package:mesaj/core/protocol/encrypted_envelope.dart';
import 'package:mesaj/core/protocol/qr_payload.dart';

void main() {
  group('CryptoService — Anahtar Üretimi', () {
    test('Ed25519 anahtar çifti 32 byte uzunluğunda olmalı', () async {
      final bundle = await CryptoService.generateIdentityKeyPair();
      expect(bundle.publicKeyBytes.length, equals(32));
      expect(bundle.privateKeyBytes.length, greaterThanOrEqualTo(32));
      expect(bundle.peerId.isNotEmpty, isTrue);
    });

    test('X25519 anahtar çifti 32 byte uzunluğunda olmalı', () async {
      final bundle = await CryptoService.generateEphemeralKeyPair();
      expect(bundle.publicKeyBytes.length, equals(32));
      expect(bundle.privateKeyBytes.length, greaterThanOrEqualTo(32));
    });

    test('İki farklı anahtar üretimi benzersiz olmalı', () async {
      final a = await CryptoService.generateIdentityKeyPair();
      final b = await CryptoService.generateIdentityKeyPair();
      expect(a.peerId, isNot(equals(b.peerId)));
      expect(a.publicKeyBytes, isNot(equals(b.publicKeyBytes)));
    });
  });

  group('CryptoService — Diffie-Hellman (ECDH)', () {
    test('A ve B aynı ortak anahtarı türetmeli (Diffie-Hellman)', () async {
      // Alice ve Bob'un anahtar çiftleri
      final alice = await CryptoService.generateEphemeralKeyPair();
      final bob = await CryptoService.generateEphemeralKeyPair();

      // Alice → Bob'un açık anahtarıyla ortak sır türetir
      final aliceShared = await CryptoService.deriveSharedKey(
        myPrivateKeyBytes: alice.privateKeyBytes,
        theirPublicKeyBytes: bob.publicKeyBytes,
      );

      // Bob → Alice'in açık anahtarıyla ortak sır türetir
      final bobShared = await CryptoService.deriveSharedKey(
        myPrivateKeyBytes: bob.privateKeyBytes,
        theirPublicKeyBytes: alice.publicKeyBytes,
      );

      // İkisi de aynı anahtarı türetmeli
      expect(aliceShared.length, equals(32));
      expect(CryptoService.constantTimeEquals(aliceShared, bobShared), isTrue);
    });

    test('Farklı anahtar çiftleriyle ortak sır farklı olmalı', () async {
      final a1 = await CryptoService.generateEphemeralKeyPair();
      final a2 = await CryptoService.generateEphemeralKeyPair();
      final b = await CryptoService.generateEphemeralKeyPair();

      final shared1 = await CryptoService.deriveSharedKey(
        myPrivateKeyBytes: a1.privateKeyBytes,
        theirPublicKeyBytes: b.publicKeyBytes,
      );
      final shared2 = await CryptoService.deriveSharedKey(
        myPrivateKeyBytes: a2.privateKeyBytes,
        theirPublicKeyBytes: b.publicKeyBytes,
      );

      expect(CryptoService.constantTimeEquals(shared1, shared2), isFalse);
    });
  });

  group('CryptoService — ChaCha20-Poly1305 Şifreleme', () {
    late Uint8List sessionKey;

    setUpAll(() async {
      final alice = await CryptoService.generateEphemeralKeyPair();
      final bob = await CryptoService.generateEphemeralKeyPair();
      sessionKey = await CryptoService.deriveSharedKey(
        myPrivateKeyBytes: alice.privateKeyBytes,
        theirPublicKeyBytes: bob.publicKeyBytes,
      );
    });

    test('Şifreleme ve çözme tam metin döndürmeli', () async {
      const message = 'Merhaba, bu şifreli bir mesajdır!';
      final plaintext = Uint8List.fromList(utf8.encode(message));

      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      final decrypted = await CryptoService.decryptMessage(
        ciphertext: encrypted,
        sessionKey: sessionKey,
      );

      expect(utf8.decode(decrypted), equals(message));
    });

    test('Şifreli metin düz metinden farklı olmalı', () async {
      const message = 'Test mesajı';
      final plaintext = Uint8List.fromList(utf8.encode(message));

      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      expect(encrypted, isNot(equals(plaintext)));
    });

    test('Yanlış anahtar ile çözme başarısız olmalı', () async {
      const message = 'Gizli mesaj';
      final plaintext = Uint8List.fromList(utf8.encode(message));

      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      // Farklı oturum anahtarı üret
      final wrongA = await CryptoService.generateEphemeralKeyPair();
      final wrongB = await CryptoService.generateEphemeralKeyPair();
      final wrongKey = await CryptoService.deriveSharedKey(
        myPrivateKeyBytes: wrongA.privateKeyBytes,
        theirPublicKeyBytes: wrongB.publicKeyBytes,
      );

      expect(
        () => CryptoService.decryptMessage(
            ciphertext: encrypted, sessionKey: wrongKey),
        throwsA(anything),
      );
    });

    test('Bozulmuş şifreli metin çözme başarısız olmalı', () async {
      const message = 'Manipüle edilecek mesaj';
      final plaintext = Uint8List.fromList(utf8.encode(message));

      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      // Son byte'u boz (MAC manipülasyonu)
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 1] ^= 0xFF;

      expect(
        () => CryptoService.decryptMessage(
            ciphertext: tampered, sessionKey: sessionKey),
        throwsA(anything),
      );
    });

    test('Her şifreleme farklı nonce üretmeli (deterministik değil)', () async {
      const message = 'Aynı mesaj';
      final plaintext = Uint8List.fromList(utf8.encode(message));

      final enc1 = await CryptoService.encryptMessage(
          plaintext: plaintext, sessionKey: sessionKey);
      final enc2 = await CryptoService.encryptMessage(
          plaintext: plaintext, sessionKey: sessionKey);

      // Nonce farklı olduğu için şifreli metinler farklı olmalı
      expect(enc1, isNot(equals(enc2)));
    });
  });

  group('CryptoService — Ed25519 İmzalama', () {
    test('İmza doğrulama başarılı olmalı', () async {
      final bundle = await CryptoService.generateIdentityKeyPair();
      final payload = Uint8List.fromList(utf8.encode('İmzalanacak veri'));

      final sig = await CryptoService.sign(
        payload: payload,
        privateKeyBytes: bundle.privateKeyBytes,
        publicKeyBytes: bundle.publicKeyBytes,
      );

      final isValid = await CryptoService.verify(
        payload: payload,
        signatureBytes: sig,
        publicKeyBytes: bundle.publicKeyBytes,
      );

      expect(isValid, isTrue);
    });

    test('Yanlış açık anahtarla doğrulama başarısız olmalı', () async {
      final alice = await CryptoService.generateIdentityKeyPair();
      final bob = await CryptoService.generateIdentityKeyPair();
      final payload = Uint8List.fromList(utf8.encode('Alice imzaladı'));

      final sig = await CryptoService.sign(
        payload: payload,
        privateKeyBytes: alice.privateKeyBytes,
        publicKeyBytes: alice.publicKeyBytes,
      );

      // Bob'un açık anahtarıyla doğrulama — başarısız olmalı
      final isValid = await CryptoService.verify(
        payload: payload,
        signatureBytes: sig,
        publicKeyBytes: bob.publicKeyBytes,
      );

      expect(isValid, isFalse);
    });

    test('Bozulmuş payload doğrulama başarısız olmalı', () async {
      final bundle = await CryptoService.generateIdentityKeyPair();
      final payload = Uint8List.fromList(utf8.encode('Orijinal veri'));

      final sig = await CryptoService.sign(
        payload: payload,
        privateKeyBytes: bundle.privateKeyBytes,
        publicKeyBytes: bundle.publicKeyBytes,
      );

      final tampered = Uint8List.fromList(utf8.encode('Değiştirilmiş veri'));

      final isValid = await CryptoService.verify(
        payload: tampered,
        signatureBytes: sig,
        publicKeyBytes: bundle.publicKeyBytes,
      );

      expect(isValid, isFalse);
    });
  });

  group('EncryptedEnvelope — Protokol', () {
    test('JSON serileştirme/deserileştirme idempotent olmalı', () async {
      final alice = await CryptoService.generateIdentityKeyPair();
      final aliceX = await CryptoService.generateEphemeralKeyPair();
      final bob = await CryptoService.generateIdentityKeyPair();
      final bobX = await CryptoService.generateEphemeralKeyPair();

      final envelope = await EnvelopeBuilder.seal(
        plaintext: 'Test mesajı',
        senderPrivateKeyBytes: alice.privateKeyBytes,
        senderPublicKeyBytes: alice.publicKeyBytes,
        senderId: alice.peerId,
        recipientId: bob.peerId,
        recipientX25519PublicKeyBytes: bobX.publicKeyBytes,
      );

      final json = envelope.toJsonString();
      final restored = EncryptedEnvelope.fromJsonString(json);

      expect(restored.senderId, equals(envelope.senderId));
      expect(restored.recipientId, equals(envelope.recipientId));
      expect(restored.timestamp, equals(envelope.timestamp));
      expect(
        CryptoService.constantTimeEquals(restored.signature, envelope.signature),
        isTrue,
      );
    });

    test('Zarf oluşturma ve açma uçtan uca çalışmalı', () async {
      final alice = await CryptoService.generateIdentityKeyPair();
      final aliceX = await CryptoService.generateEphemeralKeyPair();
      final bob = await CryptoService.generateIdentityKeyPair();
      final bobX = await CryptoService.generateEphemeralKeyPair();

      const originalMessage = 'Merhaba Bob! Bu mesaj sadece sana görünür.';

      // Alice → Bob'a şifreli zarf oluşturur
      final envelope = await EnvelopeBuilder.seal(
        plaintext: originalMessage,
        senderPrivateKeyBytes: alice.privateKeyBytes,
        senderPublicKeyBytes: alice.publicKeyBytes,
        senderId: alice.peerId,
        recipientId: bob.peerId,
        recipientX25519PublicKeyBytes: bobX.publicKeyBytes,
      );

      // Bob zarfı açar
      final decrypted = await EnvelopeBuilder.open(
        envelope: envelope,
        myX25519PrivateKeyBytes: bobX.privateKeyBytes,
        senderEd25519PublicKeyBytes: alice.publicKeyBytes,
      );

      expect(decrypted, equals(originalMessage));
    });

    test('Replay attack: Eski zarf reddedilmeli', () async {
      final alice = await CryptoService.generateIdentityKeyPair();
      final bob = await CryptoService.generateIdentityKeyPair();
      final bobX = await CryptoService.generateEphemeralKeyPair();

      final envelope = await EnvelopeBuilder.seal(
        plaintext: 'Eski mesaj',
        senderPrivateKeyBytes: alice.privateKeyBytes,
        senderPublicKeyBytes: alice.publicKeyBytes,
        senderId: alice.peerId,
        recipientId: bob.peerId,
        recipientX25519PublicKeyBytes: bobX.publicKeyBytes,
      );

      // Zaman penceresini çok kısa tut
      expect(
        envelope.isWithinTimeWindow(window: Duration.zero),
        isFalse,
      );
    });
  });
}
