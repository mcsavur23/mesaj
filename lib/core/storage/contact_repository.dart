import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/peer_contact.dart';
import '../crypto/crypto_service.dart';

/// Eşleşilen arkadaşların kriptografik bilgilerini SQLite'ta saklayan depo.
///
/// Sadece açık anahtarlar ve meta veri saklanır. Özel anahtar ASLA bu tabloya girmez.
class ContactRepository {
  static Database? _db;

  static Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'mesaj_contacts.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE contacts (
            peer_id TEXT PRIMARY KEY,
            alias TEXT NOT NULL,
            ed25519_public_key TEXT NOT NULL,
            x25519_public_key TEXT NOT NULL,
            ble_service_uuid TEXT NOT NULL,
            added_at INTEGER NOT NULL,
            last_seen_at INTEGER,
            is_verified INTEGER NOT NULL DEFAULT 1
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_contacts_ble ON contacts (ble_service_uuid)
        ''');
      },
    );
  }

  // -----------------------------------------------------------------------
  // CRUD İşlemleri
  // -----------------------------------------------------------------------

  /// Yeni bir arkadaş ekler. Zaten mevcutsa günceller.
  static Future<void> upsertContact(PeerContact contact) async {
    final db = await _database;
    await db.insert(
      'contacts',
      {
        'peer_id': contact.peerId,
        'alias': contact.alias,
        'ed25519_public_key': CryptoService.toBase64(contact.ed25519PublicKey),
        'x25519_public_key': CryptoService.toBase64(contact.x25519PublicKey),
        'ble_service_uuid': contact.bleServiceUuid,
        'added_at': contact.addedAt.millisecondsSinceEpoch,
        'last_seen_at': contact.lastSeenAt?.millisecondsSinceEpoch,
        'is_verified': contact.isVerified ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Tüm kayıtlı arkadaşları döner.
  static Future<List<PeerContact>> getAllContacts() async {
    final db = await _database;
    final rows = await db.query('contacts', orderBy: 'added_at DESC');
    return rows.map(_rowToContact).toList();
  }

  /// Peer ID'ye göre tek arkadaş döner.
  static Future<PeerContact?> getContact(String peerId) async {
    final db = await _database;
    final rows = await db.query(
      'contacts',
      where: 'peer_id = ?',
      whereArgs: [peerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToContact(rows.first);
  }

  /// BLE servis UUID'sine göre arkadaş arar (Bluetooth keşfi için).
  static Future<PeerContact?> getContactByBleUuid(String bleUuid) async {
    final db = await _database;
    final rows = await db.query(
      'contacts',
      where: 'ble_service_uuid = ?',
      whereArgs: [bleUuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToContact(rows.first);
  }

  /// Arkadaşın son görülme zamanını günceller.
  static Future<void> updateLastSeen(String peerId) async {
    final db = await _database;
    await db.update(
      'contacts',
      {'last_seen_at': DateTime.now().millisecondsSinceEpoch},
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
  }

  /// Arkadaşı siler.
  static Future<void> removeContact(String peerId) async {
    final db = await _database;
    await db.delete('contacts', where: 'peer_id = ?', whereArgs: [peerId]);
  }

  static PeerContact _rowToContact(Map<String, dynamic> row) {
    return PeerContact(
      peerId: row['peer_id'] as String,
      alias: row['alias'] as String,
      ed25519PublicKey: CryptoService.fromBase64(row['ed25519_public_key'] as String),
      x25519PublicKey: CryptoService.fromBase64(row['x25519_public_key'] as String),
      bleServiceUuid: row['ble_service_uuid'] as String,
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
      lastSeenAt: row['last_seen_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['last_seen_at'] as int)
          : null,
      isVerified: (row['is_verified'] as int) == 1,
    );
  }
}
