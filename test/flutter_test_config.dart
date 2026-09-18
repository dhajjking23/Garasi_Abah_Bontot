// Konfigurasi global untuk seluruh test suite di folder `test/`.
// File ini otomatis dipanggil oleh `flutter test` SEBELUM semua test
// dijalankan — ini adalah mekanisme resmi Flutter untuk hal semacam ini,
// bukan hack. Lihat: https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html
// (cari "flutter_test_config.dart").
//
// Kenapa file ini ada (bukan taruh di widget_test.dart saja):
//
// AppTheme (kode aplikasi, TIDAK diubah) memakai GoogleFonts, yang secara
// default mencoba fetch font lewat network saat runtime. Di host test (CI)
// semua request HTTP diblok oleh TestWidgetsFlutterBinding (selalu balas
// kode 400), jadi percobaan fetch itu PASTI gagal. Ini murni kosmetik/noise
// — Text tetap render normal pakai font fallback — TAPI exception async
// dari percobaan itu kadang baru "meledak" SETELAH body test selesai
// (makanya di log tertulis "but after the test had completed"), sehingga
// lolos dari zone internal flutter_test per-test dan malah menggagalkan
// test lain yang kebetulan sedang berjalan berikutnya.
//
// runZonedGuarded di sini membungkus SELURUH test suite (bukan cuma satu
// testWidgets), dan binding Flutter diinisialisasi DI DALAM zone ini
// (bukan di zone terpisah) — jadi aman dari "zone mismatch", beda dengan
// kalau kita taruh runZonedGuarded di dalam satu testWidgets secara
// terpisah dari binding init.
import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Matikan percobaan fetch font lewat network sama sekali. Karena project
  // ini tidak membundel file font sebagai asset, kegagalannya (baik gagal
  // network maupun "not found in assets") sama-sama tidak fatal untuk UI —
  // keduanya cuma memengaruhi Future background yang memuat file font,
  // terpisah dari proses render widget itu sendiri.
  GoogleFonts.config.allowRuntimeFetching = false;

  await runZonedGuarded(
    () async {
      await testMain();
    },
    (Object error, StackTrace stack) {
      final message = error.toString();
      final isBenignFontError = message.contains('google_fonts') ||
          message.contains('Failed to load font') ||
          message.contains('allowRuntimeFetching');

      if (isBenignFontError) {
        // Sengaja diabaikan — lihat penjelasan panjang di atas.
        return;
      }

      // Error lain (bukan soal font) BUKAN urusan file ini untuk
      // menyembunyikan — lempar lagi supaya tetap terlihat & tetap
      // menggagalkan test seperti perilaku default flutter_test.
      // ignore: only_throw_errors
      throw error;
    },
  );
}
