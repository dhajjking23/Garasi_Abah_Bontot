import 'package:flutter/material.dart';
import '../../core/motion/motion.dart';

/// V5.9.11-MOTION — KPI counter animation (Mega Prompt §12): angka
/// menghitung naik dari 0 (atau dari nilai sebelumnya) ke nilai baru
/// saat pertama tampil / saat berubah, BUKAN meloncat langsung. Dipakai
/// untuk kartu ringkasan Dashboard (Total Aset, Laba, Cash, dst).
///
/// PENTING (§12 "Do NOT constantly animate numbers after loading"):
/// widget ini hanya animasi saat NILAI benar-benar berubah (dideteksi
/// via `oldWidget.value != value` pada `didUpdateWidget`), bukan setiap
/// rebuild — supaya tidak "menghitung ulang" tiap kali layar sekadar
/// digambar ulang karena state lain berubah.
class AnimatedCountUp extends StatefulWidget {
  final double value;
  final String Function(double) formatter;
  final TextStyle? style;
  final Duration duration;
  final int? maxLines;
  final TextOverflow? overflow;

  const AnimatedCountUp({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.duration = AppMotion.medium,
    this.maxLines,
    this.overflow,
  });

  @override
  State<AnimatedCountUp> createState() => _AnimatedCountUpState();
}

class _AnimatedCountUpState extends State<AnimatedCountUp> {
  double _previous = 0;

  @override
  void didUpdateWidget(covariant AnimatedCountUp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previous = oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduceMotion(context);
    if (reduced) {
      return Text(
        widget.formatter(widget.value),
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: _previous, end: widget.value),
      duration: widget.duration,
      curve: AppMotion.emphasized,
      builder: (context, val, _) {
        return Text(
          widget.formatter(val),
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
        );
      },
    );
  }
}
