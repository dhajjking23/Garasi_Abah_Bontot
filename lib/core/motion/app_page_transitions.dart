import 'package:flutter/material.dart';
import '../../core/motion/motion.dart';

/// V5.9.11-MOTION — Page transition app-wide (Mega Prompt §9): fade +
/// translateY halus, bukan slide horizontal platform default yang
/// terasa berat/lambat untuk app internal seperti ini.
///
/// Ini didaftarkan SEKALI ke `ThemeData.pageTransitionsTheme` di
/// `AppTheme` (lihat app_theme.dart) — begitu terpasang, SEMUA
/// `Navigator.push(MaterialPageRoute(...))` di SELURUH 28+ layar
/// aplikasi otomatis memakai transisi ini TANPA perlu mengubah satu pun
/// file layar itu sendiri. Ini cara paling aman untuk memenuhi §9
/// ("implement polished page/view transitions") di seluruh aplikasi
/// tanpa menyentuh setiap layar satu-satu (risiko regresi jauh lebih
/// kecil daripada mengedit 28 file terpisah).
///
/// Menghormati reduced-motion (§46): kalau aktif, memakai builder
/// bawaan Flutter (`FadeUpwardsPageTransitionsBuilder`) yang jauh lebih
/// singkat & tanpa gerakan besar, alih-alih transisi custom ini.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.standard);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(curved);
    // Halaman yang DITINGGALKAN (secondaryAnimation) sedikit fade juga,
    // supaya terasa "halaman baru mendorong masuk", bukan cuma halaman
    // baru muncul menimpa (Mega Prompt §9: hindari transisi yang bikin
    // navigasi terasa lambat, jadi durasinya tetap pakai default route
    // Flutter -- cuma kurvanya yang diganti).
    final outgoingFade = Tween<double>(begin: 1, end: 0.85).animate(
      CurvedAnimation(parent: secondaryAnimation, curve: AppMotion.exit),
    );
    return FadeTransition(
      opacity: curved,
      child: FadeTransition(
        opacity: outgoingFade,
        child: SlideTransition(position: slide, child: child),
      ),
    );
  }
}
