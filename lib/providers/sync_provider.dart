import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync_service.dart';
import '../services/sync_push_service.dart';
import '../services/sync_client_service.dart' show SyncClientException;
import '../services/auth_service.dart';
import 'app_providers.dart';

final syncServiceProvider = Provider<SyncService>((ref) => SyncService());
final syncPushServiceProvider = Provider<SyncPushService>((ref) => SyncPushService());

class SyncState {
  final bool isSyncing;
  final DateTime? lastSyncAt;
  final String? lastError;
  final List<String> lastTablesUpdated;

  const SyncState({
    this.isSyncing = false,
    this.lastSyncAt,
    this.lastError,
    this.lastTablesUpdated = const [],
  });

  SyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncAt,
    String? lastError,
    bool clearError = false,
    List<String>? lastTablesUpdated,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastTablesUpdated: lastTablesUpdated ?? this.lastTablesUpdated,
    );
  }
}

/// State + aksi sync, dipakai bersama oleh ServerScreen (auto-sync saat
/// status ONLINE) dan RootShell (auto-sync sekali saat Partner login/buka
/// app). Satu instance untuk seluruh app (bukan autoDispose) supaya status
/// "kapan terakhir sync" tetap ada walau user pindah-pindah tab.
class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  bool _loadedInitial = false;

  SyncNotifier(this._ref) : super(const SyncState());

  Future<void> _loadInitialIfNeeded() async {
    if (_loadedInitial) return;
    _loadedInitial = true;
    final service = _ref.read(syncServiceProvider);
    final last = await service.lastSyncAt();
    if (last != null) {
      state = state.copyWith(lastSyncAt: last);
    }
  }

  /// Jalankan sync sekarang. Aman dipanggil berkali-kali — kalau sedang
  /// jalan, panggilan berikutnya diabaikan (bukan di-antre) supaya tidak
  /// ada dua sync bentrok menulis ke DB yang sama.
  Future<SyncResult?> syncNow() async {
    await _loadInitialIfNeeded();

    // V5.1: OWNER_ADMIN adalah sumber data (Master di sisi client), jadi
    // arahnya PUSH ke server, bukan PULL seperti Partner. Sebelumnya
    // OWNER_ADMIN tidak melakukan apapun di sini karena server membaca
    // file .db admin langsung -- sekarang server punya DB sendiri dan
    // WAJIB menerima perubahan lewat API.
    if (!AuthService.instance.isViewer) {
      return _pushAsOwnerAdmin();
    }
    if (state.isSyncing) return null;

    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final db = await _ref.read(databaseProvider.future);
      final username = AuthService.instance.currentUser?.username ?? 'Partner';
      final service = _ref.read(syncServiceProvider);
      final result = await service.syncNow(db: db, deviceName: 'Partner ($username)');

      state = state.copyWith(
        isSyncing: false,
        lastSyncAt: result.success ? result.at : state.lastSyncAt,
        lastError: result.success ? null : result.errorMessage,
        clearError: result.success,
        lastTablesUpdated: result.tablesUpdated,
      );

      // Kalau ada tabel yang berubah, refresh semua provider data supaya
      // layar yang sedang terbuka langsung menampilkan data baru tanpa
      // user harus keluar-masuk screen manual.
      if (result.success && result.tablesUpdated.isNotEmpty) {
        _invalidateAllDataProviders();
      }

      return result;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: 'Sync gagal: $e');
      return SyncResult.failure('Sync gagal: $e');
    }
  }

  /// V5.1 — kirim outbox lokal (sync_log) OWNER_ADMIN ke server MASTER.
  /// Tidak menyentuh data lokal admin sama sekali (admin tidak perlu
  /// menerima apa pun balik dari server) -- hanya kirim, lalu tandai
  /// terkirim lewat SyncVersionStore.saveLastPushedLogId di dalam
  /// SyncPushService.
  Future<SyncResult?> _pushAsOwnerAdmin() async {
    if (state.isSyncing) return null;
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final db = await _ref.read(databaseProvider.future);
      final username = AuthService.instance.currentUser?.username ?? 'Admin';
      final pushService = _ref.read(syncPushServiceProvider);
      await pushService.pushPending(db: db, deviceName: 'Admin ($username)');

      final result = SyncResult(success: true, tablesUpdated: const [], at: DateTime.now());
      state = state.copyWith(isSyncing: false, lastSyncAt: result.at, clearError: true);
      return result;
    } on SyncClientException catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.message);
      return SyncResult.failure(e.message);
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: 'Push gagal: $e');
      return SyncResult.failure('Push gagal: $e');
    }
  }

  /// Duplikat sengaja dari refreshSemuaData() di app_providers.dart —
  /// TIDAK memakai fungsi itu langsung karena signature-nya WidgetRef
  /// (dipakai dari widget), sedangkan di sini kita hanya punya Ref biasa
  /// (dipakai dari dalam StateNotifier). Kalau menambah provider data
  /// baru di app_providers.dart, tambahkan juga invalidate-nya di sini.
  void _invalidateAllDataProviders() {
    _ref.invalidate(dashboardSummaryProvider);
    _ref.invalidate(saldoProvider);
    _ref.invalidate(periodeAktifProvider);
    _ref.invalidate(semuaPeriodeProvider);
    _ref.invalidate(daftarMotorProvider);
    _ref.invalidate(stokMotorTersediaProvider);
    _ref.invalidate(daftarPenjualanProvider);
    _ref.invalidate(daftarPemasukanProvider);
    _ref.invalidate(daftarPengeluaranProvider);
    _ref.invalidate(daftarKasbonProvider);
    _ref.invalidate(piutangPerKaryawanProvider);
    _ref.invalidate(histroiCashFlowProvider);
    _ref.invalidate(histroiModalProvider);
    _ref.invalidate(daftarDanaTalangProvider);
    _ref.invalidate(riwayatPembayaranDanaTalangProvider);
    _ref.invalidate(totalPiutangPartnerProvider);
    _ref.invalidate(totalHutangPartnerProvider);
    _ref.invalidate(riwayatMutasiAntarSaldoProvider);
    _ref.invalidate(daftarKategoriProvider);
    _ref.invalidate(daftarGajihanProvider);
    _ref.invalidate(daftarBiayaTransferManualProvider);
  }
}

final syncNotifierProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});
