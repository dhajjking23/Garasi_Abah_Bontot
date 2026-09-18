import 'package:flutter/material.dart';
import '../../core/motion/motion.dart';

/// V5.9.11-MOTION — Entrance animation: opacity 0→1 + translateY 12px→0
/// (Mega Prompt §7 "Cards / Entrance"). Dipakai untuk card, list item,
/// section — kapan pun sebuah widget baru muncul di layar dan sebaiknya
/// tidak langsung "meloncat" begitu saja.
///
/// Otomatis menghormati reduced-motion (§46): kalau aktif, widget
/// langsung tampil penuh tanpa animasi.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.normal,
    this.offsetY = 12,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: AppMotion.enter);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.standard));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reduced = AppMotion.reduceMotion(context);
      if (_reduced) {
        _controller.value = 1;
        return;
      }
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: FractionalTranslation(
            translation: _slide.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// V5.9.11-MOTION — Bungkus list/grid yang butuh entrance BERTAHAP
/// (stagger, Mega Prompt §8): item pertama muncul duluan, item
/// berikutnya menyusul dengan delay kecil, bukan semua muncul serentak.
///
/// Pakai seperti `ListView`/`Column` biasa — tinggal ganti children
/// dengan hasil [staggeredChildren].
class StaggeredEntrance {
  /// Bungkus setiap widget di [children] dengan [FadeSlideIn] dengan
  /// delay bertahap. [step] menentukan jarak antar item (default:
  /// [AppMotion.staggerSmall]), dan otomatis di-cap
  /// ([AppMotion.staggerMaxItems]) supaya list panjang tidak terasa
  /// lambat (§8: "keep stagger short enough that the UI still feels
  /// fast").
  static List<Widget> staggeredChildren(
    List<Widget> children, {
    Duration step = AppMotion.staggerSmall,
    Duration duration = AppMotion.normal,
  }) {
    return List.generate(children.length, (i) {
      return FadeSlideIn(
        delay: AppMotion.staggerDelayFor(i, step: step),
        duration: duration,
        child: children[i],
      );
    });
  }
}
