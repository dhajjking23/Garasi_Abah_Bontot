# TODO — Perbaikan Permanen widget_test.dart

**Status saat ini:** `flutter test` masih gagal di CI (test `widget_test.dart`)
meski precheck database sudah diperbaiki (`singleInstance: false`). CI diatur
`continue-on-error: true` di `.github/workflows/build_apk.yml` supaya Build
APK tetap jalan — **ini sementara**, bukan solusi akhir.

## Yang sudah dicoba & terbukti BUKAN penyebab utama
- Noise `google_fonts` (fetch font gagal di CI) — sudah ditangani benar via
  `test/flutter_test_config.dart` (`allowRuntimeFetching = false` +
  `runZonedGuarded` menahan exception async-nya).
- Precheck backup-before-migration membuka koneksi kedua ke path yang sama
  dan bentrok dengan cache singleton `sqflite` — sudah diperbaiki dengan
  `singleInstance: false` + `finally { close() }` di `database_helper.dart`.

Test tetap gagal dengan gejala sama (`database has been locked`,
`pumpAndSettle timed out`) setelah kedua perbaikan di atas — artinya ada
sumber kontensi lain yang belum ditemukan.

## Kandidat penyebab untuk investigasi berikutnya
1. **Trigger SQLite `json_object(...)`** yang dibuat di
   `_createSyncTriggers` (V12) — `sqflite_common_ffi` di CI memakai
   `sqlite3` versi tertentu dari `sqlite3_flutter_libs`/paket sistem host;
   jika versi itu < 3.38 tanpa ekstensi JSON1 aktif, `CREATE TRIGGER`
   dengan `json_object()` bisa gagal SAAT trigger tereksekusi (bukan saat
   dibuat), yaitu tepat saat `tambahMotor`/insert pertama terjadi — waktunya
   cocok dengan momen test macet (setelah tap tombol MASUK, saat login
   memicu seed data & insert pertama).
2. Kemungkinan **deadlock nested transaction**: beberapa repository
   (`motor_repository.dart`, dll) memanggil `db.transaction()` yang di
   dalamnya memanggil repository lain yang juga membuka `db.transaction()`
   baru alih-alih memakai `txn` yang sama — ini valid di sqflite native
   Android tapi berpotensi beda perilaku di `sqflite_common_ffi`.
3. Cek apakah `AuthService.instance` (singleton in-memory, bukan per-test)
   membawa state dari test sebelumnya jika suite ditambah test lain.

## Langkah verifikasi tersarankan
- Jalankan `flutter test test/widget_test.dart -v` lokal dengan Flutter SDK
  asli (bukan CI) untuk lihat stack trace lengkap tanpa terpotong oleh log
  GitHub Actions.
- Sementara nonaktifkan trigger `json_object` (ganti payload jadi `NULL`
  dulu) di `_createSyncTriggers` sebagai eksperimen isolasi — jika test
  langsung hijau, itu konfirmasi penyebab #1 di atas.
- Setelah akar masalah ketemu dan widget_test hijau secara natural, HAPUS
  `continue-on-error: true` dari `build_apk.yml`.
