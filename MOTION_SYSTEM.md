# MOTION_SYSTEM.md — Garasi Abah Bontot (Flutter)

## Catatan penting sebelum membaca

Prompt yang diberikan ditulis untuk aplikasi web (CSS custom properties,
`prefers-reduced-motion` media query, sidebar/dropdown HTML, dsb).
Proyek ini adalah **aplikasi Flutter/Dart mobile**, bukan web — jadi
setiap konsep di prompt saya terjemahkan ke padanan Flutter yang
sebenarnya, bukan ditiru literal. Tabel di bawah memetakan istilah
prompt → implementasi nyata di sini.

| Konsep di prompt | Padanan di Flutter (proyek ini) |
|---|---|
| CSS custom properties `--motion-*` | `lib/core/motion/motion.dart` → class `AppMotion` (konstanta `Duration`/`Curve`) |
| `prefers-reduced-motion: reduce` | `MediaQuery.of(context).disableAnimations` (Android "Remove animations" / iOS "Reduce Motion") — dicek lewat `AppMotion.reduceMotion(context)` |
| Page/route transition | `PageTransitionsTheme` di `AppTheme.lightTheme`, custom builder `AppPageTransitionsBuilder` |
| Card/list entrance + stagger | `lib/widgets/motion/fade_slide_in.dart` (`FadeSlideIn`, `StaggeredEntrance`) |
| Button/tile press feedback | `lib/widgets/motion/pressable_scale.dart` (`PressableScale`) — HANYA untuk widget custom yang belum punya ripple; tombol Material bawaan (`ElevatedButton` dst) SUDAH punya feedback sendiri |
| KPI counter animation | `lib/widgets/motion/animated_count_up.dart` (`AnimatedCountUp`) |
| Skeleton loading | `lib/widgets/motion/skeleton.dart` (`SkeletonBox`, `SkeletonCard`) |
| Toast/snackbar | `ScaffoldMessenger.showSnackBar` bawaan Flutter — animasi masuk/keluar sudah ditangani framework, tidak perlu dibuat ulang |

## Token motion (`AppMotion`)

```dart
AppMotion.instant  // 80ms  — tap/press feedback
AppMotion.fast     // 160ms — chip, toggle
AppMotion.normal   // 280ms — card, entrance
AppMotion.medium   // 420ms — transisi halaman, counter besar
AppMotion.slow     // 650ms — dipakai sangat jarang

AppMotion.standard  // Curves.easeOutCubic — default umum
AppMotion.emphasized// Curves.easeOutQuint — angka besar, hero
AppMotion.enter     // Curves.easeOut
AppMotion.exit      // Curves.easeIn
AppMotion.spring    // Curves.easeOutBack — feedback playful (dipakai hati-hati)
```

Semua widget motion baru **wajib** memakai token ini, bukan angka
`Duration`/`Curve` hardcode tersebar di tiap file — supaya nada gerak
seluruh app tetap satu keluarga dan bisa di-tune di satu tempat.

## Reduced motion (wajib, bukan opsional)

Setiap widget di `lib/widgets/motion/` memeriksa
`AppMotion.reduceMotion(context)` di awal `build()`. Kalau aktif:
- `FadeSlideIn` → tampil langsung penuh, tanpa fade/slide.
- `PressableScale` → tap tetap berfungsi, tanpa efek mengecil.
- `AnimatedCountUp` → angka langsung tampil final, tanpa menghitung naik.
- `SkeletonBox` → blok statis, tanpa efek sweep bergerak.
- `AppPageTransitionsBuilder` → jatuh balik ke transisi fade sederhana
  bawaan Flutter, bukan custom slide.

Feedback fungsional (warna, teks, status) tidak pernah bergantung pada
animasi saja — animasi cuma memperhalus, bukan satu-satunya sumber
informasi.

## Cara pakai singkat

```dart
// Entrance satu widget
FadeSlideIn(child: MyCard())

// Entrance list dengan stagger
GridView.count(
  children: StaggeredEntrance.staggeredChildren([
    CardA(), CardB(), CardC(),
  ]),
)

// Angka KPI yang menghitung naik
AnimatedCountUp(
  value: totalAset,
  formatter: AppFormatter.rupiah,
  style: myStyle,
)

// Skeleton saat loading
summaryAsync.when(
  loading: () => const SkeletonCard(),
  data: (s) => MyRealCard(s),
)
```

Transisi halaman (`AppPageTransitionsBuilder`) TIDAK perlu dipanggil
manual — sudah aktif otomatis untuk setiap
`Navigator.push(MaterialPageRoute(...))` di seluruh aplikasi lewat
`AppTheme.lightTheme.pageTransitionsTheme`.
