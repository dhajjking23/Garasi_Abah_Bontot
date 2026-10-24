import 'package:flutter_test/flutter_test.dart';
import 'package:garasi_abah_bontot/models/pemasukan_model.dart';
import 'package:garasi_abah_bontot/models/penjualan_model.dart';
import 'package:garasi_abah_bontot/models/periode_model.dart';
import 'package:garasi_abah_bontot/services/financial_indicators.dart';

PeriodeModel periode({
  double cash = 0,
  double bank = 0,
  double totalAset = 0,
}) {
  final t = DateTime(2026, 10, 1);
  return PeriodeModel(
    id: 1,
    namaPeriode: 'Uji',
    tanggalMulai: t,
    modalAwalCash: cash,
    modalAwalBank: bank,
    modalAwalTotalAset: totalAset,
    createdAt: t,
    updatedAt: t,
  );
}

PemasukanModel pemasukan(String kategori, double nominal,
    {int? id, int? ref, DateTime? tanggal}) {
  final t = tanggal ?? DateTime(2026, 10, 5);
  return PemasukanModel(
    id: id,
    tanggal: t,
    kategori: kategori,
    nominal: nominal,
    referensiId: ref,
    createdAt: t,
  );
}

PenjualanModel penjualan(int id, double hargaJual, {DateTime? tanggal}) {
  final t = tanggal ?? DateTime(2026, 10, 5);
  return PenjualanModel(
    id: id,
    motorId: id,
    tanggalJual: t,
    hargaJual: hargaJual,
    modalMotor: hargaJual - 1000000,
    laba: 1000000,
    penjual: 'Abah',
    createdAt: t,
  );
}

void main() {
  // Angka dari layar "Rangkuman Total Aset" — HANYA data uji.
  const cash = 1401500.0,
      bank = 10903600.0,
      stok = 43830000.0,
      kasbon = 682000.0,
      piutangJual = 0.0,
      piutangPartner = 1570000.0,
      utangPartner = 5500000.0,
      modalAcuan = 52200000.0;
  const totalAset = cash + bank + stok + kasbon + piutangJual + piutangPartner;

  group('Kasus screenshot', () {
    final ind = IndikatorAset(
      totalAset: totalAset,
      totalKewajiban: utangPartner,
      modalAcuan: const ModalAcuan(modalAcuan, 'uji'),
    );

    test('total aset = 58.387.100', () => expect(totalAset, 58387100));
    test('total kewajiban = 5.500.000',
        () => expect(ind.totalKewajiban, 5500000));
    test('aset bersih = 52.887.100', () => expect(ind.asetBersih, 52887100));
    test('selisih aset bersih vs modal acuan = +687.100',
        () => expect(ind.selisihAsetBersihVsModal, 687100));
    test('selisih total aset vs modal acuan = +6.187.100',
        () => expect(ind.selisihTotalAsetVsModal, 6187100));
    test('selisih TIDAK sama dengan total aset', () {
      expect(ind.selisihAsetBersihVsModal, isNot(totalAset));
      expect(ind.selisihTotalAsetVsModal, isNot(totalAset));
    });
  });

  group('Modal acuan', () {
    test('periode carry-forward memakai modalAwalTotalAset (bug lama = 0)', () {
      final p = periode(totalAset: 52200000);
      expect(p.modalAwal, 0); // perilaku lama yang menyebabkan selisih = aset
      expect(tentukanModalAcuan(p).nilai, 52200000);
    });
    test('periode pertama memakai setoran cash + bank', () {
      expect(tentukanModalAcuan(periode(cash: 1000, bank: 500)).nilai, 1500);
    });
    test('semua 0 -> belum dapat dihitung, selisih null (bukan 0)', () {
      final m = tentukanModalAcuan(periode());
      expect(m.tersedia, isFalse);
      final ind =
          IndikatorAset(totalAset: 100, totalKewajiban: 0, modalAcuan: m);
      expect(ind.selisihAsetBersihVsModal, isNull);
      expect(ind.selisihTotalAsetVsModal, isNull);
      expect(ind.peringatan, isNotEmpty);
    });
    test('periode null -> belum dapat dihitung', () {
      expect(tentukanModalAcuan(null).tersedia, isFalse);
    });
    test('rugi: selisih negatif tetap ditampilkan negatif', () {
      final ind = IndikatorAset(
          totalAset: 40,
          totalKewajiban: 10,
          modalAcuan: const ModalAcuan(100, 'uji'));
      expect(ind.selisihAsetBersihVsModal, -70);
    });
  });

  group('Pemisahan pemasukan / duplikasi', () {
    test('satu penjualan 42.950.000 tanpa pemasukan lain', () {
      final b = pisahkanPemasukan(
          [pemasukan('Penjualan Motor', 42950000, id: 1, ref: 1)]);
      expect(b.pendapatanLain, 0);
      expect(b.penerimaanPenjualan, 42950000);
    });
    test('pemasukan manual berbeda bernominal sama tetap terpisah', () {
      final b = pisahkanPemasukan([
        pemasukan('Penjualan Motor', 42950000, id: 1, ref: 1),
        pemasukan('Jasa Lain', 42950000, id: 2),
      ]);
      expect(b.penerimaanPenjualan, 42950000);
      expect(b.pendapatanLain, 42950000);
      expect(b.totalPenerimaanKas, 85900000);
    });
    test('setoran modal bukan pendapatan', () {
      final b = pisahkanPemasukan([pemasukan('Tambah Modal', 5000000, id: 1)]);
      expect(b.pendapatanLain, 0);
      expect(b.setoranModal, 5000000);
    });
    test('DP: kas diterima < omzet, omzet tidak berubah', () {
      final b = pisahkanPemasukan(
          [pemasukan('Penjualan Motor', 10000000, id: 1, ref: 1)]);
      expect(b.penerimaanPenjualan, 10000000);
      expect(penjualan(1, 42950000).hargaJual, 42950000);
    });
    test('periode kosong -> semua nol', () {
      final b = pisahkanPemasukan([]);
      expect(b.totalPenerimaanKas, 0);
    });
  });

  group('Deteksi dugaan duplikat (hanya peringatan)', () {
    test('penjualan + jurnal otomatis normal -> tanpa peringatan', () {
      expect(
          deteksiDugaanDuplikat(
            penjualan: [penjualan(1, 42950000)],
            pemasukan: [pemasukan('Penjualan Motor', 42950000, id: 1, ref: 1)],
          ),
          isEmpty);
    });
    test('dua jurnal untuk satu penjualan -> peringatan', () {
      final w = deteksiDugaanDuplikat(
        penjualan: [penjualan(1, 100)],
        pemasukan: [
          pemasukan('Penjualan Motor', 100, id: 1, ref: 1),
          pemasukan('Penjualan Motor', 100, id: 2, ref: 1),
        ],
      );
      expect(w.length, 1);
    });
    test('pemasukan manual sama nominal+tanggal dengan penjualan -> peringatan',
        () {
      final w = deteksiDugaanDuplikat(
        penjualan: [penjualan(1, 42950000)],
        pemasukan: [
          pemasukan('Penjualan Motor', 42950000, id: 1, ref: 1),
          pemasukan('Jasa Lain', 42950000, id: 2),
        ],
      );
      expect(w.length, 1);
    });
    test('nominal sama tapi tanggal beda -> tidak dicurigai', () {
      final w = deteksiDugaanDuplikat(
        penjualan: [penjualan(1, 500)],
        pemasukan: [
          pemasukan('Jasa Lain', 500, id: 2, tanggal: DateTime(2026, 10, 9)),
        ],
      );
      expect(w, isEmpty);
    });
    test('jurnal yatim (referensi penjualan tidak ada) -> peringatan', () {
      final w = deteksiDugaanDuplikat(
        penjualan: [],
        pemasukan: [pemasukan('Penjualan Motor', 100, id: 1, ref: 99)],
      );
      expect(w.length, 1);
    });
  });
}
