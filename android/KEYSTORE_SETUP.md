# KEYSTORE SETUP — GARASI ABAH BONTOT V4

## Jika keystore V3.1 (upload-keystore.jks) SUDAH ADA

1. Copy `upload-keystore.jks` ke folder `android/`.
2. Copy `android/key.properties.template` menjadi `android/key.properties`.
3. Isi `storePassword`, `keyPassword`, `keyAlias` sesuai keystore lama.
4. Build: `flutter build apk --release`.
5. APK hasil akan bersignature SAMA dengan APK lama → update tanpa uninstall.

**JANGAN generate keystore baru jika sudah ada V3.1 terpasang di HP** —
signature akan berbeda dan Android akan menolak update in-place.

## Jika keystore BELUM PERNAH dibuat (instalasi pertama V4, belum ada V3.1 live)

Generate SEKALI, lalu simpan permanen untuk semua rilis berikutnya (V4, V5, V6, ...):

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Jawab prompt (nama, organisasi, dll) lalu:

1. Pindahkan `upload-keystore.jks` ke `android/`.
2. Copy `android/key.properties.template` → `android/key.properties`, isi sesuai password yang dipakai saat generate.
3. **BACKUP `upload-keystore.jks` dan `key.properties` di tempat aman di luar repo** (Google Drive pribadi, dsb). Jika file ini hilang, APK tidak akan bisa di-update lagi selamanya — pengguna harus uninstall dan install ulang (dan kehilangan data jika lupa backup database).

## Verifikasi signature APK lama vs baru (opsional, sebelum distribusi)

```bash
apksigner verify --print-certs app-old.apk
apksigner verify --print-certs app-new-release.apk
```

Pastikan fingerprint SHA-256 sertifikat pada kedua APK identik.
