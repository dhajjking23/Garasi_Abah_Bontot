import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/motion/motion.dart';

/// V5.9.11-MOTION — Skeleton shimmer (Mega Prompt §14/§44 "Small:
/// Component skeleton"). Pengganti `CircularProgressIndicator` polos
/// untuk area yang MEMANG akan digantikan konten sungguhan berbentuk
/// blok (card, baris list, angka ringkasan) — bukan untuk aksi singkat
/// (tetap pakai spinner kecil di tombol untuk itu, §44 "Tiny: Button
/// spinner").
///
/// Menghormati reduced-motion (§46): kalau aktif, tampil sebagai blok
/// statis abu-abu tanpa efek sweep bergerak (tetap jelas "ini loading",
/// cuma tanpa animasi looping).
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Colors.black.withOpacity(0.06);
    if (AppMotion.reduceMotion(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: widget.borderRadius),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(color: base),
            child: Align(
              alignment: Alignment(_controller.value * 3 - 1.5, 0),
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        base.withOpacity(0),
                        AppTheme.primary.withOpacity(0.08),
                        base.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Kombinasi beberapa [SkeletonBox] menyerupai bentuk kartu ringkasan —
/// dipakai saat Dashboard/laporan masih memuat data async.
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 90});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SkeletonBox(width: 90, height: 12),
          SizedBox(height: 8),
          SkeletonBox(width: 140, height: 20),
        ],
      ),
    );
  }
}
