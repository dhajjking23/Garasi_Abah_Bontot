// Basic smoke test untuk Garasi Abah Bontot.
//
// Test ini memastikan aplikasi bisa dibangun (build) tanpa error, alur
// login V4 (AuthGate) berjalan, dan RootShell (bottom navigation) muncul
// setelah login sukses.
// Test yang lebih detail untuk logika bisnis ada di:
//   - test/app_constants_test.dart
//   - test/pembagian_laba_formula_test.dart
//   - test/app_formatter_test.dart
//   - test/saldo_model_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:garasi_abah_bontot/main.dart';
import 'package:garasi_abah_bontot/core/database/database_helper.dart';

/// Path provider palsu untuk host test: mengarahkan "application documents
/// directory" ke folder temp di disk host, karena tidak ada platform
/// channel native yang tersedia saat `flutter test` dijalankan.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._dir);
  final Directory _dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    // Ganti backend sqflite ke FFI (sqlite3 murni) supaya query DB bisa
    // jalan di host test tanpa emulator/device Android.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Penanganan noise google_fonts (tidak bisa fetch font lewat network
    // di host test) sudah diatur secara global untuk seluruh test suite
    // di test/flutter_test_config.dart — tidak perlu diulang di sini.
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('garasi_widget_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
      'App bisa dibangun, login berhasil, dan bottom navigation muncul',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: GarasiAbahBontotApp()),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Sebelum login, yang tampil harus LoginScreen (V4: wajib login).
    expect(find.text('MASUK'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // Login pakai akun OWNER_ADMIN default hasil seed database
    // (lihat DatabaseHelper._seedDefaultUsers): andri / andri123.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'andri',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'andri123',
    );
    await tester.tap(find.text('MASUK'));
    await tester.pump();

    // PENTING: login menyentuh sqflite_common_ffi, yang melakukan I/O
    // NYATA lewat isolate/FFI (buka/bikin file DB, migrasi tabel, seed
    // data, dsb). tester.pump(duration) HANYA memajukan jam animasi &
    // flush microtask — ia tidak menunggu operasi I/O event-loop yang
    // sungguhan selesai. tester.runAsync() membuka "jendela" ke event
    // loop nyata supaya operasi database itu bisa benar-benar tuntas.
    //
    // Durasi bikin DB baru (banyak CREATE TABLE + seed) bisa bervariasi
    // tergantung kecepatan disk runner CI, jadi di sini kita POLLING
    // (cek berulang) sampai RootShell muncul, bukan menunggu durasi
    // tetap — supaya test tidak flaky di runner yang kebetulan lambat.
    var loggedIn = false;
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      if (find.byType(NavigationBar).evaluate().isNotEmpty) {
        loggedIn = true;
        break;
      }
    }

    if (!loggedIn) {
      // Bantu diagnosa kalau tetap gagal: apakah muncul pesan error login
      // (kredensial salah) atau masih macet di loading.
      final adaErrorLogin = find
          .text('Username atau password salah, atau akun nonaktif.')
          .evaluate()
          .isNotEmpty;
      fail(
        'Login tidak selesai sampai batas waktu polling (~5 detik). '
        'Pesan error login terlihat di layar: $adaErrorLogin. '
        'Jika true -> kredensial seed (andri/andri123) tidak cocok dengan '
        'yang ada di DB. Jika false -> proses login masih macet/loading '
        '(kemungkinan ada exception di layer database yang belum '
        'terekspos ke UI).',
      );
    }

    await tester.pump(const Duration(milliseconds: 300));

    // Setelah login sukses, RootShell dengan bottom navigation harus muncul.
    // pumpAndSettle di sini (dengan timeout aman) membereskan sisa
    // animasi/microtask transisi Login -> RootShell sebelum kita expect,
    // supaya tidak flaky karena masih ada frame yang "in-flight".
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Motor'), findsOneWidget);
    expect(find.text('Penjualan'), findsOneWidget);
    expect(find.text('Pembukuan'), findsOneWidget);
    expect(find.text('Laporan'), findsOneWidget);

    // PENTING (pending timer fix): lepas widget tree secara EKSPLISIT
    // sebelum callback test ini return, lalu pump sekali lagi. Ini memaksa
    // ProviderScope (dan seluruh provider di bawahnya, termasuk yang
    // terhubung ke DatabaseHelper/sqflite) untuk mulai proses dispose di
    // dalam siklus pump yang masih kita kontrol.
    //
    // Kalau dibiarkan dispose terjadi implicit setelah test ini return
    // (perilaku default), Riverpod men-scheduling dispose provider
    // autoDispose lewat sebuah Timer (lihat
    // `_ProviderScheduler.scheduleProviderDispose` di paket riverpod).
    // Timer itu bisa belum sempat "tick" saat flutter_test melakukan
    // pengecekan akhir (`verifyInvariants`), sehingga muncul error
    // "A Timer is still pending even after the widget tree was disposed."
    // — bukan bug di provider/database itu sendiri, murni soal urutan.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
