# INSTALASI — GARASI ABAH BONTOT V4

## 1. Setup Signing (WAJIB sebelum build release)
Lihat `android/KEYSTORE_SETUP.md`. Tanpa `android/key.properties`, build akan
fallback ke debug signing dan **tidak bisa update APK lama tanpa uninstall**.

## 2. Build APK
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## 3. Install / Update di Poco F3 (Master)
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```
`-r` = reinstall/replace, data SQLite tetap ada selama `applicationId` & signature sama.

## 4. Setup Termux Server (Poco F3)
```bash
pkg install python tmux termux-api -y
termux-setup-storage
cp -r garasi_server ~/garasi_server
cd ~/garasi_server
pip install -r requirements.txt
```
Edit `config.json`:
- `db_path` → path database aplikasi (lihat `flutter: getApplicationDocumentsDirectory()`, biasanya `/data/data/com.garasiabahbontot.garasi_abah_bontot/app_flutter/garasi_abah_bontot.db` — akses via `run-as` atau app export path).
- `api_token` → ganti dari default, catat untuk diisi di app Partner.

Jalankan manual:
```bash
bash start_server.sh
```

## 5. Auto-start saat HP restart
```bash
pkg install termux-boot -y
mkdir -p ~/.termux/boot
cp termux_boot/start-garasi-server ~/.termux/boot/
chmod +x ~/.termux/boot/start-garasi-server
```
Install app **Termux:Boot** dari F-Droid (bukan Play Store), buka sekali agar Android mengizinkan auto-start.

## 6. Setup HP Partner (Viewer)
1. Install APK yang sama.
2. Login pakai akun `partner` (password diatur OWNER_ADMIN via menu Manajemen User).
3. Buka menu **Server**, isi IP Poco F3 (cek lewat `ip addr` di Termux atau menu Server di app Master) + API Token yang sama dengan `config.json`.

## 7. Login Default (WAJIB DIGANTI SETELAH INSTALL PERTAMA)
| Role | Username | Password |
|---|---|---|
| OWNER_ADMIN | andri | andri123 |
| VIEWER | partner | partner123 |

Ganti password lewat **Pengaturan → Manajemen User**.

## 8. Test Wajib (sesuai spesifikasi)
- **Test Update**: install APK lama → isi data → install APK V4 tanpa uninstall → data harus tetap ada.
- **Test Backup**: backup → hapus app → install ulang → restore → data kembali.
- **Test Server**: input transaksi di Master → cek Partner menerima update; matikan server → Partner tetap bisa buka data lama (offline cache); nyalakan lagi → sync otomatis.
