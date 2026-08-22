import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../models/gajihan_model.dart';
import 'audit_log_repository.dart';
import 'pengeluaran_repository.dart';
import 'kasbon_repository.dart';
import 'dana_talang_repository.dart';
import '../core/security/write_guard.dart';

/// Proses Gajihan & Tutup Buku (spesifikasi V3 #11).
///
/// Alur: gaji pokok dicatat penuh sebagai Pengeluaran kategori 'Gaji'
/// (Cash/Bank berkurang sejumlah gaji_pokok). Lalu kasbon & dana talang
/// karyawan yang BELUM LUNAS otomatis dilunasi sejumlah potongan yang
/// diminta (Cash/Bank bertambah kembali sejumlah itu, piutang company
/// ke karyawan hilang). Net efek kas = -(gaji - kasbon - dana talang),
/// persis sejumlah yang benar-benar diterima karyawan.
class GajihanRepository {
  final Database db;

  GajihanRepository(this.db);

  Future<GajihanModel> prosesGajihan({
    required String namaKaryawan,
    required DateTime tanggal,
    required double gajiPokok,
    double kasbonDipotong = 0,
    double danaTalangDipotong = 0,
    String sumber = AppConstants.sumberCash,
    String? jenisTransfer,
    String? keterangan,
    int? periodeId,
  }) async {
    requireWriteAccess();
    // CATATAN: tidak dibungkus db.transaction() di sini karena setiap
    // langkah memanggil repository lain yang SUDAH atomik sendiri lewat
    // db.transaction internal masing-masing — sqflite tidak mendukung
    // nested transaction. Setiap langkah (pengeluaran gaji, pelunasan
    // kasbon, pelunasan dana talang) tetap atomik secara individual.
    final pengeluaranRepo = PengeluaranRepository(db);
    final kasbonRepo = KasbonRepository(db);
    final danaTalangRepo = DanaTalangRepository(db);

    // 1) Gaji pokok penuh sebagai pengeluaran (Cash/Bank berkurang).
    if (gajiPokok > 0) {
      await pengeluaranRepo.tambahPengeluaran(
        tanggal: tanggal,
        kategori: AppConstants.kategoriGaji,
        nominal: gajiPokok,
        sumber: sumber,
        jenisTransfer: jenisTransfer,
        keterangan:
            'Gaji $namaKaryawan${keterangan != null ? " - $keterangan" : ""}',
        periodeId: periodeId,
      );
    }

    // 2) Lunasi kasbon karyawan ini (tertua dulu) sampai jumlah
    // potongan tercapai. Setiap kasbon yang dilunasi mengembalikan
    // Cash/Bank sesuai sumber asal kasbon tsb diambil.
    if (kasbonDipotong > 0) {
      final daftarKasbon = await kasbonRepo.getAll(
          namaKaryawan: namaKaryawan,
          status: AppConstants.statusKasbonBelumLunas);
      double sisaPotongan = kasbonDipotong;
      for (final k in daftarKasbon) {
        if (sisaPotongan <= 0) break;
        if (k.jumlah <= sisaPotongan + 0.5) {
          await kasbonRepo.bayarKasbon(k.id!, tanggalLunas: tanggal);
          sisaPotongan -= k.jumlah;
        }
      }
    }

    // 3) Lunasi dana talang (Saya Menalangi ke karyawan ini) sampai
    // jumlah potongan tercapai.
    if (danaTalangDipotong > 0) {
      final daftarTalang = await danaTalangRepo.getAll(
          jenis: AppConstants.danaTalangSayaMenalangi);
      final talangKaryawan = daftarTalang
          .where((t) => t.namaPartner == namaKaryawan && t.isAktif)
          .toList();
      double sisaPotongan = danaTalangDipotong;
      for (final t in talangKaryawan) {
        if (sisaPotongan <= 0) break;
        final bayar = t.sisa <= sisaPotongan ? t.sisa : sisaPotongan;
        if (bayar <= 0) continue;
        await danaTalangRepo.bayarKembali(
          danaTalangId: t.id!,
          tanggal: tanggal,
          nominal: bayar,
          metodePembayaran: AppConstants.metodeCash,
          cashDibayar: bayar,
        );
        sisaPotongan -= bayar;
      }
    }

    final totalDiterima = gajiPokok - kasbonDipotong - danaTalangDipotong;
    final now = DateTime.now();
    final gajihan = GajihanModel(
      namaKaryawan: namaKaryawan,
      tanggal: tanggal,
      gajiPokok: gajiPokok,
      kasbonDipotong: kasbonDipotong,
      danaTalangDipotong: danaTalangDipotong,
      totalDiterima: totalDiterima,
      sumber: sumber,
      keterangan: keterangan,
      periodeId: periodeId,
      createdAt: now,
    );
    final id = await db.insert('gajihan', gajihan.toMap());
    final saved = GajihanModel.fromMap({...gajihan.toMap(), 'id': id});

    final auditLog = AuditLogRepository(db);
    await auditLog.catatCreate(
      'gajihan',
      id,
      jsonEncode(saved.toMap()),
      keterangan:
          'Gajihan $namaKaryawan: Rp$gajiPokok - kasbon Rp$kasbonDipotong - talangan Rp$danaTalangDipotong = Rp$totalDiterima',
    );

    return saved;
  }

  /// Edit HANYA tanggal catatan gajihan (bagian dari V3.1 Patch #3).
  /// Catatan: hanya mengubah tanggal baris riwayat gajihan ini —
  /// transaksi Pengeluaran "Gaji" dan pelunasan kasbon/dana talang yang
  /// sudah tercatat terpisah harus diedit sendiri lewat menu masing-masing
  /// bila tanggalnya juga perlu disesuaikan.
  Future<void> editTanggalGajihan(int id, DateTime tanggalBaru) async {
    requireWriteAccess();
    return db.transaction<void>((txn) async {
      final result =
          await txn.query('gajihan', where: 'id = ?', whereArgs: [id]);
      if (result.isEmpty) throw ArgumentError('Data gajihan tidak ditemukan');
      final lama = GajihanModel.fromMap(result.first);
      final auditLog = AuditLogRepository(txn);

      await txn.update(
        'gajihan',
        {'tanggal': tanggalBaru.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await auditLog.catatUpdate(
        'gajihan',
        id,
        jsonEncode({'tanggal': lama.tanggal.toIso8601String()}),
        jsonEncode({'tanggal': tanggalBaru.toIso8601String()}),
        keterangan: 'Mengubah tanggal gajihan ${lama.namaKaryawan}: dari '
            '${lama.tanggal.toIso8601String().split("T").first} menjadi '
            '${tanggalBaru.toIso8601String().split("T").first}',
      );
    });
  }

  Future<List<GajihanModel>> getAll({int? periodeId}) async {    final result = await db.query(
      'gajihan',
      where: periodeId != null ? 'periode_id = ?' : null,
      whereArgs: periodeId != null ? [periodeId] : null,
      orderBy: 'tanggal DESC',
    );
    return result.map((e) => GajihanModel.fromMap(e)).toList();
  }

  /// Ringkasan kasbon & dana talang aktif seorang karyawan (dipakai UI
  /// untuk menampilkan potongan yang tersedia sebelum proses gajihan).
  Future<({double kasbon, double danaTalang})> getRingkasanPotongan(
      String namaKaryawan) async {
    final kasbonRepo = KasbonRepository(db);
    final danaTalangRepo = DanaTalangRepository(db);

    final daftarKasbon = await kasbonRepo.getAll(
        namaKaryawan: namaKaryawan,
        status: AppConstants.statusKasbonBelumLunas);
    final totalKasbon =
        daftarKasbon.fold<double>(0, (sum, k) => sum + k.jumlah);

    final daftarTalang = await danaTalangRepo.getAll(
        jenis: AppConstants.danaTalangSayaMenalangi);
    final totalTalang = daftarTalang
        .where((t) => t.namaPartner == namaKaryawan && t.isAktif)
        .fold<double>(0, (sum, t) => sum + t.sisa);

    return (kasbon: totalKasbon, danaTalang: totalTalang);
  }
}
