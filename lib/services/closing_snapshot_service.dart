import 'package:sqflite/sqflite.dart';
import '../models/closing_snapshot_model.dart';
import '../repositories/closing_snapshot_repository.dart';
import '../repositories/periode_repository.dart';
import 'financial_balance_engine.dart';
import 'laporan_service.dart';

/// V5.9 — CLOSING = RECONCILIATION + SNAPSHOT + REPORT.
///
/// "Tutup Buku" DI SINI **bukan** period lock. Ini murni:
///   1. Hitung ulang semua transaksi sampai saat ini.
///   2. Simpan hasilnya sebagai snapshot (baris baru, closing_number
///      berikutnya — TIDAK PERNAH menimpa/menghapus snapshot lama).
///   3. Kembalikan hasil untuk ditampilkan sebagai laporan closing.
///
/// TIDAK ADA baris kode di sini (atau di mana pun di V5.9) yang menolak
/// insert/update/delete transaksi karena periode "sudah closing". Periode
/// & semua transaksi di dalamnya TETAP 100% bisa diedit kapan saja —
/// kalau user mengedit transaksi lama setelah closing, `sudahBerubahSejakClosingTerakhir()`
/// di bawah ini akan mendeteksinya dan menyarankan closing baru
/// (Rekalkulasi), TANPA memblokir editnya sama sekali.
///
/// PERIOD LOCKING TIDAK DIIMPLEMENTASIKAN — sesuai instruksi eksplisit.
class ClosingSnapshotService {
  final Database db;
  late final ClosingSnapshotRepository _repo;
  late final PeriodeRepository _periodeRepo;
  late final LaporanService _laporanService;
  late final FinancialBalanceEngine _balanceEngine;

  ClosingSnapshotService(this.db) {
    _repo = ClosingSnapshotRepository(db);
    _periodeRepo = PeriodeRepository(db);
    _laporanService = LaporanService(db);
    _balanceEngine = FinancialBalanceEngine(db);
  }

  /// Hitung hasil closing TANPA menyimpan apa pun — dipakai untuk preview
  /// & untuk deteksi "ada perubahan sejak closing terakhir".
  Future<ClosingSnapshotModel> hitungPreview(int periodeId) async {
    final periode = await _periodeRepo.getById(periodeId);
    if (periode == null) {
      throw ArgumentError('Periode tidak ditemukan (id=$periodeId)');
    }
    final lap = await _laporanService.getLaporanPeriode(periodeId);
    final balance = await _balanceEngine.hitung();

    final totalModalMotor =
        lap.labaPerMotor.fold<double>(0, (s, l) => s + l.penjualan.modalMotor);
    final totalEquity = balance.modal + balance.totalLaba;
    final balanceDifference = lap.totalAset - (lap.hutangPartner + totalEquity);

    final nomor = await _repo.getNomorBerikutnya(periodeId);

    return ClosingSnapshotModel(
      periodeId: periodeId,
      closingNumber: nomor,
      periodStart: periode.tanggalMulai,
      periodEnd: periode.tanggalSelesai,
      totalModal: balance.modal,
      totalPenjualan: lap.totalPenjualan,
      totalModalMotor: totalModalMotor,
      totalBiaya: lap.totalPengeluaran,
      totalLaba: balance.totalLaba,
      cash: lap.cash,
      bank: lap.saldoBank,
      stock: lap.nilaiStok,
      piutang: lap.piutangPenjualan + lap.piutangKasbon + lap.piutangPartner,
      kasbon: lap.piutangKasbon,
      hutang: lap.hutangPartner,
      danaTalang: lap.piutangPartner - lap.hutangPartner,
      totalAsset: lap.totalAset,
      totalLiability: lap.hutangPartner,
      totalEquity: totalEquity,
      balanceDifference: balanceDifference,
      closingStatus: balanceDifference.abs() < 1 ? 'BALANCE' : 'TIDAK_BALANCE',
      createdAt: DateTime.now(),
    );
  }

  /// Jalankan closing sungguhan — simpan snapshot baru (bukan timpa).
  Future<ClosingSnapshotModel> jalankanClosing(int periodeId, {String? createdBy}) async {
    final preview = await hitungPreview(periodeId);
    return _repo.simpan(ClosingSnapshotModel(
      periodeId: preview.periodeId,
      closingNumber: preview.closingNumber,
      periodStart: preview.periodStart,
      periodEnd: preview.periodEnd,
      totalModal: preview.totalModal,
      totalPenjualan: preview.totalPenjualan,
      totalModalMotor: preview.totalModalMotor,
      totalBiaya: preview.totalBiaya,
      totalLaba: preview.totalLaba,
      cash: preview.cash,
      bank: preview.bank,
      stock: preview.stock,
      piutang: preview.piutang,
      kasbon: preview.kasbon,
      hutang: preview.hutang,
      danaTalang: preview.danaTalang,
      totalAsset: preview.totalAsset,
      totalLiability: preview.totalLiability,
      totalEquity: preview.totalEquity,
      balanceDifference: preview.balanceDifference,
      closingStatus: preview.closingStatus,
      createdAt: DateTime.now(),
      createdBy: createdBy,
    ));
  }

  /// Bandingkan closing terakhir vs kondisi sekarang. `null` = belum
  /// pernah closing sama sekali (bukan berarti "berubah").
  Future<ClosingChangeStatus> cekPerubahanSejakClosingTerakhir(int periodeId) async {
    final terakhir = await _repo.getTerakhir(periodeId);
    if (terakhir == null) {
      return ClosingChangeStatus(
        pernahClosing: false,
        berubah: false,
        closingTerakhir: null,
        nilaiTerbaru: null,
      );
    }
    final preview = await hitungPreview(periodeId);
    final berubah = (preview.totalLaba - terakhir.totalLaba).abs() >= 1 ||
        (preview.totalAsset - terakhir.totalAsset).abs() >= 1;
    return ClosingChangeStatus(
      pernahClosing: true,
      berubah: berubah,
      closingTerakhir: terakhir,
      nilaiTerbaru: preview,
    );
  }
}

class ClosingChangeStatus {
  final bool pernahClosing;
  final bool berubah;
  final ClosingSnapshotModel? closingTerakhir;
  final ClosingSnapshotModel? nilaiTerbaru;

  ClosingChangeStatus({
    required this.pernahClosing,
    required this.berubah,
    required this.closingTerakhir,
    required this.nilaiTerbaru,
  });

  double get selisihLaba =>
      (nilaiTerbaru?.totalLaba ?? 0) - (closingTerakhir?.totalLaba ?? 0);
}
