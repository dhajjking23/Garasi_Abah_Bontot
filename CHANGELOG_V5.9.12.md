# V5.9.12 — Audit & perbaikan indikator aset / pemasukan

STATUS VERIFIKASI: kode ditulis TANPA toolchain Flutter/Dart (tidak tersedia
di lingkungan kerja). `dart format`, `flutter analyze`, `flutter test`, dan
build BELUM dijalankan. Jalankan sendiri sebelum dipakai (lihat bawah).

## Temuan
- P0 `PeriodeModel.modalAwal` = cash + bank saja. Periode carry-forward
  menyimpan modal di `modalAwalTotalAset`, jadi `modalAwalPeriode` = 0 dan
  "Selisih Aset vs Modal Awal" = Total Aset (Rp58.387.100 pada screenshot).
- P0 `LaporanService.totalPemasukan` menjumlahkan SELURUH tabel pemasukan,
  termasuk jurnal otomatis 'Penjualan Motor' (dibuat PenjualanRepository)
  dan 'Tambah Modal'. Layar menamainya "Total Pemasukan Lain" -> sama dengan
  omzet (Rp42.950.000). Bukan duplikasi record, tapi salah label/agregasi.
- P1 Rumus selisih tidak mengurangi kewajiban (utang partner).
- P1 (belum diubah, perlu keputusan pemilik) lihat "Known issues".

## Perubahan
- BARU lib/services/financial_indicators.dart: modal acuan, IndikatorAset,
  pemisahan pemasukan, deteksi dugaan duplikat (hanya peringatan).
- lib/services/laporan_service.dart: field `indikator`, `pemasukanBreakdown`,
  `peringatanDuplikat`; `labaPerubahanModal` ditandai deprecated.
- lib/screens/dashboard/total_aset_detail_screen.dart, laporan_screen.dart,
  export_service.dart: label & rumus baru; "Belum dapat dihitung" bila modal
  acuan belum ada.
- BARU test/financial_indicators_test.dart.

## Rumus
Total Aset = Cash + Bank + Stok + Kasbon + Piutang Penjualan + Piutang Partner
Aset Bersih = Total Aset - Total Kewajiban
Selisih = Aset Bersih - Modal Acuan (diagnostik, BUKAN laba)
Modal Acuan = modalAwalTotalAset (carry-forward) | modalAwalCash+Bank (periode pertama) | belum dihitung

## Migrasi / backup
Tidak ada perubahan skema atau data. Tidak perlu migrasi.

## Known issues (butuh keputusan pemilik)
1. `hitungPreview` (laba bersih) hanya mengurangi kategori 'Pengeluaran Lain'
   (nominal); biaya admin bank tidak ikut. Sementara layar "Total
   Pengeluaran" = semua kategori + biaya admin. Angkanya memang berbeda.
2. Total Pengeluaran menyertakan kategori 'Kasbon' (piutang/aset, bukan beban).
3. Biaya transfer kasbon dijumlah global (tanpa periode_id).
4. Total aset memakai saldo global saat ini, bukan "as of" akhir periode.
5. Rekonsiliasi Aset = Kewajiban + Ekuitas belum diuji dengan data nyata.

## Cara verifikasi
    dart format lib test
    flutter analyze
    flutter test
