import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/motor/motor_list_screen.dart';
import 'screens/penjualan/penjualan_screen.dart';
import 'screens/pembukuan/pembukuan_screen.dart';
import 'screens/laporan/laporan_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/pengaturan/pengaturan_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/sync_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(const ProviderScope(child: GarasiAbahBontotApp()));
}

class GarasiAbahBontotApp extends StatelessWidget {
  const GarasiAbahBontotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Garasi Abah Bontot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}

/// AuthGate — V4: wajib login (OWNER_ADMIN / VIEWER) sebelum masuk aplikasi.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restoring = ref.watch(authRestoringProvider);
    if (restoring) {
      // Persistent login: sedang mengecek sesi tersimpan (app baru dibuka
      // / HP baru restart). Jangan lompat ke LoginScreen dulu.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = ref.watch(authProvider);
    if (user == null) {
      return const LoginScreen();
    }
    return const RootShell();
  }
}

/// Shell utama dengan bottom navigation. Halaman lain (Pemasukan,
/// Pengeluaran, Kasbon, Pembagian Laba) diakses lewat menu di Dashboard
/// dan Pembukuan agar bottom nav tetap ringkas (5 tab utama).
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _autoSyncTimer;

  // V5.2 — AUTO SYNC REALTIME: interval polling selama app aktif di
  // foreground. syncNow() sendiri yang menentukan arah (ADMIN push /
  // VIEWER pull) dan aman dipanggil berulang (no-op kalau masih syncing
  // atau server offline — lihat SyncNotifier & SyncPushService).
  static const _autoSyncInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Sync pertama begitu app dibuka (login baru / sesi tersimpan
    // direstore) — untuk ADMIN maupun VIEWER, tidak perlu buka menu Server
    // atau tekan tombol manual dulu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncNotifierProvider.notifier).syncNow();
    });

    _startAutoSyncTimer();
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
      // syncNow() sudah aman dipanggil kapan pun: kalau server OFFLINE,
      // gagal dengan tenang dan tetap pakai data lokal terakhir (lihat
      // SyncClientException handling di SyncNotifier); begitu server
      // ONLINE lagi, panggilan berikutnya otomatis lanjut normal tanpa
      // aksi tambahan apa pun.
      ref.read(syncNotifierProvider.notifier).syncNow();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hemat baterai/data: auto sync hanya jalan selagi app di foreground.
    // Begitu kembali (resumed), langsung sync sekali + timer jalan lagi.
    if (state == AppLifecycleState.resumed) {
      ref.read(syncNotifierProvider.notifier).syncNow();
      _startAutoSyncTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _autoSyncTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  final _pages = const [
    DashboardScreen(),
    MotorListScreen(),
    PenjualanScreen(),
    PembukuanScreen(),
    LaporanScreen(),
    PengaturanScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.motorcycle_outlined),
            selectedIcon: Icon(Icons.motorcycle),
            label: 'Motor',
          ),
          NavigationDestination(
            icon: Icon(Icons.sell_outlined),
            selectedIcon: Icon(Icons.sell),
            label: 'Penjualan',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Pembukuan',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Laporan',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}
