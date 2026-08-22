import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../repositories/motor_repository.dart';
import '../repositories/penjualan_repository.dart';
import '../repositories/pemasukan_repository.dart';
import '../repositories/pengeluaran_repository.dart';
import '../repositories/kasbon_repository.dart';
import '../repositories/dana_talang_repository.dart';
import '../repositories/biaya_transfer_manual_repository.dart';
import '../repositories/kategori_repository.dart';
import '../services/audit_rollback_service.dart';
import '../repositories/gajihan_repository.dart';
import '../models/gajihan_model.dart';
import '../repositories/periode_repository.dart';
import '../repositories/saldo_repository.dart';
import '../repositories/audit_log_repository.dart';
import '../services/dashboard_service.dart';
import '../services/laporan_service.dart';
import '../services/pembagian_laba_service.dart';
import '../models/periode_model.dart';
import '../models/cash_flow_model.dart';
import '../models/modal_history_model.dart';
import '../models/mutasi_antar_saldo_model.dart';
import '../models/dana_talang_model.dart';
import '../models/biaya_transfer_manual_model.dart';

/// Provider database - async karena sqflite butuh membuka file lebih dulu.
final databaseProvider = FutureProvider<Database>((ref) async {
  return DatabaseHelper.instance.database;
});

/// Provider level repository/service dibuat sebagai Provider biasa yang
/// bergantung pada databaseProvider melalui `.future`. UI cukup pakai
/// `ref.watch(xxxRepositoryProvider.future)` atau bungkus dengan
/// FutureProvider turunan sesuai kebutuhan layar.

final motorRepositoryProvider = FutureProvider<MotorRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MotorRepository(db);
});

final penjualanRepositoryProvider =
    FutureProvider<PenjualanRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PenjualanRepository(db);
});

final pemasukanRepositoryProvider =
    FutureProvider<PemasukanRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PemasukanRepository(db);
});

final pengeluaranRepositoryProvider =
    FutureProvider<PengeluaranRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PengeluaranRepository(db);
});

final kasbonRepositoryProvider = FutureProvider<KasbonRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return KasbonRepository(db);
});

final danaTalangRepositoryProvider =
    FutureProvider<DanaTalangRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return DanaTalangRepository(db);
});

final biayaTransferManualRepositoryProvider =
    FutureProvider<BiayaTransferManualRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return BiayaTransferManualRepository(db);
});

final kategoriRepositoryProvider =
    FutureProvider<KategoriRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return KategoriRepository(db);
});

final auditRollbackServiceProvider =
    FutureProvider<AuditRollbackService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return AuditRollbackService(db);
});

final gajihanRepositoryProvider = FutureProvider<GajihanRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return GajihanRepository(db);
});

final daftarGajihanProvider =
    FutureProvider.autoDispose.family<List<GajihanModel>, int?>((ref, periodeId) async {
  final repo = await ref.watch(gajihanRepositoryProvider.future);
  return repo.getAll(periodeId: periodeId);
});

final daftarKategoriProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, tipe) async {
  final repo = await ref.watch(kategoriRepositoryProvider.future);
  return repo.getDaftarLengkap(tipe);
});

final periodeRepositoryProvider =
    FutureProvider<PeriodeRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PeriodeRepository(db);
});

final saldoRepositoryProvider = FutureProvider<SaldoRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SaldoRepository(db);
});

final auditLogRepositoryProvider =
    FutureProvider<AuditLogRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return AuditLogRepository(db);
});

final dashboardServiceProvider =
    FutureProvider<DashboardService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return DashboardService(db);
});

final laporanServiceProvider = FutureProvider<LaporanService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return LaporanService(db);
});

final pembagianLabaServiceProvider =
    FutureProvider<PembagianLabaService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PembagianLabaService(db);
});

// ==============================================================
// DATA PROVIDERS - dipakai langsung oleh UI, auto refresh lewat
// ref.invalidate(...) setelah operasi tulis (create/update/delete).
// ==============================================================

final dashboardSummaryProvider = FutureProvider.autoDispose((ref) async {
  final service = await ref.watch(dashboardServiceProvider.future);
  return service.getSummary();
});

final saldoProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(saldoRepositoryProvider.future);
  return repo.getSaldo();
});

final periodeAktifProvider =
    FutureProvider.autoDispose<PeriodeModel?>((ref) async {
  final repo = await ref.watch(periodeRepositoryProvider.future);
  return repo.getPeriodeAktif();
});

final semuaPeriodeProvider =
    FutureProvider.autoDispose<List<PeriodeModel>>((ref) async {
  final repo = await ref.watch(periodeRepositoryProvider.future);
  return repo.getAll();
});

final daftarMotorProvider =
    FutureProvider.autoDispose.family((ref, String? status) async {
  final repo = await ref.watch(motorRepositoryProvider.future);
  return repo.getAll(status: status);
});

final stokMotorTersediaProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(motorRepositoryProvider.future);
  return repo.getStokTersedia();
});

final nilaiStokMotorProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(motorRepositoryProvider.future);
  return repo.getTotalNilaiStok();
});

final riwayatBiayaMotorProvider =
    FutureProvider.autoDispose.family((ref, int motorId) async {
  final repo = await ref.watch(motorRepositoryProvider.future);
  return repo.getRiwayatBiaya(motorId);
});

final daftarPenjualanProvider =
    FutureProvider.autoDispose.family((ref, int? periodeId) async {
  final repo = await ref.watch(penjualanRepositoryProvider.future);
  return repo.getAll(periodeId: periodeId);
});

final daftarPemasukanProvider =
    FutureProvider.autoDispose.family((ref, int? periodeId) async {
  final repo = await ref.watch(pemasukanRepositoryProvider.future);
  return repo.getAll(periodeId: periodeId);
});

final daftarPengeluaranProvider =
    FutureProvider.autoDispose.family((ref, int? periodeId) async {
  final repo = await ref.watch(pengeluaranRepositoryProvider.future);
  return repo.getAll(periodeId: periodeId);
});

final daftarKasbonProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(kasbonRepositoryProvider.future);
  return repo.getAll();
});

final piutangPerKaryawanProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(kasbonRepositoryProvider.future);
  return repo.getPiutangPerKaryawan();
});

final daftarDanaTalangProvider =
    FutureProvider.autoDispose.family<List<DanaTalangModel>, String?>(
        (ref, jenis) async {
  final repo = await ref.watch(danaTalangRepositoryProvider.future);
  return repo.getAll(jenis: jenis);
});

final riwayatPembayaranDanaTalangProvider =
    FutureProvider.autoDispose.family((ref, int danaTalangId) async {
  final repo = await ref.watch(danaTalangRepositoryProvider.future);
  return repo.getRiwayatPembayaran(danaTalangId);
});

final totalPiutangPartnerProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(danaTalangRepositoryProvider.future);
  return repo.getTotalPiutangPartner();
});

final totalHutangPartnerProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(danaTalangRepositoryProvider.future);
  return repo.getTotalHutangPartner();
});

final riwayatMutasiAntarSaldoProvider = FutureProvider.autoDispose
    .family<List<MutasiAntarSaldoModel>, String?>((ref, jenis) async {
  final repo = await ref.watch(saldoRepositoryProvider.future);
  final semua = await repo.getRiwayatMutasiAntarSaldo();
  if (jenis == null) return semua;
  return semua.where((e) => e.jenis == jenis).toList();
});

final histroiCashFlowProvider = FutureProvider.autoDispose
    .family<List<CashFlowModel>, String?>((ref, sumber) async {
  final repo = await ref.watch(saldoRepositoryProvider.future);
  return repo.getHistoriCashFlow(sumber: sumber);
});

final histroiModalProvider = FutureProvider.autoDispose
    .family<List<ModalHistoryModel>, String?>((ref, jenis) async {
  final repo = await ref.watch(saldoRepositoryProvider.future);
  return repo.getHistoriModal(jenis: jenis);
});

final previewPembagianLabaProvider =
    FutureProvider.autoDispose.family((ref, int periodeId) async {
  final service = await ref.watch(pembagianLabaServiceProvider.future);
  return service.hitungPreview(periodeId);
});

final laporanPeriodeProvider =
    FutureProvider.autoDispose.family((ref, int periodeId) async {
  final service = await ref.watch(laporanServiceProvider.future);
  return service.getLaporanPeriode(periodeId);
});

final auditLogProvider =
    FutureProvider.autoDispose.family((ref, String? tabel) async {
  final repo = await ref.watch(auditLogRepositoryProvider.future);
  return repo.getAll(tabel: tabel);
});

final daftarBiayaTransferManualProvider =
    FutureProvider.autoDispose.family<List<BiayaTransferManualModel>, int?>(
        (ref, periodeId) async {
  final repo = await ref.watch(biayaTransferManualRepositoryProvider.future);
  return repo.getAll(periodeId: periodeId);
});

/// Helper untuk refresh semua data terkait setelah transaksi baru
/// (dipanggil dari screen setelah create/update berhasil).
void refreshSemuaData(WidgetRef ref) {
  ref.invalidate(dashboardSummaryProvider);
  ref.invalidate(saldoProvider);
  ref.invalidate(periodeAktifProvider);
  ref.invalidate(semuaPeriodeProvider);
  ref.invalidate(daftarMotorProvider);
  ref.invalidate(stokMotorTersediaProvider);
  ref.invalidate(daftarPenjualanProvider);
  ref.invalidate(daftarPemasukanProvider);
  ref.invalidate(daftarPengeluaranProvider);
  ref.invalidate(daftarKasbonProvider);
  ref.invalidate(piutangPerKaryawanProvider);
  ref.invalidate(histroiCashFlowProvider);
  ref.invalidate(histroiModalProvider);
  ref.invalidate(daftarDanaTalangProvider);
  ref.invalidate(riwayatPembayaranDanaTalangProvider);
  ref.invalidate(totalPiutangPartnerProvider);
  ref.invalidate(totalHutangPartnerProvider);
  ref.invalidate(riwayatMutasiAntarSaldoProvider);
  ref.invalidate(daftarKategoriProvider);
  ref.invalidate(daftarGajihanProvider);
  ref.invalidate(daftarBiayaTransferManualProvider);
}
