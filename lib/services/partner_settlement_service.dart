import 'package:sqflite/sqflite.dart';
import '../core/constants/app_constants.dart';
import '../repositories/dana_talang_repository.dart';
import '../repositories/kasbon_repository.dart';
import '../repositories/gajihan_repository.dart';
import 'pembagian_laba_service.dart';

/// V5.8/V5.9 — PARTNER NET SETTLEMENT ENGINE.
///
/// Formula (diaudit ulang V5.9, sesuai spesifikasi eksplisit):
///
///   NET SETTLEMENT =
///       HAK LABA PARTNER
///     + DANA TALANG YANG MENJADI HAK PARTNER   (partner pernah menalangi
///       kita, sisa belum kita kembalikan -> ini KEWAJIBAN kita ke dia,
///       jadi MENAMBAH yang harus dibayarkan)
///     - KASBON PARTNER (belum lunas)
///     - PIUTANG PARTNER (kita pernah menalangi dia, sisa belum dia
///       kembalikan -> PIUTANG kita ke dia, MENGURANGI yang dibayarkan)
///
/// "Piutang Partner" & "Dana Talang yang jadi hak partner" SENGAJA
/// sama-sama bersumber dari tabel dana_talang (beda `jenis`:
/// SAYA_MENALANGI vs SAYA_MENERIMA) — BUKAN dua tabel terpisah. Ini
/// disengaja untuk menghindari double counting: satu transaksi dana
/// talang hanya pernah muncul SEKALI, sebagai piutang ATAU sebagai
/// kewajiban, tidak pernah dua-duanya sekaligus dan tidak pernah dihitung
/// dua kali di sisi manapun.
///
/// PENTING (anti double-counting, per baris demi baris):
///  - Semua angka di-filter PER NAMA PARTNER (`namaKaryawan`/`namaPartner
///    == nama`) — TIDAK PERNAH mengurangi "total semua kasbon" dari
///    "total semua laba". Kasbon/dana talang milik Iki hanya memotong
///    hak Iki, tidak menyentuh hak Abah/Andri/Ilham.
///  - Kasbon TIDAK PERNAH masuk sebagai biaya/expense (tetap piutang di
///    tabel `kasbon`, terpisah total dari `pengeluaran`) — dicek ulang di
///    kasbon_repository.dart, tidak ada tulis-silang ke tabel pengeluaran.
///  - Biaya motor (motor_cost) TIDAK PERNAH masuk sebagai pengeluaran
///    operasional — cuma menambah `motor.totalModal`, dipakai SEKALI di
///    formula laba (hargaJual - biayaCalo - modalMotor). Dicek ulang:
///    motor_repository.dart tidak pernah menulis ke tabel `pengeluaran`.
///
/// SENGAJA TIDAK menyentuh:
///  - PembagianLabaService.hitungPreview()/tutupBukuDanBagiLaba() — formula
///    gross (25/27.5/22.5/15% + bonus 10%) & histori tersimpan APA ADANYA.
///  - Kasbon/DanaTalang TIDAK otomatis ditandai lunas di sini. Ini murni
///    kalkulasi "berapa yang seharusnya dibayar" — pelunasan tetap aksi
///    manual terpisah (KasbonScreen/DanaTalangScreen), supaya tidak ada
///    uang berpindah otomatis tanpa konfirmasi eksplisit owner.
class PartnerNetSettlement {
  final String nama;
  final double persenBagi;
  final double hakLaba;
  /// V5.9.8 — Hadiah/bonus penjualan (10%) milik partner ini, kalau dia
  /// menjual unit internal periode ini. Sebelumnya HANYA ditampilkan
  /// terpisah di bawah kartu Net Settlement, sekarang ikut dihitung di
  /// [netSettlement] supaya kartu ini benar-benar menunjukkan "total
  /// yang akan diterima", bukan cuma sebagian.
  final double hadiahPenjualan;
  final double kasbonPartner;
  /// Dana talang yang MENJADI HAK partner (dia pernah menalangi kita).
  final double danaTalangHakPartner;
  /// Piutang kita ke partner (kita pernah menalangi dia).
  final double piutangPartner;
  /// V5.9.8 — total yang SUDAH DIAMBIL partner via Gajihan periode ini
  /// (lihat GajihanScreen). Dikurangi di sini supaya kartu "Net
  /// Settlement" di layar Pembagian Laba SINKRON dengan yang benar-benar
  /// akan dibayar `PembagianLabaService.tutupBukuDanBagiLaba()` — kalau
  /// tidak, dua layar ini akan menampilkan angka berbeda untuk hak yang
  /// sama (persis yang diminta: kedua tab harus saling terhubung).
  final double sudahDiambilGajihan;

  PartnerNetSettlement({
    required this.nama,
    required this.persenBagi,
    required this.hakLaba,
    this.hadiahPenjualan = 0,
    required this.kasbonPartner,
    required this.danaTalangHakPartner,
    required this.piutangPartner,
    this.sudahDiambilGajihan = 0,
  });

  double get netSettlement =>
      hakLaba +
      hadiahPenjualan +
      danaTalangHakPartner -
      kasbonPartner -
      piutangPartner -
      sudahDiambilGajihan;

  /// Nama lama, dipertahankan supaya UI yang sudah ada (V5.8) tidak perlu
  /// diubah kalau masih memakainya.
  double get netPayment => netSettlement;
}

class PartnerSettlementService {
  final Database db;
  final PembagianLabaService _pembagianLabaService;
  final KasbonRepository _kasbonRepo;
  final DanaTalangRepository _danaTalangRepo;
  final GajihanRepository _gajihanRepo;

  PartnerSettlementService(this.db)
      : _pembagianLabaService = PembagianLabaService(db),
        _kasbonRepo = KasbonRepository(db),
        _danaTalangRepo = DanaTalangRepository(db),
        _gajihanRepo = GajihanRepository(db);

  Future<List<PartnerNetSettlement>> hitungNetSettlement(int periodeId) async {
    final preview = await _pembagianLabaService.hitungPreview(periodeId);
    final kasbonPerNama = await _kasbonRepo.getPiutangPerKaryawan();
    final hubunganPartner = await _danaTalangRepo.getHubunganPerPartner();

    final hakLabaPerNama = <String, double>{
      'Abah': preview.bagianAbah,
      'Iki': preview.bagianIki,
      'Andri': preview.bagianAndri,
      'Ilham': preview.bagianIlham,
    };
    final hadiahPerNama = <String, double>{
      for (final b in preview.detailBonus) b.nama: b.totalBonus,
    };

    final hasil = <PartnerNetSettlement>[];
    for (final entry in AppConstants.pembagianLabaUtama.entries) {
      final nama = entry.key;
      // Filter PER NAMA -- inilah yang mencegah "total semua kasbon"
      // dikurangi dari "total semua laba" (wajib per individu).
      final hubungan =
          hubunganPartner.where((h) => h.namaPartner == nama).toList();
      final danaTalangHakPartner = hubungan.isEmpty ? 0.0 : hubungan.first.totalHutang;
      final piutangPartner = hubungan.isEmpty ? 0.0 : hubungan.first.totalPiutang;
      final sudahDiambil =
          await _gajihanRepo.getTotalGajiDiambilPeriode(nama, periodeId);
      hasil.add(PartnerNetSettlement(
        nama: nama,
        persenBagi: entry.value,
        hakLaba: hakLabaPerNama[nama] ?? 0,
        hadiahPenjualan: hadiahPerNama[nama] ?? 0,
        kasbonPartner: kasbonPerNama[nama] ?? 0,
        danaTalangHakPartner: danaTalangHakPartner,
        piutangPartner: piutangPartner,
        sudahDiambilGajihan: sudahDiambil,
      ));
    }
    return hasil;
  }
}
