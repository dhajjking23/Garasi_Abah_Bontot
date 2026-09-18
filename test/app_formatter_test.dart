import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:garasi_abah_bontot/core/utils/app_formatter.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  group('AppFormatter', () {
    test('format rupiah tanpa desimal', () {
      final hasil = AppFormatter.rupiah(1500000);
      expect(hasil.contains('1.500.000'), isTrue);
      expect(hasil.contains('Rp'), isTrue);
    });

    test('format persen', () {
      expect(AppFormatter.persen(0.275), '27.5%');
      expect(AppFormatter.persen(0.25), '25.0%');
    });
  });
}
