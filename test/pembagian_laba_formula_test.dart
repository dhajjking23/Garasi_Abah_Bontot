import 'package:flutter_test/flutter_test.dart';
import 'package:garasi_abah_bontot/core/constants/app_constants.dart';

/// Simulasi murni rumus hadiah penjualan (tanpa database) untuk
/// memverifikasi kesesuaian dengan contoh pada spesifikasi:
///   Total hadiah: 2.000.000, Unit internal: 10 unit
///   -> Bonus/unit: 200.000
///   Seseorang menjual 3 unit -> mendapat 600.000
double hitungBonusPerUnit(double totalHadiah, int unitInternal) {
  if (unitInternal == 0) return 0;
  return totalHadiah / unitInternal;
}

double hitungBonusMilikSeseorang(double bonusPerUnit, int jumlahUnitDijual) {
  return bonusPerUnit * jumlahUnitDijual;
}

void main() {
  group('Rumus Hadiah Penjualan (sesuai contoh spesifikasi)', () {
    test('bonus per unit = total hadiah / unit internal terjual', () {
      final bonusPerUnit = hitungBonusPerUnit(2000000, 10);
      expect(bonusPerUnit, 200000);
    });

    test('bonus milik seseorang yang menjual 3 unit = 600.000', () {
      final bonusPerUnit = hitungBonusPerUnit(2000000, 10);
      final bonusMilik = hitungBonusMilikSeseorang(bonusPerUnit, 3);
      expect(bonusMilik, 600000);
    });

    test('unit internal terjual 0 -> bonus per unit 0 (hindari div by zero)',
        () {
      final bonusPerUnit = hitungBonusPerUnit(2000000, 0);
      expect(bonusPerUnit, 0);
    });
  });

  group('Rumus Laba', () {
    test('laba motor = harga jual - modal motor', () {
      const hargaJual = 15000000.0;
      const modalMotor = 12000000.0;
      const laba = hargaJual - modalMotor;
      expect(laba, 3000000);
    });

    test('laba bersih periode = total laba motor - pengeluaran lain', () {
      const totalLabaMotor = 10000000.0;
      const pengeluaranLain = 1500000.0;
      const labaBersih = totalLabaMotor - pengeluaranLain;
      expect(labaBersih, 8500000);
    });

    test('pembagian laba bersih ke 4 pemilik + hadiah sesuai persentase', () {
      const labaBersih = 8500000.0;
      const bagianAbah = labaBersih * AppConstants.persenAbah;
      const bagianIki = labaBersih * AppConstants.persenIki;
      const bagianAndri = labaBersih * AppConstants.persenAndri;
      const bagianIlham = labaBersih * AppConstants.persenIlham;
      const hadiah = labaBersih * AppConstants.persenHadiahPenjualan;

      const totalDibagikan =
          bagianAbah + bagianIki + bagianAndri + bagianIlham + hadiah;

      expect(totalDibagikan, closeTo(labaBersih, 0.01));
    });
  });

  group('Aturan Calo', () {
    test('Calo tidak dihitung sebagai unit internal', () {
      const daftarPenjualan = [
        {'penjual': 'Abah', 'internal': true},
        {'penjual': 'Iki', 'internal': true},
        {'penjual': 'Calo', 'internal': false},
      ];

      final unitInternal =
          daftarPenjualan.where((p) => p['internal'] == true).length;

      expect(unitInternal, 2);
    });
  });
}
