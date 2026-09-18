# GARASI ABAH BONTOT V3.1
## Safe Update Guide

---

## ✅ Update Safety Guarantee

GARASI ABAH BONTOT V3.1 adalah **SAFE UPDATE** yang dapat dipasang di atas instalasi V3 tanpa:

❌ Uninstall aplikasi  
❌ Hapus data aplikasi  
❌ Reset database  
❌ Kehilangan transaksi lama  

✅ Semua data V3 tetap 100% aman dan dapat diakses

---

## 📋 Pre-Update Checklist

Sebelum melakukan update, pastikan:

### 1. Backup Data
```bash
# Backup database sebelum update (recommended tapi tidak wajib)
- Di app: Menu Pembukuan → Backup Database
- Simpan file backup di lokasi aman (Google Drive, cloud storage, dll)
```

### 2. Check Device Storage
- Pastikan device memiliki space minimal 50MB untuk APK
- Jangan update saat storage critical

### 3. Network Connection
- Gunakan WiFi stabil untuk download APK
- Jangan update via data mobile (risiko terputus)

### 4. Battery Status
- Charge device minimal 80%
- Jangan update saat charging (risiko interrupt)

### 5. App Version
- Verifikasi versi saat ini adalah V3 (`Setting → App Version`)
- Jika sudah V3.1, update tidak perlu diulang

---

## 🔄 Update Process

### Step 1: Download APK V3.1
```
1. Dapatkan file: GARASI_ABAH_BONTOT_V3.1_PATCH_FINAL.apk
2. Simpan di smartphone
3. Verifikasi ukuran file (± 30-40 MB)
```

### Step 2: Install Update
```
1. Buka file manager → Cari APK file
2. Tap file → "Install"
3. Android akan ask permission → "Install anyway"
   (Karena berbeda versi/signature vs Play Store)
4. Tunggu proses selesai (1-2 menit)
5. Jangan close atau interrupt proses
```

### Step 3: Verification
```
1. App akan auto-launch setelah install
2. Tunggu loading screen selesai (± 30 detik)
3. Jika loading lama (>1 menit), force close & relaunch
4. Check App Version: Harus V3.1 (1.0.1+2)
```

### Step 4: Data Verification
```
1. Tap Menu Pembukuan → Riwayat Periode
   ✓ Semua periode lama harus muncul
   
2. Tap Menu Penjualan → Daftar Penjualan
   ✓ Semua penjualan lama harus muncul
   
3. Tap Menu Laporan → Laporan Periode
   ✓ Pilih periode lama → Laporan harus muncul dengan data benar
   
4. Tap Menu Dashboard
   ✓ Saldo modal, cash, bank harus correct
```

---

## 🛠️ Troubleshooting

### Issue 1: "Installation Failed" Error

**Penyebab:** Signature mismatch atau corrupted file

**Solusi:**
```
1. Uninstall app → App Settings → Uninstall
2. Restart device
3. Download APK file ulang (verify checksum)
4. Install ulang
5. Jika masih gagal: Clear Play Store cache
   Settings → Apps → Play Store → Storage → Clear Cache → Try again
```

### Issue 2: App Force Close Saat Startup

**Penyebab:** Database migration issue atau corrupted data

**Solusi:**
```
1. Jangan force close, tunggu proses selesai (30-60 detik)
2. Jika tetap force close:
   a. Restart device
   b. Relaunch app
   c. Jika masih error: Check console logs
      adb logcat | grep "garasi_abah_bontot"
3. Last resort: Contact developer dengan error log
```

### Issue 3: Data Tidak Muncul Setelah Update

**Penyebab:** Cache issue atau database lock

**Solusi:**
```
1. Restart device
2. Clear app cache: Settings → Apps → GARASI ABAH BONTOT → Storage → Clear Cache
3. Relaunch app
4. Jika masih tidak ada: Check database file
   - Backup file sebelumnya masih ada
   - Database migration harus complete
5. Contact developer jika issue persist
```

### Issue 4: Saldo Tidak Sesuai

**Penyebab:** Split pemasukan belum ter-populate dengan benar

**Solusi:**
```
1. Jangan edit transaksi sebelum verify
2. Buka setiap laporan periode → check calculation
3. Jika ada discrepancy:
   a. Document transaksi yang tidak match
   b. Check audit log untuk tracking changes
   c. Contact developer dengan detail
```

---

## 📊 Data Integrity Checks

Setelah update selesai, lakukan verifikasi:

### Check 1: Database Version
```
Di app: Menu Pembukuan → Info Aplikasi
- Database Version harus: 10 (bukan 9)
- App Version harus: 1.0.1+2
```

### Check 2: Modal & Saldo
```
Menu Modal & Saldo Bank:
- Modal Cash: Harus sama dengan sebelum update
- Modal Bank: Harus sama dengan sebelum update
- Saldo Cash: Harus sama dengan sebelum update
- Saldo Bank: Harus sama dengan sebelum update
```

### Check 3: Transaksi Count
```
Menu Laporan → Pilih Periode Awal
- Jumlah penjualan motor
- Jumlah pengeluaran
- Jumlah pemasukan
- Semua HARUS sama dengan sebelum update
```

### Check 4: Audit Log
```
Menu Pembukuan → Audit Log
- Cek timestamp: seharusnya ada entries untuk "Upgrade V3 → V3.1"
- Migrations harus tercatat
- Jangan ada "ERROR" entries
```

---

## ✨ New Features Testing

Setelah verifikasi data lama, test fitur baru:

### Test 1: Transfer Admin Fee
```
1. Buat Pengeluaran baru
2. Sumber: BANK
3. Pilih Jenis Transfer: BI_FAST
4. Nominal: Rp100.000
5. Verifikasi:
   - Biaya admin: Rp2.500 (otomatis)
   - Total: Rp102.500
   - Saldo berkurang Rp102.500
```

### Test 2: Income CAMPURAN
```
1. Buat Pemasukan baru (atau edit yang existing)
2. Sumber: CAMPURAN
3. Input cash: Rp3.000.000
4. Input bank: Rp2.000.000
5. Total: Rp5.000.000
6. Verifikasi:
   - Saldo cash +3jt
   - Saldo bank +2jt
   - Total +5jt ✓
```

### Test 3: Edit Tanggal
```
1. Pilih transaksi existing
2. Tap "Edit" atau "..."
3. Edit tanggal: ubah ke tanggal berbeda
4. Verifikasi:
   - Tanggal berubah di list
   - Laporan periode re-calculate
   - Audit log tercatat perubahan
```

---

## 🔙 Rollback (Jika Diperlukan)

Jika ada critical issue dan harus rollback ke V3:

```
1. Uninstall V3.1
   Settings → Apps → GARASI ABAH BONTOT → Uninstall

2. JANGAN clear data app
   (Database file tetap tersimpan)

3. Install V3 APK kembali
   (Gunakan APK V3 original)

4. App akan auto-load database V10
   (Database compatibility backward)

5. Jika ada issue:
   - Restore dari backup database
   - V10 database compatible dengan V3 reader
```

---

## 📞 Support & Contact

Jika ada pertanyaan atau issue:

### Information to Provide
1. Device: [Model, Android version]
2. App Version: [V3 atau V3.1?]
3. Database Version: [9 atau 10?]
4. Error message: [Exact message]
5. Steps to reproduce: [Clear steps]
6. Screenshots: [Error screen if possible]
7. Audit log snippet: [Copy relevant entries]

### Contact
- Whatsapp: [Number]
- Email: [Email]
- GitHub Issues: [Link]

---

## ✅ Post-Update Checklist

Setelah update berhasil, pastikan:

- [ ] App version: 1.0.1+2
- [ ] Database version: 10
- [ ] Semua periode lama muncul
- [ ] Semua transaksi lama muncul
- [ ] Saldo & modal sesuai
- [ ] Laporan dapat di-generate
- [ ] Transfer fee berfungsi
- [ ] Income CAMPURAN berfungsi
- [ ] Edit tanggal berfungsi
- [ ] Audit log tercatat

---

## 🎉 Update Complete

Jika semua checklist done, update V3.1 berhasil! 🎊

---

## 📚 Additional Resources

- README.md: Overview aplikasi
- CHANGELOG_V3.1.md: Technical changes
- CHANGELOG_V3.md: Previous update notes

---

**Last Updated:** August 17, 2026  
**Version:** 1.0.1+2  
**Database:** v10
