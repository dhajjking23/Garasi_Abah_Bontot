# GARASI ABAH BONTOT V5.2 — AUTO SYNC REALTIME

## File berubah
- `lib/main.dart`

## File baru
(tidak ada)

## Perubahan
`_RootShellState` (shell utama setelah login) sekarang:
- Jalankan `syncNow()` sekali begitu app dibuka (ADMIN & VIEWER, sebelumnya
  hanya VIEWER).
- `Timer.periodic` tiap 30 detik memanggil `syncNow()` selama app di
  foreground — ADMIN otomatis push, VIEWER otomatis pull (arah ditentukan
  `syncNow()` yang sudah ada, tidak diubah).
- `WidgetsBindingObserver`: timer berhenti saat app di background
  (`paused`/`detached`), langsung sync + timer jalan lagi saat kembali
  (`resumed`).
- Server offline → `syncNow()` gagal dengan tenang (sudah ditangani
  `SyncClientException` yang ada), app tetap pakai data lokal terakhir.
  Server online lagi → panggilan timer berikutnya otomatis lanjut normal.

Tombol "Sinkronkan Sekarang" tidak diubah. Sistem sync (`SyncNotifier`,
`SyncService`, `SyncPushService`, server) tidak disentuh sama sekali.
