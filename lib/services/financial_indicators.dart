import '../models/pemasukan_model.dart';
import '../models/penjualan_model.dart';
import '../models/periode_model.dart';

/// Kategori pemasukan yang BUKAN pendapatan lain:
/// - 'Penjualan Motor' dibuat otomatis oleh PenjualanRepository (jurnal
///   penerimaan kas dari penjualan; omzetnya sudah dihitung di tabel
///   penjualan, jadi menjumlahkannya lagi = hitung ganda).
/// - 'Tambah Modal' adalah setoran modal (ekuitas), bukan pendapatan.
const String kKategoriPemasukanPenjualan = 'Penjualan Motor';
const String kKategoriPemasukanTambahModal = 'Tambah Modal';

/// Hasil pemisahan total tabel `pemasukan` menurut sifat ekonominya.
class PemasukanBreakdown {
  /// Kas diterima dari penjualan motor (jurnal otomatis; bisa < omzet jika DP).
  final double penerimaanPenjualan;

  /// Setoran modal — menambah kas & modal, bukan pendapatan.
  final double setoranModal;

  /// Pemasukan non-penjualan, non-modal (benar-benar pendapatan lain).
  final double pendapatanLain;

  const PemasukanBreakdown({
    required this.penerimaanPenjualan,
    required this.setoranModal,
    required this.pendapatanLain,
  });

  /// Seluruh baris tabel pemasukan (arus kas masuk bruto).
  double get totalPenerimaanKas =>
      penerimaanPenjualan + setoranModal + pendapatanLain;
}

PemasukanBreakdown pisahkanPemasukan(Iterable<PemasukanModel> daftar) {
  double penjualan = 0, modal = 0, lain = 0;
  for (final p in daftar) {
    switch (p.kategori) {
      case kKategoriPemasukanPenjualan:
        penjualan += p.nominal;
        break;
      case kKategoriPemasukanTambahModal:
        modal += p.nominal;
        break;
      default:
        lain += p.nominal;
    }
  }
  return PemasukanBreakdown(
    penerimaanPenjualan: penjualan,
    setoranModal: modal,
    pendapatanLain: lain,
  );
}

/// Modal acuan hasil penelusuran model periode.
class ModalAcuan {
  /// null = belum dapat dihitung (tidak pernah dianggap 0 diam-diam).
  final double? nilai;
  final String label;
  const ModalAcuan(this.nilai, this.label);
  bool get tersedia => nilai != null;
}

/// Tentukan modal acuan dari periode:
/// - periode carry-forward: `modalAwalTotalAset` (snapshot total aset
///   akhir closing sebelumnya; modalAwalCash/Bank = 0 di kasus ini).
/// - periode pertama: `modalAwalCash + modalAwalBank` (setoran modal awal).
/// - keduanya 0/negatif/periode null: belum dapat dihitung.
///
/// BUG LAMA: LaporanService memakai `periode.modalAwal` (= cash + bank
/// saja), yang SELALU 0 pada periode carry-forward sehingga "selisih"
/// jadi sama dengan total aset.
ModalAcuan tentukanModalAcuan(PeriodeModel? periode) {
  if (periode == null) return const ModalAcuan(null, 'Periode tidak ditemukan');
  if (periode.modalAwalTotalAset > 0) {
    return ModalAcuan(
        periode.modalAwalTotalAset, 'Modal awal periode (total aset carry-forward)');
  }
  final setoran = periode.modalAwalCash + periode.modalAwalBank;
  if (setoran > 0) {
    return ModalAcuan(setoran, 'Modal awal periode (setoran Cash + Bank)');
  }
  return const ModalAcuan(null, 'Modal awal periode belum diatur');
}

/// Indikator aset/kewajiban/modal. Murni kalkulasi; DIAGNOSTIK, bukan laba.
class IndikatorAset {
  final double totalAset;
  final double totalKewajiban;
  final ModalAcuan modalAcuan;

  const IndikatorAset({
    required this.totalAset,
    required this.totalKewajiban,
    required this.modalAcuan,
  });

  /// Aset Bersih = Total Aset - Total Kewajiban.
  double get asetBersih => totalAset - totalKewajiban;

  /// Aset Bersih - Modal Acuan (null jika modal acuan belum tersedia).
  double? get selisihAsetBersihVsModal =>
      modalAcuan.tersedia ? asetBersih - modalAcuan.nilai! : null;

  /// Total Aset - Modal Acuan (null jika modal acuan belum tersedia).
  double? get selisihTotalAsetVsModal =>
      modalAcuan.tersedia ? totalAset - modalAcuan.nilai! : null;

  List<String> get peringatan => [
        if (!modalAcuan.tersedia)
          'Modal acuan belum diatur — selisih belum dapat dihitung.',
        if (totalKewajiban > 0)
          'Total Aset belum dikurangi kewajiban; gunakan Aset Bersih untuk '
              'dibandingkan dengan modal.',
      ];
}

/// Peringatan DUGAAN duplikasi — TIDAK menghapus/mengubah data apa pun.
///
/// 1. Dua+ baris 'Penjualan Motor' dengan referensi_id yang sama
///    (satu penjualan hanya membuat satu jurnal pemasukan).
/// 2. Baris 'Penjualan Motor' yang referensi_id-nya tidak cocok dengan
///    penjualan mana pun pada daftar yang diberikan.
/// 3. Pemasukan MANUAL (non-penjualan, non-modal, tanpa referensi) dengan
///    nominal & tanggal sama persis dengan sebuah penjualan — mungkin
///    penjualan yang dicatat ulang manual (hanya dugaan; bisa sah).
List<String> deteksiDugaanDuplikat({
  required List<PenjualanModel> penjualan,
  required List<PemasukanModel> pemasukan,
}) {
  final hasil = <String>[];
  final idPenjualan = penjualan.map((p) => p.id).whereType<int>().toSet();

  final jumlahPerRef = <int, int>{};
  for (final m in pemasukan) {
    if (m.kategori == kKategoriPemasukanPenjualan && m.referensiId != null) {
      jumlahPerRef[m.referensiId!] = (jumlahPerRef[m.referensiId!] ?? 0) + 1;
    }
  }
  jumlahPerRef.forEach((ref, n) {
    if (n > 1) {
      hasil.add('Penjualan #$ref punya $n baris pemasukan otomatis '
          '(seharusnya 1) — periksa manual.');
    }
  });

  for (final m in pemasukan) {
    if (m.kategori == kKategoriPemasukanPenjualan &&
        m.referensiId != null &&
        !idPenjualan.contains(m.referensiId)) {
      hasil.add('Pemasukan "Penjualan Motor" #${m.id} merujuk penjualan '
          '#${m.referensiId} yang tidak ditemukan di periode ini.');
    }
  }

  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  for (final m in pemasukan) {
    final manual = m.kategori != kKategoriPemasukanPenjualan &&
        m.kategori != kKategoriPemasukanTambahModal &&
        m.referensiId == null;
    if (!manual) continue;
    final cocok = penjualan.any((p) =>
        (p.hargaJual - m.nominal).abs() < 0.5 &&
        sameDay(p.tanggalJual, m.tanggal));
    if (cocok) {
      hasil.add('Pemasukan manual "${m.kategori}" #${m.id} bernominal sama '
          'dan bertanggal sama dengan sebuah penjualan — duga duplikat, '
          'periksa manual (tidak dihapus otomatis).');
    }
  }
  return hasil;
}
