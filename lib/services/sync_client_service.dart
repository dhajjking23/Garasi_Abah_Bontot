import 'dart:convert';
import 'package:http/http.dart' as http;

/// Hasil satu pemanggilan POST /sync — per tabel yang berubah sejak
/// client_versions terakhir yang dikirim.
class SyncDeltaTable {
  final String tableName;
  final int version;
  final int changeCount;

  const SyncDeltaTable({
    required this.tableName,
    required this.version,
    required this.changeCount,
  });
}

class SyncDeltaResult {
  final DateTime serverTime;
  final List<SyncDeltaTable> tables;

  const SyncDeltaResult({required this.serverTime, required this.tables});

  factory SyncDeltaResult.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map<String, dynamic>?) ?? {};
    final tables = data.entries.map((e) {
      final v = e.value as Map<String, dynamic>;
      final changes = (v['changes'] as List?) ?? const [];
      return SyncDeltaTable(
        tableName: e.key,
        version: v['version'] as int? ?? 0,
        changeCount: changes.length,
      );
    }).toList();
    return SyncDeltaResult(
      serverTime: DateTime.tryParse(json['server_time'] as String? ?? '') ?? DateTime.now(),
      tables: tables,
    );
  }
}

/// Dilempar kalau server menolak request (mis. token salah — 401) atau
/// respons tidak bisa diparse. Ditangkap di layer atas (SyncService) untuk
/// ditampilkan sebagai pesan yang ramah ke user.
class SyncClientException implements Exception {
  final String message;
  const SyncClientException(this.message);
  @override
  String toString() => message;
}

/// Client HTTP murni untuk endpoint sync di Termux Server. Tidak menyentuh
/// database lokal sama sekali — hanya request/response JSON. Penerapan ke
/// SQLite lokal ada di SyncApplyService (terpisah, supaya gampang dites).
class SyncClientService {
  static const _timeout = Duration(seconds: 15);

  Uri _uri(String host, int port, String path) => Uri.parse('http://$host:$port$path');

  /// POST /sync — kirim versi tabel yang diketahui client, terima daftar
  /// tabel yang PUNYA perubahan (payload sebenarnya diambil terpisah lewat
  /// [fetchTable], karena server tidak mengirim payload penuh di /sync —
  /// lihat catatan di database_helper.dart soal keterbatasan json_object()
  /// pada SQLite Android).
  Future<SyncDeltaResult> pullDelta({
    required String host,
    required int port,
    required String apiToken,
    required Map<String, int> clientVersions,
    required String deviceName,
  }) async {
    try {
      final res = await http
          .post(
            _uri(host, port, '/sync'),
            headers: {
              'Content-Type': 'application/json',
              'X-API-Token': apiToken,
            },
            body: jsonEncode({
              'client_versions': clientVersions,
              'device_name': deviceName,
            }),
          )
          .timeout(_timeout);

      if (res.statusCode == 401) {
        throw const SyncClientException('Token server tidak valid.');
      }
      if (res.statusCode != 200) {
        // Server (utils/error_handler.py & endpoint /sync) mengirim JSON
        // {"detail": "..."} berisi penyebab spesifik (mis. db_path salah,
        // tabel sync_version belum ada, dll) — tampilkan itu kalau ada,
        // supaya pesan error tidak berhenti di "status 500/503" saja.
        String detail = 'Server membalas status ${res.statusCode}.';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['detail'] is String && (body['detail'] as String).isNotEmpty) {
            detail = body['detail'] as String;
          }
        } catch (_) {
          // body bukan JSON valid — pakai pesan default di atas
        }
        throw SyncClientException(detail);
      }
      return SyncDeltaResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } on SyncClientException {
      rethrow;
    } catch (e) {
      throw SyncClientException('Gagal menghubungi server: $e');
    }
  }

  /// GET /table/{table_name} — ambil SELURUH isi tabel saat ini dari
  /// Master. Dipakai sebagai fallback full-fetch (bukan payload delta per
  /// baris) supaya tidak bergantung pada payload JSON per-baris yang
  /// memang sengaja NULL di server (lihat sync_engine.py).
  Future<List<Map<String, dynamic>>> fetchTable({
    required String host,
    required int port,
    required String apiToken,
    required String tableName,
  }) async {
    try {
      final res = await http
          .get(
            _uri(host, port, '/table/$tableName'),
            headers: {'X-API-Token': apiToken},
          )
          .timeout(_timeout);

      if (res.statusCode == 401) {
        throw const SyncClientException('Token server tidak valid.');
      }
      if (res.statusCode != 200) {
        throw SyncClientException('Gagal mengambil tabel $tableName (status ${res.statusCode}).');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rows = (body['rows'] as List?) ?? const [];
      return rows.cast<Map<String, dynamic>>();
    } on SyncClientException {
      rethrow;
    } catch (e) {
      throw SyncClientException('Gagal mengambil tabel $tableName: $e');
    }
  }

  /// POST /push — V5.1. Dipakai OWNER_ADMIN untuk mengirim batch perubahan
  /// (outbox dari sync_log lokal, lihat SyncPushService) ke server MASTER.
  /// Partner/Viewer TIDAK PERNAH memanggil ini.
  Future<int> pushChanges({
    required String host,
    required int port,
    required String apiToken,
    required String deviceName,
    required List<Map<String, dynamic>> changes,
  }) async {
    try {
      final res = await http
          .post(
            _uri(host, port, '/push'),
            headers: {
              'Content-Type': 'application/json',
              'X-API-Token': apiToken,
            },
            body: jsonEncode({
              'device_name': deviceName,
              'changes': changes,
            }),
          )
          .timeout(_timeout);

      if (res.statusCode == 401) {
        throw const SyncClientException('Token server tidak valid.');
      }
      if (res.statusCode != 200) {
        String detail = 'Server membalas status ${res.statusCode}.';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['detail'] is String && (body['detail'] as String).isNotEmpty) {
            detail = body['detail'] as String;
          }
        } catch (_) {}
        throw SyncClientException(detail);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['applied'] as int? ?? changes.length;
    } on SyncClientException {
      rethrow;
    } catch (e) {
      throw SyncClientException('Gagal mengirim perubahan ke server: $e');
    }
  }
}
