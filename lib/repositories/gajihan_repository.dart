import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../core/constants/app_constants.dart';
import '../models/gajihan_model.dart';
import '../models/kasbon_model.dart';
import '../models/dana_talang_model.dart';
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
///
/// V5.9.2 — ATOMICITY FIX (Mega Prompt Section I / Invariant 14):
/// SELURUH proses (insert Pengeluaran gaji + pelunasan kasbon + pelunasan
/// dana talang + insert baris gajihan + audit log) sekarang berjalan
/// dalam SATU `db.transaction()`. Sebelumnya 3 langkah ini masing-masing
/// membuka `db.transaction()` sendiri (karena setiap repository dipanggil
/// via `this.db`, bukan `txn` yang sama) — kalau langkah ke-2/3 gagal
/// setelah langkah 1 sukses, hasilnya adalah state SETENGAH JADI (gaji
/// sudah keluar tapi kasbon/dana talang belum ke-update) yang TIDAK bisa
/// di-rollback otomatis. Diperbaiki dengan menambahkan varian
/// `...InTxn(DatabaseExecutor txn, ...)` di [PengeluaranRepository],
/// [KasbonRepository], dan [DanaTalangRepository] yang menerima
/// transaction dari luar alih-alih membuka transaction sendiri — sqflite
/// TIDAK mendukung nested `db.transaction()`, jadi ini satu-satunya cara
/// menggabungkan beberapa repository ke dalam SATU unit atomik tanpa
/// menulis ulang seluruh repository (perubahan pada 3 repo itu murni
/// ADDITIF — method publik lama tetap ada & tidak berubah perilakunya
/// untuk semua caller lain).
class GajihanRepository {
  final Database db;

  GajihanRepository(this.db);

  /// V5.9.7 — [metodePembayaran] sekarang CASH/TRANSFER/CAMPURAN (bukan
  /// cuma CASH/BANK single choice), mengikuti pola
  /// `MetodePembayaranController`/[cashDibayar]/[transferDibayar] yang
  /// sudah dipakai di Dana Talang. Untuk CAMPURAN, gaji pokok dipecah
  /// jadi maksimal 2 baris Pengeluaran (kategori Gaji) — satu CASH, satu
  /// BANK — karena tabel `pengeluaran` sendiri per baris cuma 1 sumber
  /// (pola yang sama dipakai di seluruh app, bukan arsitektur baru).
  Future<GajihanModel> prosesGajihan({
    required String namaKaryawan,
    required DateTime tanggal,
    required double gajiPokok,
    double kasbonDipotong = 0,
    double danaTalangDipotong = 0,
    String metodePembayaran = AppConstants.metodeCash,
    double cashDibayar = 0,
    double transferDibayar = 0,
    String? jenisTransfer,
    String? keterangan,
    int? periodeId,
  }) async {
    requireWriteAccess();

    if (metodePembayaran == AppConstants.metodeCampuran &&
        gajiPokok > 0 &&
        (cashDibayar + transferDibayar - gajiPokok).abs() > 0.5) {
      throw ArgumentError(
          'Cash + Transfer (Rp${(cashDibayar + transferDibayar).toStringAsFixed(0)}) '
          'harus sama dengan Gaji Pokok (Rp${gajiPokok.toStringAsFixed(0)})');
    }
    final double cashPorsi;
    final double transferPorsi;
    switch (metodePembayaran) {
      case AppConstants.metodeTransfer:
        cashPorsi = 0;
        transferPorsi = gajiPokok;
        break;
      case AppConstants.metodeCampuran:
        cashPorsi = cashDibayar;
        transferPorsi = transferDibayar;
        break;
      case AppConstants.metodeCash:
      default:
        cashPorsi = gajiPokok;
        transferPorsi = 0;
    }

    // Baca daftar kasbon/dana talang AKTIF dulu (read-only, di luar
    // transaction, boleh — datanya cuma dipakai untuk memilih baris mana
    // yang akan dilunasi; keputusan MUTASI sungguhan semuanya terjadi di
    // dalam satu transaction di bawah).
    final kasbonRepo = KasbonRepository(db);
    final danaTalangRepo = DanaTalangRepository(db);

    // V5.9.9 — sama seperti getRingkasanPotongan: jangan hanya
    // BELUM_LUNAS, sertakan juga SEBAGIAN_LUNAS (masih ada sisa).
    // Urutkan TERTUA dulu secara eksplisit (bukan mengandalkan reversed
    // dari orderBy DESC bawaan getAll, supaya jelas & tidak rapuh).
    final daftarKasbon = kasbonDipotong > 0
        ? ((await kasbonRepo.getAll(namaKaryawan: namaKaryawan))
              .where((k) => k.isAktif)
              .toList()
            ..sort((a, b) => a.tanggal.compareTo(b.tanggal)))
        : <KasbonModel>[];
    final talangKaryawan = danaTalangDipotong > 0
        ? (await danaTalangRepo.getAll(
                jenis: AppConstants.danaTalangSayaMenalangi))
            .where((t) => t.namaPartner == namaKaryawan && t.isAktif)
            .toList()
        : <DanaTalangModel>[];

    return db.transaction<GajihanModel>((txn) async {
      // 1) Gaji pokok sebagai pengeluaran (Cash/Bank berkurang) —
      // dipecah jadi 2 baris kalau CAMPURAN.
      final pengeluaranRepo = PengeluaranRepository(db);
      if (cashPorsi > 0) {
        await pengeluaranRepo.tambahPengeluaranInTxn(
          txn,
          tanggal: tanggal,
          kategori: AppConstants.kategoriGaji,
          nominal: cashPorsi,
          sumber: AppConstants.sumberCash,
          keterangan:
              'Gaji $namaKaryawan${keterangan != null ? " - $keterangan" : ""}'
              '${metodePembayaran == AppConstants.metodeCampuran ? " (porsi cash)" : ""}',
          periodeId: periodeId,
        );
      }
      if (transferPorsi > 0) {
        await pengeluaranRepo.tambahPengeluaranInTxn(
          txn,
          tanggal: tanggal,
          kategori: AppConstants.kategoriGaji,
          nominal: transferPorsi,
          sumber: AppConstants.sumberBank,
          jenisTransfer: jenisTransfer,
          keterangan:
              'Gaji $namaKaryawan${keterangan != null ? " - $keterangan" : ""}'
              '${metodePembayaran == AppConstants.metodeCampuran ? " (porsi bank)" : ""}',
          periodeId: periodeId,
        );
      }

      // 2) Lunasi kasbon karyawan ini (tertua dulu) sampai jumlah
      // potongan tercapai. Setiap kasbon yang dilunasi/dicicil
      // mengembalikan Cash/Bank sesuai sumber asal kasbon tsb diambil.
      //
      // V5.9.9 — BUG FIX: sebelumnya kasbon HANYA dibayar kalau jumlah
      // PENUHNYA pas cukup dengan sisa potongan (`k.jumlah <=
      // sisaPotongan`) -- kasbon yang lebih BESAR dari sisa potongan
      // akan TERLEWAT SEPENUHNYA (tidak dibayar sama sekali), padahal
      // "Diterima Bersih" yang ditampilkan ke user sudah menganggap
      // potongan itu benar-benar terjadi. Akibatnya kasbon tetap
      // BELUM_LUNAS dan tetap masuk hitungan aset perusahaan walau
      // partner sudah "dipotong" gajinya untuk itu. Diperbaiki: kasbon
      // yang lebih besar dari sisa potongan sekarang DICICIL sebagian
      // (bayarSebagianKasbonInTxn) sejumlah sisa potongan yang ada,
      // bukan dilewati.
      if (kasbonDipotong > 0) {
        double sisaPotongan = kasbonDipotong;
        for (final k in daftarKasbon) {
          if (sisaPotongan <= 0) break;
          final bayar = k.sisa <= sisaPotongan ? k.sisa : sisaPotongan;
          if (bayar <= 0) continue;
          if (bayar >= k.sisa - 0.5) {
            await kasbonRepo.bayarKasbonInTxn(txn, k.id!, tanggalLunas: tanggal);
          } else {
            await kasbonRepo.bayarSebagianKasbonInTxn(txn,
                kasbonId: k.id!, nominal: bayar, tanggal: tanggal);
          }
          sisaPotongan -= bayar;
        }
      }

      // 3) Lunasi dana talang (Saya Menalangi ke karyawan ini) sampai
      // jumlah potongan tercapai.
      if (danaTalangDipotong > 0) {
        double sisaPotongan = danaTalangDipotong;
        for (final t in talangKaryawan) {
          if (sisaPotongan <= 0) break;
          final bayar = t.sisa <= sisaPotongan ? t.sisa : sisaPotongan;
          if (bayar <= 0) continue;
          await danaTalangRepo.bayarKembaliInTxn(
            txn,
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
        sumber: metodePembayaran,
        keterangan: keterangan,
        periodeId: periodeId,
        createdAt: now,
      );
      final id = await txn.insert('gajihan', gajihan.toMap());
      final saved = GajihanModel.fromMap({...gajihan.toMap(), 'id': id});

      final auditLog = AuditLogRepository(txn);
      await auditLog.catatCreate(
        'gajihan',
        id,
        jsonEncode(saved.toMap()),
        keterangan:
            'Gajihan $namaKaryawan: Rp$gajiPokok - kasbon Rp$kasbonDipotong - talangan Rp$danaTalangDipotong = Rp$totalDiterima',
      );

      return saved;
    });
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

  /// V5.9.6 — total "Gaji Pokok" yang SUDAH diambil [namaKaryawan] untuk
  /// periode [periodeId] tertentu (jumlahkan seluruh baris `gajihan`
  /// dengan periode_id tsb). Dipakai untuk:
  /// (a) GajihanScreen -- tampilkan sisa hak laba yang belum diambil.
  /// (b) PembagianLabaService.tutupBukuDanBagiLaba() -- supaya closing
  ///     TIDAK membayar dobel untuk bagian yang sudah diambil partner
  ///     sebagai "gajihan" selama periode berjalan.
  Future<double> getTotalGajiDiambilPeriode(
      String namaKaryawan, int? periodeId) async {
    if (periodeId == null) return 0;
    final result = await db.query(
      'gajihan',
      where: 'nama_karyawan = ? AND periode_id = ?',
      whereArgs: [namaKaryawan, periodeId],
    );
    return result.fold<double>(
        0, (sum, row) => sum + (row['gaji_pokok'] as num).toDouble());
  }

  /// Ringkasan kasbon & dana talang aktif seorang karyawan (dipakai UI
  /// untuk menampilkan potongan yang tersedia sebelum proses gajihan).
  Future<({double kasbon, double danaTalang})> getRingkasanPotongan(
      String namaKaryawan) async {
    final kasbonRepo = KasbonRepository(db);
    final danaTalangRepo = DanaTalangRepository(db);

    // V5.9.9 — BUG FIX: sebelumnya hanya mengambil status BELUM_LUNAS
    // dan menjumlahkan `jumlah` penuh -- kasbon yang sudah SEBAGIAN
    // dicicil (status SEBAGIAN_LUNAS) jadi hilang total dari ringkasan
    // ini walau masih ada sisa outstanding. Sekarang ambil SEMUA kasbon
    // karyawan ybs, filter aktif (BELUM_LUNAS + SEBAGIAN_LUNAS) di sisi
    // Dart, jumlahkan `sisa` (bukan `jumlah`).
    final daftarKasbon = await kasbonRepo.getAll(namaKaryawan: namaKaryawan);
    final totalKasbon = daftarKasbon
        .where((k) => k.isAktif)
        .fold<double>(0, (sum, k) => sum + k.sisa);

    final daftarTalang = await danaTalangRepo.getAll(
        jenis: AppConstants.danaTalangSayaMenalangi);
    final totalTalang = daftarTalang
        .where((t) => t.namaPartner == namaKaryawan && t.isAktif)
        .fold<double>(0, (sum, t) => sum + t.sisa);

    return (kasbon: totalKasbon, danaTalang: totalTalang);
  }
}
