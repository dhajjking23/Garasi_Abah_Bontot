import 'package:flutter_test/flutter_test.dart';
import 'package:garasi_abah_bontot/core/constants/app_constants.dart';
import 'package:garasi_abah_bontot/models/saldo_model.dart';
import 'package:garasi_abah_bontot/models/cash_flow_model.dart';
import 'package:garasi_abah_bontot/models/modal_history_model.dart';
import 'package:garasi_abah_bontot/models/kategori_custom_model.dart';
import 'package:garasi_abah_bontot/models/penjualan_pembayaran_model.dart';
import 'package:garasi_abah_bontot/models/penjualan_model.dart';
import 'package:garasi_abah_bontot/models/periode_model.dart';
import 'package:garasi_abah_bontot/models/dana_talang_model.dart';
import 'package:garasi_abah_bontot/models/gajihan_model.dart';

void main() {
  group('SaldoModel - Modal Cash/Bank split', () {
    test('modalTotal = modalCash + modalBank', () {
      final saldo = SaldoModel(
        cash: 1000,
        saldoBank: 2000,
        modalCash: 5000000,
        modalBank: 3000000,
        updatedAt: DateTime(2026, 8, 15),
      );
      expect(saldo.modalTotal, 8000000);
      expect(saldo.totalKas, 3000);
    });

    test('toMap/fromMap round-trip mempertahankan modal_cash & modal_bank', () {
      final saldo = SaldoModel(
        cash: 1000,
        saldoBank: 2000,
        modalCash: 5000000,
        modalBank: 3000000,
        updatedAt: DateTime(2026, 8, 15),
      );
      final map = saldo.toMap();
      expect(map['modal_cash'], 5000000);
      expect(map['modal_bank'], 3000000);
      expect(map['modal_total'], 8000000);

      final restored = SaldoModel.fromMap(map);
      expect(restored.modalCash, saldo.modalCash);
      expect(restored.modalBank, saldo.modalBank);
      expect(restored.modalTotal, saldo.modalTotal);
    });

    test('fromMap tetap aman jika modal_cash/modal_bank belum ada (data lama)',
        () {
      final mapLama = {
        'cash': 1000.0,
        'saldo_bank': 2000.0,
        'updated_at': DateTime(2026, 8, 15).toIso8601String(),
      };
      final saldo = SaldoModel.fromMap(mapLama);
      expect(saldo.modalCash, 0);
      expect(saldo.modalBank, 0);
    });

    test('copyWith hanya mengubah field yang diberikan', () {
      final saldo = SaldoModel(
        cash: 1000,
        saldoBank: 2000,
        modalCash: 5000,
        modalBank: 3000,
        updatedAt: DateTime(2026, 8, 15),
      );
      final baru = saldo.copyWith(modalCash: 9000);
      expect(baru.modalCash, 9000);
      expect(baru.modalBank, 3000);
      expect(baru.cash, 1000);
    });
  });

  group('CashFlowModel - sumber CASH/BANK', () {
    test('default sumber adalah CASH', () {
      final cf = CashFlowModel(
        tanggal: DateTime(2026, 8, 15),
        tipe: AppConstants.cashFlowMasuk,
        nominal: 500000,
        referensi: AppConstants.cashFlowRefDepositBank,
        saldoSetelah: 1000000,
        createdAt: DateTime(2026, 8, 15),
      );
      expect(cf.sumber, AppConstants.sumberCash);
    });

    test('toMap/fromMap round-trip mempertahankan sumber BANK', () {
      final cf = CashFlowModel(
        tanggal: DateTime(2026, 8, 15),
        tipe: AppConstants.cashFlowMasuk,
        sumber: AppConstants.sumberBank,
        nominal: 500000,
        referensi: AppConstants.cashFlowRefDepositBank,
        saldoSetelah: 1000000,
        createdAt: DateTime(2026, 8, 15),
      );
      final restored = CashFlowModel.fromMap(cf.toMap());
      expect(restored.sumber, AppConstants.sumberBank);
      expect(restored.referensi, AppConstants.cashFlowRefDepositBank);
    });
  });

  group('ModalHistoryModel', () {
    test('toMap/fromMap round-trip', () {
      final h = ModalHistoryModel(
        tanggal: DateTime(2026, 8, 15),
        jenis: AppConstants.modalJenisBank,
        aksi: AppConstants.modalAksiTambah,
        nominal: 1000000,
        saldoSebelum: 2000000,
        saldoSesudah: 3000000,
        keterangan: 'Setoran modal partner',
        createdAt: DateTime(2026, 8, 15),
      );
      final restored = ModalHistoryModel.fromMap(h.toMap());
      expect(restored.jenis, AppConstants.modalJenisBank);
      expect(restored.aksi, AppConstants.modalAksiTambah);
      expect(restored.saldoSesudah - restored.saldoSebelum, 1000000);
      expect(restored.keterangan, 'Setoran modal partner');
    });
  });

  group('KategoriCustomModel', () {
    test('toMap/fromMap round-trip', () {
      final k = KategoriCustomModel(
        tipe: AppConstants.kategoriTipePengeluaran,
        nama: 'Cuci Motor',
        createdAt: DateTime(2026, 8, 15),
      );
      final restored = KategoriCustomModel.fromMap(k.toMap());
      expect(restored.tipe, AppConstants.kategoriTipePengeluaran);
      expect(restored.nama, 'Cuci Motor');
    });
  });

  group('PenjualanModel - DP / cicilan', () {
    test('status LUNAS ketika totalDiterima >= hargaJual', () {
      final p = PenjualanModel(
        motorId: 1,
        tanggalJual: DateTime(2026, 8, 15),
        hargaJual: 10000000,
        modalMotor: 8000000,
        laba: 2000000,
        penjual: 'Abah',
        cashDiterima: 10000000,
        transferDiterima: 0,
        statusPembayaran: AppConstants.statusPembayaranLunas,
        createdAt: DateTime(2026, 8, 15),
      );
      expect(p.isLunas, true);
      expect(p.sisaPembayaran, 0);
    });

    test('DP: sisaPembayaran dihitung dari total cash+transfer diterima', () {
      final p = PenjualanModel(
        motorId: 1,
        tanggalJual: DateTime(2026, 8, 15),
        hargaJual: 10000000,
        modalMotor: 8000000,
        laba: 2000000,
        penjual: 'Iki',
        cashDiterima: 3000000,
        transferDiterima: 1000000,
        statusPembayaran: AppConstants.statusPembayaranBelumLunas,
        createdAt: DateTime(2026, 8, 15),
      );
      expect(p.isLunas, false);
      expect(p.totalDiterima, 4000000);
      expect(p.sisaPembayaran, 6000000);
    });

    test('copyWith cicilan menambah totalDiterima & mengubah status', () {
      final p = PenjualanModel(
        motorId: 1,
        tanggalJual: DateTime(2026, 8, 15),
        hargaJual: 10000000,
        modalMotor: 8000000,
        laba: 2000000,
        penjual: 'Iki',
        cashDiterima: 4000000,
        transferDiterima: 0,
        statusPembayaran: AppConstants.statusPembayaranBelumLunas,
        createdAt: DateTime(2026, 8, 15),
      );
      final setelahCicil = p.copyWith(
        cashDiterima: p.cashDiterima + 6000000,
        statusPembayaran: AppConstants.statusPembayaranLunas,
      );
      expect(setelahCicil.totalDiterima, 10000000);
      expect(setelahCicil.isLunas, true);
      expect(setelahCicil.sisaPembayaran, 0);
    });
  });

  group('PenjualanPembayaranModel', () {
    test('toMap/fromMap round-trip', () {
      final bayar = PenjualanPembayaranModel(
        penjualanId: 5,
        tanggal: DateTime(2026, 8, 15),
        nominal: 2000000,
        metodePembayaran: AppConstants.metodeCampuran,
        cashTerpakai: 1000000,
        transferTerpakai: 1000000,
        keterangan: 'Cicilan ke-1',
        createdAt: DateTime(2026, 8, 15),
      );
      final restored = PenjualanPembayaranModel.fromMap(bayar.toMap());
      expect(restored.penjualanId, 5);
      expect(restored.cashTerpakai + restored.transferTerpakai, 2000000);
      expect(restored.keterangan, 'Cicilan ke-1');
    });
  });

  group('PeriodeModel - Modal Awal snapshot (V3 #1/#2)', () {
    test('modalAwal = modalAwalCash + modalAwalBank, tidak berubah oleh transaksi', () {
      final p = PeriodeModel(
        namaPeriode: 'Periode Test',
        tanggalMulai: DateTime(2026, 8, 1),
        modalAwalCash: 50000000,
        modalAwalBank: 50000000,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );
      expect(p.modalAwal, 100000000);
    });

    test('fromMap fallback ke modal_awal lama jika modal_awal_cash belum ada', () {
      final mapLama = {
        'nama_periode': 'Periode Lama',
        'tanggal_mulai': DateTime(2026, 1, 1).toIso8601String(),
        'status': AppConstants.statusPeriodeAktif,
        'modal_awal': 75000000.0,
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      };
      final p = PeriodeModel.fromMap(mapLama);
      expect(p.modalAwalCash, 75000000);
      expect(p.modalAwalBank, 0);
      expect(p.modalAwal, 75000000);
    });
  });

  group('DanaTalangModel - bentuk Tunai/Non-Tunai (V3 #8B)', () {
    test('default bentukTalangan adalah TUNAI', () {
      final t = DanaTalangModel(
        namaPartner: 'Iki',
        tanggal: DateTime(2026, 8, 15),
        jenis: AppConstants.danaTalangSayaMenerima,
        nominal: 5000000,
        cashTerpakai: 5000000,
        createdAt: DateTime(2026, 8, 15),
        updatedAt: DateTime(2026, 8, 15),
      );
      expect(t.bentukTalangan, AppConstants.bentukTalanganTunai);
      expect(t.isNonTunai, false);
    });

    test('non-tunai: cashTerpakai/transferTerpakai tetap 0 (tidak ada uang masuk)', () {
      final t = DanaTalangModel(
        namaPartner: 'Andri',
        tanggal: DateTime(2026, 8, 15),
        jenis: AppConstants.danaTalangSayaMenerima,
        nominal: 3000000,
        bentukTalangan: AppConstants.bentukTalanganNonTunai,
        cashTerpakai: 0,
        transferTerpakai: 0,
        createdAt: DateTime(2026, 8, 15),
        updatedAt: DateTime(2026, 8, 15),
      );
      expect(t.isNonTunai, true);
      expect(t.cashTerpakai, 0);
      expect(t.transferTerpakai, 0);
      expect(t.sisa, 3000000);
    });
  });

  group('GajihanModel - potongan kasbon & dana talang (V3 #11)', () {
    test('totalDiterima = gajiPokok - kasbonDipotong - danaTalangDipotong', () {
      final g = GajihanModel(
        namaKaryawan: 'Ilham',
        tanggal: DateTime(2026, 8, 15),
        gajiPokok: 5000000,
        kasbonDipotong: 500000,
        danaTalangDipotong: 1000000,
        totalDiterima: 3500000,
        createdAt: DateTime(2026, 8, 15),
      );
      expect(g.totalDiterima, g.gajiPokok - g.kasbonDipotong - g.danaTalangDipotong);
    });

    test('toMap/fromMap round-trip', () {
      final g = GajihanModel(
        namaKaryawan: 'Andri',
        tanggal: DateTime(2026, 8, 15),
        gajiPokok: 4000000,
        kasbonDipotong: 200000,
        totalDiterima: 3800000,
        sumber: AppConstants.sumberBank,
        createdAt: DateTime(2026, 8, 15),
      );
      final restored = GajihanModel.fromMap(g.toMap());
      expect(restored.namaKaryawan, 'Andri');
      expect(restored.sumber, AppConstants.sumberBank);
      expect(restored.totalDiterima, 3800000);
    });
  });
}
