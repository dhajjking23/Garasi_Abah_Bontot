/// Konstanta global aplikasi Garasi Abah Bontot
/// Semua nilai default, kategori, dan aturan bisnis didefinisikan di sini
/// agar tidak hardcode tersebar di banyak file.
class AppConstants {
  AppConstants._();

  static const String appName = 'Garasi Abah Bontot';
  static const String dbName = 'garasi_abah_bontot.db';
  static const int dbVersion = 16;

  // ==========================================================
  // V4 — SERVER / SYNC
  // ==========================================================
  static const String serverId = 'GAB-001';
  static const String serverOwnerName = 'Andri';
  static const int serverDefaultPort = 8000;
  static const String roleOwnerAdmin = 'OWNER_ADMIN';
  static const String roleViewer = 'VIEWER';

  // ==========================================================
  // KARYAWAN DEFAULT (internal / berhak dapat pembagian laba & bonus)
  // ==========================================================
  static const List<String> karyawanDefault = [
    'Abah',
    'Iki',
    'Andri',
    'Ilham',
  ];

  /// Daftar penjual yang muncul di form penjualan (internal + calo)
  static const List<String> daftarPenjual = [
    'Abah',
    'Iki',
    'Andri',
    'Ilham',
    'Calo',
  ];

  static const String penjualCalo = 'Calo';

  // ==========================================================
  // KATEGORI BIAYA MOTOR (motor_cost)
  // ==========================================================
  static const List<String> kategoriMotorCost = [
    'Pembelian Unit',
    'Transportasi',
    'Bensin',
    'Makan COD',
    'Rokok COD',
    'Service',
    'Sparepart',
    'Gajih Service',
    'Finishing',
  ];

  // ==========================================================
  // KATEGORI PEMASUKAN
  // ==========================================================
  static const List<String> kategoriPemasukan = [
    'Tambah Modal',
    'Penjualan Motor',
  ];

  // ==========================================================
  // KATEGORI PENGELUARAN
  // ==========================================================
  static const List<String> kategoriPengeluaran = [
    'Kasbon',
    'Pengeluaran Lain',
  ];

  // ==========================================================
  // KATEGORI CUSTOM (disimpan user, tabel kategori_custom)
  // "Tambah Jenis Baru" BUKAN nama kategori — ini sentinel value di
  // dropdown yang memicu dialog untuk membuat kategori baru.
  // ==========================================================
  static const String kategoriTipePemasukan = 'PEMASUKAN';
  static const String kategoriTipePengeluaran = 'PENGELUARAN';
  static const String kategoriTipeMotorCost = 'MOTOR_COST';
  static const String kategoriTambahBaruSentinel = '__TAMBAH_JENIS_BARU__';

  // ==========================================================
  // STATUS
  // ==========================================================
  static const String statusMotorTersedia = 'TERSEDIA';
  static const String statusMotorTerjual = 'TERJUAL';

  static const String statusPeriodeAktif = 'AKTIF';
  static const String statusPeriodeTutup = 'TUTUP';

  static const String statusKasbonBelumLunas = 'BELUM_LUNAS';
  static const String statusKasbonLunas = 'LUNAS';

  // ==========================================================
  // CASH FLOW TIPE
  // ==========================================================
  static const String cashFlowMasuk = 'MASUK';
  static const String cashFlowKeluar = 'KELUAR';

  static const String cashFlowRefMotorBeli = 'PEMBELIAN_MOTOR';
  static const String cashFlowRefMotorCost = 'BIAYA_MOTOR';
  static const String cashFlowRefPenjualan = 'PENJUALAN_MOTOR';
  static const String cashFlowRefPemasukan = 'PEMASUKAN';
  static const String cashFlowRefPengeluaran = 'PENGELUARAN';
  static const String cashFlowRefKasbonAmbil = 'KASBON_AMBIL';
  static const String cashFlowRefKasbonBayar = 'KASBON_BAYAR';
  static const String cashFlowRefDepositBank = 'DEPOSIT_KE_BANK';
  static const String cashFlowRefTarikTunai = 'TARIK_TUNAI';
  static const String cashFlowRefAdjustment = 'PENYESUAIAN_SALDO';
  static const String cashFlowRefDanaTalangBeri = 'DANA_TALANG_BERI';
  static const String cashFlowRefDanaTalangTerima = 'DANA_TALANG_TERIMA';
  static const String cashFlowRefDanaTalangBayar = 'DANA_TALANG_BAYAR';
  static const String cashFlowRefAdminTransfer = 'ADMINISTRASI_BANK';
  static const String cashFlowRefPenjualanCicilan = 'PENJUALAN_CICILAN';
  static const String cashFlowRefModalAwalPeriode = 'MODAL_AWAL_PERIODE';
  static const String cashFlowRefGajihan = 'GAJIHAN';
  static const String kategoriGaji = 'Gaji';

  /// Status pembayaran penjualan motor (mendukung DP / cicilan).
  static const String statusPembayaranLunas = 'LUNAS';
  static const String statusPembayaranBelumLunas = 'BELUM_LUNAS';

  /// Sumber kas untuk setiap baris cash_flow: CASH (dompet fisik) atau
  /// BANK (rekening/saldo bank). Dipakai untuk memisahkan riwayat Cash
  /// dan riwayat Saldo Bank pada layar yang berbeda.
  static const String sumberCash = 'CASH';
  static const String sumberBank = 'BANK';
  static const String sumberCampuran = 'CAMPURAN';

  /// Daftar destinasi uang masuk (pemasukan)
  static const List<String> daftarSumberPemasukan = [
    sumberCash,
    sumberBank,
    sumberCampuran,
  ];

  // ==========================================================
  // JENIS MODAL (modal_history)
  // ==========================================================
  static const String modalJenisCash = 'CASH';
  static const String modalJenisBank = 'BANK';
  static const String modalAksiTambah = 'TAMBAH';
  static const String modalAksiKurang = 'KURANG';
  static const String modalAksiEdit = 'EDIT';

  // ==========================================================
  // METODE PEMBAYARAN (motor, penjualan, pengeluaran)
  // ==========================================================
  static const String metodeCash = 'CASH';
  static const String metodeTransfer = 'TRANSFER';
  static const String metodeCampuran = 'CAMPURAN';

  // ==========================================================
  // BIAYA ADMIN TRANSFER
  // ==========================================================
  static const double adminTransferGratis = 0;
  static const double adminTransferBiFast = 2500;
  static const double adminTransferRealtime = 6500;
  static const String kategoriAdministrasiBank = 'Administrasi Bank';
  static const String jenisTransferGratis = 'GRATIS';
  static const String jenisTransferBiFast = 'BI_FAST';
  static const String jenisTransferRealtime = 'REALTIME';
  static const List<String> daftarJenisTransfer = [
    jenisTransferGratis,
    jenisTransferBiFast,
    jenisTransferRealtime,
  ];

  // ==========================================================
  // DANA TALANG PARTNER
  // ==========================================================
  static const String danaTalangSayaMenalangi = 'SAYA_MENALANGI';
  static const String danaTalangSayaMenerima = 'SAYA_MENERIMA';

  /// Bentuk dana talang saat SAYA_MENERIMA (spesifikasi V3 #8B):
  /// - TUNAI: partner benar-benar transfer/kasih uang cash ke saya ->
  ///   Cash/Saldo Bank saya bertambah.
  /// - NON_TUNAI: partner membelikan/membayarkan sesuatu ATAS NAMA saya
  ///   (mis. bayar motor duluan) -> BUKAN uang masuk, Cash/Saldo Bank
  ///   saya TIDAK berubah, hanya hutang yang tercatat. Baru saat saya
  ///   bayar kembali, Cash/Saldo Bank saya berkurang seperti biasa.
  static const String bentukTalanganTunai = 'TUNAI';
  static const String bentukTalanganNonTunai = 'NON_TUNAI';

  static const String statusDanaTalangBelumLunas = 'BELUM_LUNAS';
  static const String statusDanaTalangSebagianLunas = 'SEBAGIAN_LUNAS';
  static const String statusDanaTalangLunas = 'LUNAS';
  static const String statusDanaTalangBatal = 'BATAL';

  // ==========================================================
  // ATURAN PEMBAGIAN LABA (persentase dari laba bersih periode)
  // Total harus 100%: 25 + 27.5 + 22.5 + 15 + 10 = 100
  // ==========================================================
  static const double persenAbah = 0.25;
  static const double persenIki = 0.275;
  static const double persenAndri = 0.225;
  static const double persenIlham = 0.15;
  static const double persenHadiahPenjualan = 0.10;

  static const Map<String, double> pembagianLabaUtama = {
    'Abah': persenAbah,
    'Iki': persenIki,
    'Andri': persenAndri,
    'Ilham': persenIlham,
  };

  /// Penjual internal yang berhak atas hadiah penjualan (bonus 10%).
  /// Calo TIDAK termasuk.
  static const List<String> penjualInternalBerhakBonus = [
    'Abah',
    'Iki',
    'Andri',
    'Ilham',
  ];

  // ==========================================================
  // AUDIT LOG ACTION TYPE
  // ==========================================================
  static const String auditCreate = 'CREATE';
  static const String auditUpdate = 'UPDATE';
  static const String auditDelete = 'DELETE';
}
