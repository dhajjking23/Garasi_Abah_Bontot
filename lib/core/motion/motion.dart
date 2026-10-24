import 'package:flutter/material.dart';

/// V5.9.11-MOTION — Sistem token motion terpusat.
///
/// Flutter TIDAK memakai CSS custom properties (`--motion-fast`, dst) —
/// padanan idiomatis-nya adalah konstanta `Duration`/`Curve` seperti di
/// bawah. Semua widget motion baru (`lib/widgets/motion/`) WAJIB pakai
/// token dari sini, bukan angka hardcode tersebar, supaya konsisten &
/// mudah di-tune di satu tempat (Mega Prompt §4/§55).
///
/// Hierarki durasi (Mega Prompt §4/§52):
///   micro   50–120ms  -> tap/press feedback, ikon kecil
///   fast    120–220ms -> chip, toggle, badge
///   normal  220–350ms -> card, modal masuk, entrance list
///   medium  350–600ms -> transisi halaman, panel besar
///   slow    600–1000ms -> dipakai SANGAT jarang (splash/hero)
class AppMotion {
  AppMotion._();

  // ---------------------------------------------------------------
  // DURATION TOKENS
  // ---------------------------------------------------------------
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration medium = Duration(milliseconds: 420);
  static const Duration slow = Duration(milliseconds: 650);

  // ---------------------------------------------------------------
  // EASING TOKENS
  // ---------------------------------------------------------------
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
  static const Curve enter = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
  static const Curve spring = Curves.easeOutBack;

  // ---------------------------------------------------------------
  // STAGGER TOKENS (Mega Prompt §8)
  // ---------------------------------------------------------------
  static const Duration staggerTiny = Duration(milliseconds: 30);
  static const Duration staggerSmall = Duration(milliseconds: 45);
  static const Duration staggerNormal = Duration(milliseconds: 60);

  /// Batas stagger total supaya list panjang tidak jadi lambat terasa
  /// (Mega Prompt §8: "keep stagger short enough that the UI still
  /// feels fast"). Item ke-N+ akan pakai delay yang sama (di-cap), tidak
  /// terus bertambah linear tanpa batas.
  static const int staggerMaxItems = 10;

  /// Hitung delay entrance untuk item ke-[index] dalam list, di-cap di
  /// [staggerMaxItems] supaya list panjang (misal 50 baris) tidak butuh
  /// menunggu 3 detik sebelum baris terakhir muncul.
  static Duration staggerDelayFor(int index,
      {Duration step = staggerSmall}) {
    final capped = index.clamp(0, staggerMaxItems);
    return step * capped;
  }

  // ---------------------------------------------------------------
  // ACCESSIBILITY (Mega Prompt §46 — WAJIB)
  // ---------------------------------------------------------------
  /// Padanan Flutter untuk `prefers-reduced-motion: reduce`. Flutter
  /// mengekspos preferensi OS ini lewat `MediaQuery.disableAnimations`
  /// (Android: "Remove animations", iOS: "Reduce Motion"). SEMUA widget
  /// motion baru WAJIB cek ini dan lompat langsung ke state akhir tanpa
  /// animasi kalau true — feedback fungsional (warna, teks, ikon) tetap
  /// harus ada, cuma gerakannya yang dihilangkan (§46: "Do NOT rely on
  /// animation alone").
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;

  /// Durasi efektif: 0 kalau reduced-motion aktif, supaya
  /// AnimationController/implicit-animation langsung "loncat" ke state
  /// akhir tanpa transisi visual, tapi tetap lewat code path yang sama
  /// (tidak perlu percabangan if/else di setiap widget pemanggil).
  static Duration effective(BuildContext context, Duration base) =>
      reduceMotion(context) ? Duration.zero : base;
}
