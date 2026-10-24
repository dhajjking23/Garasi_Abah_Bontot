import 'package:sqflite/sqflite.dart';
import 'server_config_service.dart';
import 'server_discovery_service.dart';
import 'sync_client_service.dart';
import 'sync_apply_service.dart';
import 'sync_version_store.dart';

/// Daftar tabel yang benar-benar disinkron dari Master, HARUS PERSIS SAMA
/// dengan `_syncedTables` di database_helper.dart (yang menentukan tabel
/// mana yang punya trigger sync_version/sync_log di sisi Master). Kalau
/// dua daftar ini berbeda, tabel yang hilang dari sini tidak akan pernah
/// ke-sync walau triggernya aktif di Master.
const List<String> kSyncedTables = [
  'users',
  'motor',
  'motor_cost',
  'penjualan',
  'pemasukan',
  'pengeluaran',
  'kasbon',
  'cash_flow',
  'saldo',
  'dana_talang',
  'gajihan',
  'biaya_transfer_manual',
  'periode',
  'audit_log',
];

class SyncResult {
  final bool success;
  final String? errorMessage;
  final List<String> tablesUpdated;
  final DateTime at;

  const SyncResult({
    required this.success,
    this.errorMessage,
    this.tablesUpdated = const [],
    required this.at,
  });

  factory SyncResult.failure(String message) =>
      SyncResult(success: false, errorMessage: message, at: DateTime.now());
}

/// Orchestrator sync Partner <- Master. Alur:
///   1. Baca config server tersimpan (host/port/token) + auto-discover
///      host aktif di jaringan lokal (reuse ServerDiscoveryService, sama
///      seperti yang dipakai ServerScreen).
///   2. Baca client_versions terakhir yang tersimpan di HP ini.
///   3. POST /sync -> tahu tabel mana saja yang punya perubahan.
///   4. Untuk tiap tabel yang berubah: GET /table/{name} (full fetch).
///   5. Terapkan semua tabel sekaligus ke SQLite lokal (1 transaksi).
///   6. Simpan client_versions baru + timestamp sync terakhir.
///
/// Tidak melempar exception ke caller — semua error ditangkap dan
/// dikembalikan lewat SyncResult.errorMessage supaya UI bisa menampilkan
/// pesan tanpa try-catch berulang di banyak tempat.
class SyncService {
  final ServerConfigService _configService;
  final ServerDiscoveryService _discoveryService;
  final SyncClientService _client;
  final SyncApplyService _applyService;
  final SyncVersionStore _versionStore;

  SyncService({
    ServerConfigService? configService,
    ServerDiscoveryService? discoveryService,
    SyncClientService? client,
    SyncApplyService? applyService,
    SyncVersionStore? versionStore,
  })  : _configService = configService ?? ServerConfigService(),
        _discoveryService = discoveryService ?? ServerDiscoveryService(),
        _client = client ?? SyncClientService(),
        _applyService = applyService ?? SyncApplyService(),
        _versionStore = versionStore ?? SyncVersionStore();

  Future<DateTime?> lastSyncAt() => _versionStore.lastSyncAt();

  Future<SyncResult> syncNow({
    required Database db,
    required String deviceName,
  }) async {
    try {
      final config = await _configService.load();
      if (!config.isConfigured) {
        return SyncResult.failure('Server belum dikonfigurasi.');
      }

      final host = await _discoveryService.discover(config);
      if (host == null) {
        return SyncResult.failure('Server tidak ditemukan di jaringan (OFFLINE).');
      }

      final clientVersions = await _versionStore.loadVersions();

      final delta = await _client.pullDelta(
        host: host,
        port: config.port,
        apiToken: config.token,
        clientVersions: clientVersions,
        deviceName: deviceName,
      );

      final changedTables = delta.tables.where((t) => kSyncedTables.contains(t.tableName)).toList();

      if (changedTables.isEmpty) {
        await _versionStore.markSyncedNow();
        return SyncResult(success: true, tablesUpdated: const [], at: DateTime.now());
      }

      final tablesData = <String, List<Map<String, dynamic>>>{};
      for (final t in changedTables) {
        tablesData[t.tableName] = await _client.fetchTable(
          host: host,
          port: config.port,
          apiToken: config.token,
          tableName: t.tableName,
        );
      }

      await _applyService.applyFullMirror(db, tablesData);

      final newVersions = Map<String, int>.from(clientVersions);
      for (final t in changedTables) {
        newVersions[t.tableName] = t.version;
      }
      await _versionStore.saveVersions(newVersions);
      await _versionStore.markSyncedNow();

      return SyncResult(
        success: true,
        tablesUpdated: changedTables.map((t) => t.tableName).toList(),
        at: DateTime.now(),
      );
    } on SyncClientException catch (e) {
      return SyncResult.failure(e.message);
    } catch (e) {
      return SyncResult.failure('Sync gagal: $e');
    }
  }

  /// Dipanggil saat logout / ganti akun supaya sesi berikutnya mulai
  /// sync dari nol (hindari data nyasar antar akun di device yang sama).
  Future<void> resetLocalSyncState() => _versionStore.clear();
}
