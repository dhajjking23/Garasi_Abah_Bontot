import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../models/pembagian_laba_model.dart';
import '../models/penjualan_model.dart';
import '../repositories/penjualan_repository.dart';
import '../repositories/pengeluaran_repository.dart';
import '../repositories/periode_repository.dart';
import '../repositories/audit_log_repository.dart';
import '../core/security/write_guard.dart';

/// Hasil preview perhitungan laba sebelum benar-benar disimpan/tutup buku.
/// Dipakai UI untuk menampilkan preview di layar "Pembukuan" / "Laporan"
/// sebelum user menekan tombol "Tutup Buku & Bagi Laba".
class PreviewPembagianLaba {
  final double totalLabaMotor;
  final double totalPengeluaranLain;
  final double labaBersih;
  final double bagianAbah;
  final double bagianIki;
  final double bagianAndri;
  final double bagianIlham;
  final double totalHadiahPenjualan;
  final int unitInternalTerjual;
  final double bonusPerUnit;
  final List<DetailBonusPenjual> detailBonus;

  PreviewPembagianLaba({
    required this.totalLabaMotor,
    required this.totalPengeluaranLain,
    required this.labaBersih,
    required this.bagianAbah,
    required this.bagianIki,
    required this.bagianAndri,
    required this.bagianIlham,
    required this.totalHadiahPenjualan,
    required this.unitInternalTerjual,
    required this.bonusPerUnit,
    required this.detailBonus,
  });
}

/// Service yang mengimplementasikan logika bisnis inti dari brief:
///
///   Laba motor        = harga_jual - modal_motor
///   Laba bersih periode = total_laba_motor - total_pengeluaran_lain
///   Pembagian 100% laba bersih:
///     Abah 25% | Iki 27.5% | Andri 22.5% | Ilham 15% | Hadiah Penjualan 10%
///   Hadiah penjualan (10% dari laba bersih) dibagi rata ke jumlah unit
///   INTERNAL yang terjual (Calo dikecualikan / bonus_eligible = false).
///   bonus/unit = total_hadiah / unit_internal_terjual
///   bonus milik seseorang = bonus/unit * jumlah unit yang dia jual
class PembagianLabaService {
  final Database db;
  final PenjualanRepository _penjualanRepo;
  final PengeluaranRepository _pengeluaranRepo;
  final PeriodeRepository _periodeRepo;

  PembagianLabaService(this.db)
      : _penjualanRepo = PenjualanRepository(db),
        _pengeluaranRepo = PengeluaranRepository(db),
        _periodeRepo = PeriodeRepository(db);

  /// Menghitung preview pembagian laba untuk sebuah periode TANPA
  /// menyimpan apapun ke database. Aman dipanggil berulang kali,
  /// misal untuk ditampilkan real-time di layar Laporan.
  Future<PreviewPembagianLaba> hitungPreview(int periodeId) async {
    final List<PenjualanModel> semuaPenjualan =
        await _penjualanRepo.getAll(periodeId: periodeId);

    final totalLabaMotor =
        semuaPenjualan.fold<double>(0, (sum, p) => sum + p.laba);

    final totalPengeluaranLain =
        await _pengeluaranRepo.getTotalPengeluaranLain(periodeId: periodeId);

    final labaBersih = totalLabaMotor - totalPengeluaranLain;

    // Pembagian 4 pemilik berdasarkan persentase tetap dari AppConstants
    final bagianAbah = labaBersih * AppConstants.persenAbah;
    final bagianIki = labaBersih * AppConstants.persenIki;
    final bagianAndri = labaBersih * AppConstants.persenAndri;
    final bagianIlham = labaBersih * AppConstants.persenIlham;
    final totalHadiahPenjualan = labaBersih * AppConstants.persenHadiahPenjualan;

    // Hitung unit internal terjual (bonus_eligible == true, Calo dikecualikan)
    final penjualanInternal =
        semuaPenjualan.where((p) => p.bonusEligible).toList();
    final unitInternalTerjual = penjualanInternal.length;

    final bonusPerUnit = unitInternalTerjual > 0
        ? totalHadiahPenjualan / unitInternalTerjual
        : 0.0;

    // Rekap jumlah unit per penjual internal
    final Map<String, int> unitPerPenjual = {};
    for (final p in penjualanInternal) {
      unitPerPenjual[p.penjual] = (unitPerPenjual[p.penjual] ?? 0) + 1;
    }

    final detailBonus = unitPerPenjual.entries
        .map((e) => DetailBonusPenjual(
              nama: e.key,
              jumlahUnit: e.value,
              totalBonus: bonusPerUnit * e.value,
            ))
        .toList()
      ..sort((a, b) => b.totalBonus.compareTo(a.totalBonus));

    return PreviewPembagianLaba(
      totalLabaMotor: totalLabaMotor,
      totalPengeluaranLain: totalPengeluaranLain,
      labaBersih: labaBersih,
      bagianAbah: bagianAbah,
      bagianIki: bagianIki,
      bagianAndri: bagianAndri,
      bagianIlham: bagianIlham,
      totalHadiahPenjualan: totalHadiahPenjualan,
      unitInternalTerjual: unitInternalTerjual,
      bonusPerUnit: bonusPerUnit,
      detailBonus: detailBonus,
    );
  }

  /// Tutup buku periode: hitung ulang final, simpan hasil ke tabel
  /// pembagian_laba, dan ubah status periode menjadi TUTUP.
  /// Operasi ini permanen — hasil tersimpan sebagai histori tetap
  /// walau periode baru dibuat sesudahnya.
  Future<PembagianLabaModel> tutupBukuDanBagiLaba(int periodeId) async {
    requireWriteAccess();
    final periode = await _periodeRepo.getById(periodeId);
    if (periode == null) throw ArgumentError('Periode tidak ditemukan');
    if (!periode.isAktif) {
      throw StateError('Periode ini sudah ditutup sebelumnya.');
    }

    final preview = await hitungPreview(periodeId);

    return db.transaction<PembagianLabaModel>((txn) async {
      final auditLog = AuditLogRepository(txn);
      final now = DateTime.now();

      final hasil = PembagianLabaModel(
        periodeId: periodeId,
        labaBersih: preview.labaBersih,
        bagianAbah: preview.bagianAbah,
        bagianIki: preview.bagianIki,
        bagianAndri: preview.bagianAndri,
        bagianIlham: preview.bagianIlham,
        totalHadiahPenjualan: preview.totalHadiahPenjualan,
        unitInternalTerjual: preview.unitInternalTerjual,
        bonusPerUnit: preview.bonusPerUnit,
        detailBonus: preview.detailBonus,
        createdAt: now,
      );

      final id = await txn.insert('pembagian_laba', hasil.toMap());
      final saved = PembagianLabaModel.fromMap({...hasil.toMap(), 'id': id});

      await auditLog.catatCreate(
        'pembagian_laba',
        id,
        jsonEncode(saved.toMap()),
        keterangan: 'Tutup buku periode "${periode.namaPeriode}"',
      );

      // Update status periode -> TUTUP
      final periodeLamaMap = periode.toMap();
      final periodeBaru = periode.copyWith(
        status: AppConstants.statusPeriodeTutup,
        tanggalSelesai: now,
        updatedAt: now,
      );
      await txn.update('periode', periodeBaru.toMap(),
          where: 'id = ?', whereArgs: [periodeId]);
      await auditLog.catatUpdate(
        'periode',
        periodeId,
        jsonEncode(periodeLamaMap),
        jsonEncode(periodeBaru.toMap()),
        keterangan: 'Tutup buku & pembagian laba',
      );

      return saved;
    });
  }

  Future<PembagianLabaModel?> getHasilByPeriode(int periodeId) async {
    final result = await db.query(
      'pembagian_laba',
      where: 'periode_id = ?',
      whereArgs: [periodeId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return PembagianLabaModel.fromMap(result.first);
  }

  Future<List<PembagianLabaModel>> getSemuaHistori() async {
    final result =
        await db.query('pembagian_laba', orderBy: 'created_at DESC');
    return result.map((e) => PembagianLabaModel.fromMap(e)).toList();
  }
}
