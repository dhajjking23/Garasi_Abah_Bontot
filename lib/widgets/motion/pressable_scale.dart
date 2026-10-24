import 'package:flutter/material.dart';
import '../../core/motion/motion.dart';

/// V5.9.11-MOTION — Micro-interaction press feedback (Mega Prompt
/// §5/§15/§36): elemen mengecil sedikit saat ditekan, kembali normal
/// saat dilepas — feedback taktil untuk kartu/tombol/tile yang bisa
/// diketuk. Dipakai membungkus widget yang SUDAH punya `onTap` sendiri
/// (mis. `Card`, `Container`, custom row) supaya tidak perlu mengganti
/// `InkWell`/`GestureDetector` yang sudah ada.
///
/// TIDAK dipakai untuk `ElevatedButton`/`OutlinedButton`/`TextButton`
/// bawaan Material — widget itu SUDAH punya feedback tekan sendiri
/// (ripple + state layer) dari `Theme` aplikasi, jadi membungkusnya
/// lagi hanya akan dobel efek, bukan menambah.
///
/// Menghormati reduced-motion (§46): kalau aktif, scale tidak berubah
/// sama sekali (tap masih berfungsi normal, cuma tanpa gerakan).
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.97,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduceMotion(context);
    final scale = (!reduced && _pressed) ? widget.scaleDown : 1.0;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: scale,
        duration: AppMotion.instant,
        curve: AppMotion.standard,
        child: widget.child,
      ),
    );
  }
}
