import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Menyimpan "versi tabel terakhir yang diketahui" per tabel di HP Partner
/// ini, supaya /sync berikutnya hanya minta perubahan yang BELUM dipunya
/// (delta), bukan seluruh database tiap kali. Disimpan permanen di
/// SharedPreferences (bukan di database utama) supaya independen dari
/// mirror data bisnis yang di-replace tiap sync.
class SyncVersionStore {
  static const _kVersions = 'sync_client_versions_v1';
  static const _kLastSyncAt = 'sync_last_synced_at_v1';
  static const _kLastPushedLogId = 'sync_last_pushed_log_id_v1';

  Future<Map<String, int>> loadVersions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kVersions);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveVersions(Map<String, int> versions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVersions, jsonEncode(versions));
  }

  Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastSyncAt);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  Future<void> markSyncedNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSyncAt, DateTime.now().toIso8601String());
  }

  /// V5.1 — high-water mark untuk outbox PUSH (OWNER_ADMIN): id terakhir di
  /// tabel sync_log LOKAL yang sudah berhasil dikirim ke server. Terpisah
  /// dari [_kVersions] yang dipakai arah PULL (Partner), supaya admin &
  /// partner di device yang sama (kalau ada) tidak saling timpa state.
  Future<int> lastPushedLogId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLastPushedLogId) ?? 0;
  }

  Future<void> saveLastPushedLogId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastPushedLogId, id);
  }

  /// Reset total — dipakai kalau user logout/ganti akun, supaya sync
  /// berikutnya mulai dari nol (full resync), menghindari data nyasar
  /// antar sesi/akun berbeda di device yang sama.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kVersions);
    await prefs.remove(_kLastSyncAt);
    await prefs.remove(_kLastPushedLogId);
  }
}
