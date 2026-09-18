# Garasi Abah Bontot

Sistem pembukuan usaha jual beli motor berbasis Android (offline), dibangun
dengan Flutter + SQLite + Riverpod, Clean Architecture.

## Struktur Project

```
lib/
  core/
    constants/app_constants.dart      # Semua kategori, karyawan, % pembagian laba
    database/database_helper.dart     # Schema SQLite (11 tabel) + backup/restore
    theme/app_theme.dart
    utils/app_formatter.dart          # Format Rupiah & tanggal
  models/                             # 11 model data (Motor, Penjualan, dst)
  repositories/                       # Akses data + transaction + audit log
  services/
    dashboard_service.dart
    laporan_service.dart
    pembagian_laba_service.dart       # INTI: hitung laba, hadiah, pembagian
    export_service.dart               # Export PDF & Excel
  providers/app_providers.dart        # Semua Riverpod provider
  screens/                            # 9 halaman utama + sub-screen
  widgets/common_widgets.dart
  main.dart
pubspec.yaml
```

## Cara Build ke APK

Project ini berisi **source code Dart lengkap (lib/ + pubspec.yaml)**.
Folder platform (`android/`, `ios/`) belum di-generate di sini karena
berisi ratusan file biner/boilerplate (gradle wrapper, Podfile, dsb) yang
harus dibuat oleh Flutter SDK itu sendiri — bukan ditulis tangan.

Jalankan langkah berikut di Termux atau komputer yang sudah terinstall
Flutter SDK:

```bash
# 1. Buat wrapper project (sekali saja, generate folder android/ios)
cd garasi_abah_bontot
flutter create --platforms=android --org com.garasiabahbontot .

# 2. Install dependency
flutter pub get

# 3. Jalankan di device/emulator untuk testing
flutter run

# 4. Build APK release
flutter build apk --release
```

APK hasil build ada di:
`build/app/outputs/flutter-apk/app-release.apk`

> Catatan Termux: build APK penuh (Gradle + Android SDK) **tidak bisa**
> dijalankan langsung di Termux tanpa root/proot karena butuh Android SDK
> build-tools. Alternatif: gunakan **Codemagic / GitHub Actions / Android
> Studio di PC** untuk proses `flutter build apk`, lalu APK-nya di-transfer
> ke HP. Untuk development/debug sehari-hari, `flutter run` ke device yang
> terhubung via `adb` (termasu dari Termux dengan `termux-adb`) tetap bisa
> dipakai untuk live-reload selama coding.

## Fitur yang Sudah Diimplementasikan

- ✅ Database SQLite lengkap (periode, motor, motor_cost, penjualan,
  pemasukan, pengeluaran, kasbon, cash_flow, saldo, pembagian_laba, audit_log)
- ✅ Pembelian motor: harga beli + biaya (transportasi, bensin, service, dst)
  → otomatis hitung total modal, kurangi cash, catat cash_flow (dalam 1 DB transaction)
- ✅ Penjualan motor dengan **aturan Calo**: laba tetap dihitung, tapi
  `bonus_eligible = false` sehingga tidak masuk pembagian hadiah 10%
- ✅ Kasbon sebagai piutang (bukan pengeluaran rugi): cash berkurang saat
  ambil, cash bertambah saat lunas — tidak mengurangi laba bersih
- ✅ Sistem periode pembukuan manual (buat & tutup buku manual, bukan otomatis per bulan)
- ✅ Perhitungan laba bersih = total laba motor − pengeluaran lain
- ✅ Pembagian laba otomatis: Abah 25% | Iki 27.5% | Andri 22.5% | Ilham 15% | Hadiah 10%
- ✅ Hadiah penjualan dibagi rata ke unit internal terjual (Calo dikecualikan)
- ✅ Dashboard (modal, cash, saldo bank, nilai stok, piutang kasbon, total aset)
- ✅ Motor Inventory (tambah, biaya susulan, detail, riwayat biaya, search, filter)
- ✅ Laporan periode (laba per motor, pengeluaran per kategori, penjualan per orang)
- ✅ Export PDF & Excel
- ✅ Backup & Restore database (via share sheet / file picker)
- ✅ Audit log otomatis di setiap create/update pada semua tabel transaksi

## Yang Perlu Ditambahkan Sendiri (opsional, sesuai kebutuhan)

- Custom app icon (`assets/icons/`) — pasang lalu jalankan `flutter_launcher_icons` jika mau
- Splash screen custom
- Autentikasi/PIN lock lokal jika ingin proteksi tambahan
- Unit test tambahan di folder `test/` (struktur dasar Clean Architecture
  sudah memisahkan repository/service sehingga mudah di-mock untuk testing)
