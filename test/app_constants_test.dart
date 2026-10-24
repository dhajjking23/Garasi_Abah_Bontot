import 'package:flutter_test/flutter_test.dart';
import 'package:garasi_abah_bontot/core/constants/app_constants.dart';

void main() {
  group('AppConstants - Pembagian Laba', () {
    test('total persentase pembagian laba harus tepat 100%', () {
      const total = AppConstants.persenAbah +
          AppConstants.persenIki +
          AppConstants.persenAndri +
          AppConstants.persenIlham +
          AppConstants.persenHadiahPenjualan;

      expect(total, closeTo(1.0, 0.0001));
    });

    test('persentase masing-masing pemilik sesuai spesifikasi', () {
      expect(AppConstants.persenAbah, 0.25);
      expect(AppConstants.persenIki, 0.275);
      expect(AppConstants.persenAndri, 0.225);
      expect(AppConstants.persenIlham, 0.15);
      expect(AppConstants.persenHadiahPenjualan, 0.10);
    });

    test('pembagianLabaUtama berisi 4 pemilik dengan total 90%', () {
      final total = AppConstants.pembagianLabaUtama.values
          .fold<double>(0, (sum, v) => sum + v);
      expect(AppConstants.pembagianLabaUtama.length, 4);
      expect(total, closeTo(0.90, 0.0001));
    });

    test('Calo tidak termasuk daftar penjual internal berhak bonus', () {
      expect(
        AppConstants.penjualInternalBerhakBonus.contains('Calo'),
        isFalse,
      );
      expect(AppConstants.penjualInternalBerhakBonus.length, 4);
    });

    test('daftar penjual mencakup 4 internal + Calo', () {
      expect(AppConstants.daftarPenjual.length, 5);
      expect(AppConstants.daftarPenjual.contains(AppConstants.penjualCalo),
          isTrue);
    });
  });
}
