import 'package:sqflite/sqflite.dart';
import 'server_config_service.dart';
import 'server_discovery_service.dart';
import 'sync_client_service.dart';
import 'sync_service.dart' show kSyncedTables;
import 'sync_version_store.dart';

/// V5.1 — SERVER MASTER SYNC ARCHITECTURE.
///
/// Dipakai HANYA oleh OWNER_ADMIN. Sebelumnya server membaca file .db admin
/// langsung dari storage HP (rawan gagal karena izin Android/MIUI). Sekarang
/// server punya database sendiri, dan admin AKTIF MENGIRIM perubahannya
/// lewat API — bukan lagi dibaca paksa oleh server.
///
/// Sumber data outbox: tabel `sync_log` LOKAL yang sudah ada di setiap
/// aplikasi Flutter (diisi otomatis oleh trigger trg_*_insert/update/
/// delete_sync di database_helper.dart — TIDAK ADA perubahan skema/trigger
/// yang diperlukan, infrastruktur ini sudah lama ada untuk keperluan
/// Partner delta-sync). Karena kolom `payload` di sync_log sengaja NULL
/// (SQLite Android banyak yang tidak punya ekstensi JSON1 — lihat catatan
/// di database_helper.dart), baris lengkap diambil ulang dari tabel aslinya
/// lewat `record_id` saat akan dikirim (untuk INSERT/UPDATE; DELETE cukup
/// kirim record_id saja).
class SyncPushService {
  final ServerConfigService _configService;
  final ServerDiscoveryService _discoveryService;
  final SyncClientService _client;
  final SyncVersionStore _versionStore;

  static const int _batchSize = 200;

  SyncPushService({
    ServerConfigService? configService,
    ServerDiscoveryService? discoveryService,
    SyncClientService? client,
    SyncVersionStore? versionStore,
  })  : _configService = configService ?? ServerConfigService(),
        _discoveryService = discoveryService ?? ServerDiscoveryService(),
        _client = client ?? SyncClientService(),
        _versionStore = versionStore ?? SyncVersionStore();

  /// Kirim semua perubahan lokal yang belum pernah dikirim ke server.
  /// Return jumlah perubahan yang berhasil diterapkan server, atau
  /// melempar [SyncClientException] kalau gagal (server offline, config
  /// belum diisi, dsb) — caller (provider) yang menampilkan pesannya.
  Future<int> pushPending({required Database db, required String deviceName}) async {
    final config = await _configService.load();
    if (!config.isConfigured) {
      throw const SyncClientException('Server belum dikonfigurasi.');
    }

    final host = await _discoveryService.discover(config);
    if (host == null) {
      throw const SyncClientException('Server tidak ditemukan di jaringan (OFFLINE).');
    }

    int totalApplied = 0;
    while (true) {
      final lastId = await _versionStore.lastPushedLogId();

      final logRows = await db.query(
        'sync_log',
        where: 'id > ? AND table_name IN (${List.filled(kSyncedTables.length, '?').join(',')})',
        whereArgs: [lastId, ...kSyncedTables],
        orderBy: 'id ASC',
        limit: _batchSize,
      );
      if (logRows.isEmpty) break;

      final changes = <Map<String, dynamic>>[];
      for (final logRow in logRows) {
        final table = logRow['table_name'] as String;
        final recordId = logRow['record_id'] as int;
        final action = (logRow['action'] as String).toUpperCase();

        if (action == 'DELETE') {
          changes.add({'table': table, 'action': 'DELETE', 'record_id': recordId, 'data': null});
          continue;
        }

        // INSERT/UPDATE: ambil kondisi baris TERKINI dari tabel aslinya
        // (bukan dari payload sync_log yang NULL). Kalau baris sudah tidak
        // ada lagi (mis. dihapus setelah di-update), lewati -- entri
        // sync_log DELETE berikutnya (kalau ada) yang akan menutup baris
        // ini di sisi server.
        final rows = await db.query(table, where: 'id = ?', whereArgs: [recordId], limit: 1);
        if (rows.isEmpty) continue;

        changes.add({'table': table, 'action': action, 'record_id': recordId, 'data': rows.first});
      }

      final maxIdInBatch = logRows.last['id'] as int;

      if (changes.isNotEmpty) {
        final applied = await _client.pushChanges(
          host: host,
          port: config.port,
          apiToken: config.token,
          deviceName: deviceName,
          changes: changes,
        );
        totalApplied += applied;
      }

      // Maju high-water mark walau `changes` kosong (semua baris di batch
      // ini ternyata sudah terhapus) -- supaya outbox tidak stuck mengulang
      // batch yang sama terus-menerus.
      await _versionStore.saveLastPushedLogId(maxIdInBatch);

      if (logRows.length < _batchSize) break; // itu batch terakhir
    }

    return totalApplied;
  }
}
