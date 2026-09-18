// Test P0-2 — Dana Talang -> CAPITAL CONVERSION.
//
// Menguji DanaTalangRepository.konversiKeModal() dan interaksinya dengan
// bayarKembali()/hapusDanaTalang(), SaldoRepository.ubahModal(), dan
// getTotalHutangPartner(). Mengikuti pola setup DB yang sama dengan
// test/widget_test.dart (sqflite_common_ffi + fake path_provider), tapi
// di sini langsung memanggil repository (bukan widget) supaya cepat &
// tidak butuh render UI.
//
// Setiap test memakai temp dir + DB file BARU (lihat setUp/tearDown) agar
// tidak ada kontaminasi saldo/ID antar test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:garasi_abah_bontot/core/constants/app_constants.dart';
import 'package:garasi_abah_bontot/core/database/database_helper.dart';
import 'package:garasi_abah_bontot/models/user_model.dart';
import 'package:garasi_abah_bontot/repositories/dana_talang_repository.dart';
import 'package:garasi_abah_bontot/repositories/saldo_repository.dart';
import 'package:garasi_abah_bontot/repositories/audit_log_repository.dart';
import 'package:garasi_abah_bontot/services/auth_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._dir);
  final Directory _dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

void main() {
  late Directory tempDir;
  late Database db;
  late DanaTalangRepository danaTalangRepo;
  late SaldoRepository saldoRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('garasi_konversi_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);

    db = await DatabaseHelper.instance.database;
    danaTalangRepo = DanaTalangRepository(db);
    saldoRepo = SaldoRepository(db);

    // Login sebagai OWNER_ADMIN palsu supaya requireWriteAccess() lolos,
    // tanpa perlu lewat alur login UI/hash password sungguhan.
    AuthService.instance.restoreSession(UserModel(
      id: 1,
      nama: 'Test Owner',
      username: 'test_owner',
      passwordHash: 'x',
      role: 'OWNER_ADMIN',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  });

  tearDown(() async {
    AuthService.instance.logout();
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper: buat dana talang SAYA_MENERIMA (hutang perusahaan ke
  /// partner) sejumlah [nominal], full cash (kondisi paling umum untuk
  /// kasus "Abah memberi dana talang").
  Future<int> buatDanaTalangMenerima(String nama, double nominal) async {
    final talang = await danaTalangRepo.tambahDanaTalang(
      namaPartner: nama,
      tanggal: DateTime(2026, 1, 10),
      jenis: AppConstants.danaTalangSayaMenerima,
      nominal: nominal,
    );
    return talang.id!;
  }

  group('P0-2 Dana Talang -> Capital Conversion', () {
    test('A. Full conversion: liability -10jt, modal +10jt, cash/bank tetap',
        () async {
      final id = await buatDanaTalangMenerima('Abah', 10000000);
      final saldoSebelum = await saldoRepo.getSaldo();

      final hasil = await danaTalangRepo.konversiKeModal(
        danaTalangId: id,
        nominal: 10000000,
      );

      final saldoSesudah = await saldoRepo.getSaldo();

      expect(hasil.sisa, 0);
      expect(hasil.status, AppConstants.statusDanaTalangDikonversiModal);
      expect(hasil.totalDikonversiModal, 10000000);
      expect(saldoSesudah.modalCash - saldoSebelum.modalCash, 10000000);
      expect(saldoSesudah.cash, saldoSebelum.cash); // TIDAK BERUBAH
      expect(saldoSesudah.saldoBank, saldoSebelum.saldoBank); // TIDAK BERUBAH

      final hutang = await danaTalangRepo.getTotalHutangPartner();
      expect(hutang, 0); // sudah bukan liability lagi
    });

    test('B. Partial conversion: liability -4jt, modal +4jt, sisa 6jt',
        () async {
      final id = await buatDanaTalangMenerima('Abah', 10000000);
      final saldoSebelum = await saldoRepo.getSaldo();

      final hasil = await danaTalangRepo.konversiKeModal(
        danaTalangId: id,
        nominal: 4000000,
      );

      final saldoSesudah = await saldoRepo.getSaldo();

      expect(hasil.sisa, 6000000);
      expect(hasil.status, AppConstants.statusDanaTalangSebagianDikonversi);
      expect(saldoSesudah.modalCash - saldoSebelum.modalCash, 4000000);
      expect(saldoSesudah.cash, saldoSebelum.cash);
      expect(saldoSesudah.saldoBank, saldoSebelum.saldoBank);

      final hutang = await danaTalangRepo.getTotalHutangPartner();
      expect(hutang, 6000000); // sisa outstanding tetap terhitung
    });

    test(
        'C. Mixed settlement: bayar cash 2jt + konversi 3jt -> sisa 5jt, '
        'cash turun HANYA 2jt', () async {
      final id = await buatDanaTalangMenerima('Iki', 10000000);
      final saldoAwal = await saldoRepo.getSaldo();

      await danaTalangRepo.bayarKembali(
        danaTalangId: id,
        tanggal: DateTime(2026, 2, 1),
        nominal: 2000000,
      );
      final hasil = await danaTalangRepo.konversiKeModal(
        danaTalangId: id,
        nominal: 3000000,
      );

      final saldoAkhir = await saldoRepo.getSaldo();

      // Invariant: nominal = dibayar + dikonversi + sisa
      expect(
        hasil.totalDibayarKembali + hasil.totalDikonversiModal + hasil.sisa,
        hasil.nominal,
      );
      expect(hasil.sisa, 5000000);
      expect(hasil.status, AppConstants.statusDanaTalangSebagianLunas);
      expect(saldoAwal.cash - saldoAkhir.cash, 2000000); // HANYA 2jt
      expect(saldoAkhir.modalCash - saldoAwal.modalCash, 3000000);

      final hutang = await danaTalangRepo.getTotalHutangPartner();
      expect(hutang, 5000000);
    });

    test('D. Insufficient/over conversion ditolak, tidak ada mutasi',
        () async {
      final id = await buatDanaTalangMenerima('Andri', 10000000);
      final saldoSebelum = await saldoRepo.getSaldo();

      await expectLater(
        danaTalangRepo.konversiKeModal(danaTalangId: id, nominal: 15000000),
        throwsArgumentError,
      );

      final saldoSesudah = await saldoRepo.getSaldo();
      expect(saldoSesudah.modalCash, saldoSebelum.modalCash);

      final riwayat = await danaTalangRepo.getRiwayatPembayaran(id);
      expect(riwayat, isEmpty); // tidak ada baris payment/konversi tercipta
    });

    test(
        'E. Atomic rollback: kegagalan di tengah proses tidak meninggalkan '
        'state parsial', () async {
      final id = await buatDanaTalangMenerima('Ilham', 10000000);
      final saldoSebelum = await saldoRepo.getSaldo();

      // Simulasikan "kegagalan di tengah transaction" dengan memaksa
      // exception SETELAH mutasi pertama (insert payment) tapi SEBELUM
      // ubahModal() selesai — meniru pola yang sudah dipakai
      // konversiKeModal() sendiri: satu db.transaction, jadi exception
      // apa pun di dalamnya (termasuk yang kita picu manual di sini
      // lewat nominal tidak valid pada langkah ubahModal) membatalkan
      // SELURUH transaction, bukan cuma langkah terakhir.
      //
      // Di sini kita uji lewat jalur yang sudah ada di kode produksi:
      // ubahModal() melempar ArgumentError kalau nominal <= 0. Kita tidak
      // bisa memanggil nominal <=0 lewat konversiKeModal (sudah divalidasi
      // lebih awal), jadi kita reproduksi skenario "gagal di tengah" pada
      // level yang sama (satu db.transaction, mutasi pertama sudah
      // terjadi, mutasi kedua gagal) langsung lewat SaldoRepository +
      // DanaTalangRepository di dalam satu transaction manual, meniru
      // struktur konversiKeModal().
      try {
        await db.transaction((txn) async {
          final saldoRepoTxn = SaldoRepository(txn);
          final auditTxn = AuditLogRepository(txn);
          // langkah 1: mutasi yang valid (analog insert payment history)
          await auditTxn.catatCreate('dana_talang', id, '{}',
              keterangan: 'simulasi langkah 1 sebelum gagal');
          // langkah 2: mutasi yang sengaja gagal (analog ubahModal gagal)
          await saldoRepoTxn.ubahModal(
            jenis: AppConstants.modalJenisCash,
            aksi: AppConstants.modalAksiTambah,
            nominal: -1, // tidak valid -> throw ArgumentError
          );
        });
        fail('Seharusnya melempar exception');
      } catch (_) {
        // expected
      }

      final saldoSesudah = await saldoRepo.getSaldo();
      final talangSesudah = (await danaTalangRepo.getAll())
          .firstWhere((t) => t.id == id);

      // Rollback total: modal TIDAK berubah, dana_talang TIDAK berubah.
      expect(saldoSesudah.modalCash, saldoSebelum.modalCash);
      expect(talangSesudah.totalDikonversiModal, 0);
      expect(talangSesudah.status, AppConstants.statusDanaTalangBelumLunas);

      final auditRows =
          await AuditLogRepository(db).getAll(tabel: 'dana_talang');
      // Baris audit simulasi langkah 1 juga IKUT ROLLBACK (bukti bahwa
      // db.transaction Sqflite benar-benar all-or-nothing).
      expect(
        auditRows.where((a) => a.keterangan == 'simulasi langkah 1 sebelum gagal'),
        isEmpty,
      );
    });

    test('F. Double conversion protection: konversi penuh lalu konversi lagi ditolak',
        () async {
      final id = await buatDanaTalangMenerima('Abah', 10000000);
      await danaTalangRepo.konversiKeModal(danaTalangId: id, nominal: 10000000);
      final saldoSebelum = await saldoRepo.getSaldo();

      await expectLater(
        danaTalangRepo.konversiKeModal(danaTalangId: id, nominal: 1000000),
        throwsStateError, // isAktif == false -> StateError
      );

      final saldoSesudah = await saldoRepo.getSaldo();
      expect(saldoSesudah.modalCash, saldoSebelum.modalCash); // tidak nambah lagi
    });

    test('G. Accounting invariant assets == liabilities + equity terjaga',
        () async {
      // Skenario gabungan meniru contoh di Spec: dana talang 10jt,
      // sebagian dibayar cash, sebagian dikonversi.
      final id = await buatDanaTalangMenerima('Abah', 10000000);
      await danaTalangRepo.bayarKembali(
        danaTalangId: id,
        tanggal: DateTime(2026, 3, 1),
        nominal: 2000000,
      );
      await danaTalangRepo.konversiKeModal(danaTalangId: id, nominal: 3000000);

      final saldo = await saldoRepo.getSaldo();
      final hutangPartner = await danaTalangRepo.getTotalHutangPartner();

      // ASET (yang relevan disentuh test ini): Cash + Bank.
      // LIABILITY: hutang partner (dana talang, sisa outstanding).
      // EQUITY: modal (cash+bank).
      //
      // Delta murni dari skenario ini (mulai dari 0, DB baru per test):
      //   Cash awal (dari tambahDanaTalang SAYA_MENERIMA 10jt): +10.000.000
      //   Cash setelah bayar kembali 2jt: -2.000.000 -> Cash = 8.000.000
      //   Modal setelah konversi 3jt: +3.000.000
      //   Hutang partner tersisa: 10jt - 2jt - 3jt = 5.000.000
      //
      // ASET (cash) harus == LIABILITY (hutang) + EQUITY (modal) - PIUTANG
      // AWAL, karena dana talang SAYA_MENERIMA meng-inflate Cash sekaligus
      // Liability sejak awal (double entry standar): Cash 10jt == Hutang
      // 10jt saat baru dibuat. Setelah aktivitas ini:
      //   Cash 8jt vs (Hutang 5jt + Modal 3jt) = 8jt. BALANCE.
      expect(saldo.cash, 8000000);
      expect(hutangPartner, 5000000);
      expect(saldo.modalCash, 3000000);
      expect(saldo.cash, hutangPartner + saldo.modalCash);
    });
  });

  group('P0-2 Rollback via hapusDanaTalang', () {
    test(
        'Hapus dana talang yang sebagian dikonversi -> modal kembali, '
        'cash tetap unchanged untuk bagian konversi', () async {
      final id = await buatDanaTalangMenerima('Abah', 10000000);
      // Cash sekarang +10jt (dari penerimaan dana talang).
      await danaTalangRepo.konversiKeModal(danaTalangId: id, nominal: 4000000);
      final saldoSebelumHapus = await saldoRepo.getSaldo();
      expect(saldoSebelumHapus.modalCash, 4000000);

      await danaTalangRepo.hapusDanaTalang(id);

      final saldoSesudahHapus = await saldoRepo.getSaldo();
      // Modal kembali ke 0 (reversal konversi 4jt).
      expect(saldoSesudahHapus.modalCash, 0);
      // Cash juga kembali ke 0 (reversal transaksi ASLI dana talang 10jt
      // — ini reversal terpisah dari reversal konversi, bukan double
      // reversal, lihat audit §4 di laporan).
      expect(saldoSesudahHapus.cash, 0);

      final hutang = await danaTalangRepo.getTotalHutangPartner();
      expect(hutang, 0);
    });
  });
}
