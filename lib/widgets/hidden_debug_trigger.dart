import 'package:flutter/material.dart';

/// Wrapper widget: tap child 5 kali dalam 3 detik -> panggil [onTriggered].
/// Dipakai untuk fallback server discovery (tap logo aplikasi 5x) — cek
/// role OWNER_ADMIN di [onTriggered] itu sendiri, widget ini tidak tahu
/// soal role sama sekali (murni penghitung tap).
class HiddenDebugTrigger extends StatefulWidget {
  final Widget child;
  final VoidCallback onTriggered;
  final int requiredTaps;
  final Duration resetWindow;

  const HiddenDebugTrigger({
    super.key,
    required this.child,
    required this.onTriggered,
    this.requiredTaps = 5,
    this.resetWindow = const Duration(seconds: 3),
  });

  @override
  State<HiddenDebugTrigger> createState() => _HiddenDebugTriggerState();
}

class _HiddenDebugTriggerState extends State<HiddenDebugTrigger> {
  int _tapCount = 0;
  DateTime? _firstTapAt;

  void _onTap() {
    final now = DateTime.now();
    if (_firstTapAt == null || now.difference(_firstTapAt!) > widget.resetWindow) {
      _firstTapAt = now;
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    if (_tapCount >= widget.requiredTaps) {
      _tapCount = 0;
      _firstTapAt = null;
      widget.onTriggered();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}
