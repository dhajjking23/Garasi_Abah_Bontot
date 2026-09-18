import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_helper.dart';
import '../repositories/motor_repository.dart';
import '../models/motor_model.dart';
import '../repositories/penjualan_repository.dart';
import '../repositories/pemasukan_repository.dart';
import '../repositories/pengeluaran_repository.dart';
import '../repositories/kasbon_repository.dart';
import '../repositories/karyawan_repository.dart';
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
import '../services/partner_settlement_service.dart';
import '../services/biaya_transfer_detail_service.dart';
import '../services/financial_balance_engine.dart';
import '../services/period_opening_service.dart';
import '../services/closing_snapshot_service.dart';
import '../repositories/closing_snapshot_repository.dart';
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

final karyawanRepositoryProvider =
    FutureProvider<KaryawanRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return KaryawanRepository(db);
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

/// V5.8 — Partner Net Settlement Engine.
final partnerSettlementServiceProvider =
    FutureProvider<PartnerSettlementService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PartnerSettlementService(db);
});

/// V5.8 — rincian per-transaksi biaya transfer dari semua sumber.
final biayaTransferDetailServiceProvider =
    FutureProvider<BiayaTransferDetailService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return BiayaTransferDetailService(db);
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

/// V5.5 — lookup 1 motor by id, dipakai untuk tampilkan plat nomor/detail
/// motor di kartu Penjualan (join ringan, tidak mengubah query utama).
final motorByIdProvider =
    FutureProvider.autoDispose.family<MotorModel?, int>((ref, id) async {
  final repo = await ref.watch(motorRepositoryProvider.future);
  return repo.getById(id);
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

/// V5.5 — hubungan talangan per-partner (Perusahaan/Abah/dst).
final hubunganPartnerProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(danaTalangRepositoryProvider.future);
  return repo.getHubunganPerPartner();
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

/// V5.9.6 — Total yang akan BENAR-BENAR dibayar cash/bank saat "Tutup
/// Buku" ditekan sekarang, yaitu sisa bagian tiap partner SETELAH
/// dikurangi yang sudah mereka ambil lewat Gajihan periode ini, plus
/// bonus penjualan. Dipakai dialog konfirmasi supaya angka yang
/// ditampilkan SAMA PERSIS dengan yang akan dieksekusi
/// `tutupBukuDanBagiLaba()` (bukan angka kotor yang menyesatkan).
final totalNetTutupBukuProvider =
    FutureProvider.autoDispose.family((ref, int periodeId) async {
  final service = await ref.watch(pembagianLabaServiceProvider.future);
  final preview = await service.hitungPreview(periodeId);
  if (preview.labaBersih <= 0) return 0.0;
  double total = preview.totalHadiahPenjualan;
  for (final nama in AppConstants.karyawanDefault) {
    total += await service.sisaHakLabaPartner(nama, periodeId);
  }
  return total;
});

/// V5.8 — net settlement per partner (hak laba dipotong kasbon & dana
/// talang belum lunas).
final partnerNetSettlementProvider =
    FutureProvider.autoDispose.family((ref, int periodeId) async {
  final service = await ref.watch(partnerSettlementServiceProvider.future);
  return service.hitungNetSettlement(periodeId);
});

/// V5.8 — rincian biaya transfer per transaksi (periodeId null = semua).
final biayaTransferDetailProvider =
    FutureProvider.autoDispose.family((ref, int? periodeId) async {
  final service = await ref.watch(biayaTransferDetailServiceProvider.future);
  return service.getDetail(periodeId: periodeId);
});

/// V5.9 — Financial Balance Engine.
final financialBalanceEngineProvider =
    FutureProvider<FinancialBalanceEngine>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FinancialBalanceEngine(db);
});

/// V5.9.4 — Buka periode baru dengan carry-forward dari closing.
final periodOpeningServiceProvider =
    FutureProvider<PeriodOpeningService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PeriodOpeningService(db);
});

/// V5.9.4 — riwayat periode + status, dipakai BuatPeriodeScreen untuk
/// mendeteksi apakah ini periode PERTAMA (butuh input modal manual) atau
/// LANJUTAN (carry-forward dari closing sebelumnya).
final adaPeriodeSebelumnyaProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(periodeRepositoryProvider.future);
  final semua = await repo.getAll();
  return semua.isNotEmpty;
});

final financialBalanceReportProvider = FutureProvider.autoDispose((ref) async {
  final engine = await ref.watch(financialBalanceEngineProvider.future);
  return engine.hitung();
});

/// V5.9 — Closing Snapshot Service (BUKAN lock).
final closingSnapshotServiceProvider =
    FutureProvider<ClosingSnapshotService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ClosingSnapshotService(db);
});

final closingSnapshotRepositoryProvider =
    FutureProvider<ClosingSnapshotRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ClosingSnapshotRepository(db);
});

final riwayatClosingProvider =
    FutureProvider.autoDispose.family((ref, int periodeId) async {
  final repo = await ref.watch(closingSnapshotRepositoryProvider.future);
  return repo.getRiwayat(periodeId: periodeId);
});

final closingChangeStatusProvider =
    FutureProvider.autoDispose.family((ref, int periodeId) async {
  final service = await ref.watch(closingSnapshotServiceProvider.future);
  return service.cekPerubahanSejakClosingTerakhir(periodeId);
});

final laporanPeriodeProvider =
    FutureProvider.autoDispose.family((ref, int periodeId) async {
  final service = await ref.watch(laporanServiceProvider.future);
  return service.getLaporanPeriode(periodeId);
});

/// V5.5 — riwayat cash_flow (perubahan saldo), dipakai layar detail "Total
/// Aset" di Dashboard. Ambil dari SaldoRepository yang sudah ada, tidak
/// menambah query/tabel baru.
final riwayatCashFlowProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(saldoRepositoryProvider.future);
  return repo.getHistoriCashFlow();
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
  ref.invalidate(hubunganPartnerProvider);
  ref.invalidate(riwayatMutasiAntarSaldoProvider);
  ref.invalidate(daftarKategoriProvider);
  ref.invalidate(daftarGajihanProvider);
  ref.invalidate(daftarBiayaTransferManualProvider);
}
