import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/message.dart';

/// Cihazda yerel olarak mesaj geçmişini saklayan SQLite deposu.
/// Mesajlar SADECE bu cihazda saklanır, sunucuda veya ağda kalıcı tutulmaz.
class MessageRepository {
  static Database? _db;

  static Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'mesaj_history.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            content TEXT NOT NULL,
            sent_at INTEGER NOT NULL,
            delivered_at INTEGER,
            status TEXT NOT NULL,
            transport TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_messages_chat ON messages (sender_id, recipient_id)
        ''');
      },
    );
  }

  /// Yeni bir mesaj kaydeder.
  static Future<void> saveMessage(Message message) async {
    final db = await _database;
    await db.insert(
      'messages',
      {
        'id': message.id,
        'sender_id': message.senderId,
        'recipient_id': message.recipientId,
        'content': message.content,
        'sent_at': message.sentAt.millisecondsSinceEpoch,
        'delivered_at': message.deliveredAt?.millisecondsSinceEpoch,
        'status': message.status.name,
        'transport': message.transport.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Belirli bir arkadaşla olan tüm mesajları getirir (zamana göre sıralı).
  static Future<List<Message>> getMessagesForPeer({
    required String myPeerId,
    required String peerId,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'messages',
      where:
          '(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
      whereArgs: [myPeerId, peerId, peerId, myPeerId],
      orderBy: 'sent_at ASC',
    );

    return rows.map(_rowToMessage).toList();
  }

  /// Belirli bir arkadaşla olan son mesajı getirir (Sohbet listesi önizlemesi için).
  static Future<Message?> getLastMessageForPeer({
    required String myPeerId,
    required String peerId,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'messages',
      where:
          '(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
      whereArgs: [myPeerId, peerId, peerId, myPeerId],
      orderBy: 'sent_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _rowToMessage(rows.first);
  }

  /// Mesaj durumunu günceller (sent -> delivered gibi).
  static Future<void> updateMessageStatus(
      String messageId, MessageStatus status) async {
    final db = await _database;
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Tüm mesaj geçmişini siler.
  static Future<void> clearAll() async {
    final db = await _database;
    await db.delete('messages');
  }

  static Message _rowToMessage(Map<String, dynamic> row) {
    return Message(
      id: row['id'] as String,
      senderId: row['sender_id'] as String,
      recipientId: row['recipient_id'] as String,
      content: row['content'] as String,
      sentAt: DateTime.fromMillisecondsSinceEpoch(row['sent_at'] as int),
      deliveredAt: row['delivered_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['delivered_at'] as int)
          : null,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == (row['status'] as String),
        orElse: () => MessageStatus.sent,
      ),
      transport: TransportType.values.firstWhere(
        (e) => e.name == (row['transport'] as String),
        orElse: () => TransportType.unknown,
      ),
    );
  }
}
