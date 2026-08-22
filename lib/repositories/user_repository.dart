import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../core/database/database_helper.dart';
import '../models/user_model.dart';

class UserRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  static String hashPassword(String plain) {
    return sha256.convert(utf8.encode(plain)).toString();
  }

  Future<List<UserModel>> getAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query('users', orderBy: 'id ASC');
    return rows.map((e) => UserModel.fromMap(e)).toList();
  }

  Future<UserModel?> getByUsername(String username) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserModel.fromMap(rows.first);
  }

  Future<UserModel?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return UserModel.fromMap(rows.first);
  }

  /// Login: cocokkan username + password. Hanya akun ACTIVE yang bisa login.
  Future<UserModel?> login(String username, String password) async {
    final user = await getByUsername(username);
    if (user == null) return null;
    if (!user.isActive) return null;
    if (user.passwordHash != hashPassword(password)) return null;
    return user;
  }

  /// Hanya OWNER_ADMIN yang boleh memanggil ini (dicek di layer UI/provider).
  Future<void> updateUsername(int id, String newUsername) async {
    final db = await _dbHelper.database;
    await db.update(
      'users',
      {'username': newUsername, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePassword(int id, String newPassword) async {
    final db = await _dbHelper.database;
    await db.update(
      'users',
      {
        'password_hash': hashPassword(newPassword),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setStatus(int id, String status) async {
    final db = await _dbHelper.database;
    await db.update(
      'users',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
