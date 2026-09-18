import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../core/utils/app_formatter.dart';
import '../models/periode_model.dart';
import '../models/motor_cost_model.dart';
import '../models/pengeluaran_model.dart';
import '../repositories/motor_repository.dart';
import '../repositories/pengeluaran_repository.dart';
import 'laporan_service.dart';
import '../services/pembagian_laba_service.dart';

/// V5.5 — helper: format tanggal singkat dd/MM (mis. "12/05") dipakai
/// menggantikan kolom "Kode" motor di tabel laporan.
String _tglSingkat(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// V5.5 — detail biaya per unit motor untuk tabel "Detail Perjalanan Unit
/// Motor" (dikumpulkan dari motor_cost, bukan tabel/kolom baru).
class _DetailUnitMotor {
  final String motor;
  final String? platNomor;
  final double hargaBeli;
  final List<MotorCostModel> biayaTambahan;
  final double hargaJual;
  final double biayaCalo;
  final double laba;
  _DetailUnitMotor({
    required this.motor,
    required this.platNomor,
    required this.hargaBeli,
    required this.biayaTambahan,
    required this.hargaJual,
    required this.biayaCalo,
    required this.laba,
  });
  double get totalBiayaTambahan =>
      biayaTambahan.fold<double>(0, (s, b) => s + b.nominal);
}

/// Service untuk mengekspor laporan periode ke format PDF dan Excel.
/// File disimpan di direktori sementara aplikasi lalu dibuka lewat
/// dialog print/share bawaan `printing` package (PDF) atau dikembalikan
/// sebagai path file (Excel) untuk dibagikan.
///
/// V5.5 — sekarang butuh MotorRepository & PengeluaranRepository (opsional,
/// lihat constructor) untuk mengambil detail RAW (biaya per unit motor,
/// catatan pengeluaran per transaksi) yang tidak ada di LaporanPeriodeData
/// (yang isinya cuma angka teragregasi). Kalau tidak diisi, export tetap
/// jalan seperti sebelumnya tapi tanpa 2 bagian detail baru (fallback aman,
/// tidak memaksa semua caller lama berubah).
class ExportService {
  final MotorRepository? motorRepo;
  final PengeluaranRepository? pengeluaranRepo;

  ExportService({this.motorRepo, this.pengeluaranRepo});

  Future<List<_DetailUnitMotor>> _kumpulkanDetailUnitMotor(
      LaporanPeriodeData laporan) async {
    final hasil = <_DetailUnitMotor>[];
    for (final l in laporan.labaPerMotor) {
      final biaya = motorRepo != null
          ? await motorRepo!.getRiwayatBiaya(l.motor.id!)
          : <MotorCostModel>[];
      hasil.add(_DetailUnitMotor(
        motor: l.motor.namaLengkap,
        platNomor: l.motor.platNomor,
        hargaBeli: l.motor.hargaBeli,
        biayaTambahan: biaya,
        hargaJual: l.penjualan.hargaJual,
        biayaCalo: l.penjualan.biayaCalo,
        laba: l.laba,
      ));
    }
    return hasil;
  }

  Future<List<PengeluaranModel>> _kumpulkanPengeluaran(int periodeId) async {
    if (pengeluaranRepo == null) return [];
    return pengeluaranRepo!.getAll(periodeId: periodeId);
  }

  Future<File> exportLaporanPdf({
    required PeriodeModel periode,
    required LaporanPeriodeData laporan,
    PreviewPembagianLaba? pembagianLaba,
  }) async {
    final pdf = pw.Document();
    final detailUnit = await _kumpulkanDetailUnitMotor(laporan);
    final pengeluaranRaw =
        periode.id != null ? await _kumpulkanPengeluaran(periode.id!) : <PengeluaranModel>[];

    // V5.5 — kelompokkan pengeluaran RAW per kategori (bukan cuma total),
    // supaya tiap transaksi & catatannya kelihatan, bukan cuma angka.
    final pengeluaranByKategori = <String, List<PengeluaranModel>>{};
    for (final p in pengeluaranRaw) {
      pengeluaranByKategori.putIfAbsent(p.kategori, () => []).add(p);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Laporan Pembukuan - ${periode.namaPeriode}',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            'Periode: ${AppFormatter.tanggal(periode.tanggalMulai)}'
            '${periode.tanggalSelesai != null ? " - ${AppFormatter.tanggal(periode.tanggalSelesai!)}" : " - Berjalan"}',
          ),
          pw.SizedBox(height: 16),

          pw.Header(level: 1, text: 'Ringkasan'),
          _buildKeyValueTable({
            'Total Pemasukan': AppFormatter.rupiah(laporan.totalPemasukan),
            'Total Pengeluaran': AppFormatter.rupiah(laporan.totalPengeluaran),
            'Total Laba Motor': AppFormatter.rupiah(laporan.totalLabaMotor),
          }),
          pw.SizedBox(height: 16),

          // V5.5 — kolom "Kode" diganti tanggal/bulan (dd/MM), tambah Plat.
          pw.Header(level: 1, text: 'Laba per Motor'),
          pw.TableHelper.fromTextArray(
            headers: ['Tanggal', 'Plat', 'Motor', 'Harga Jual', 'Modal', 'Laba', 'Penjual'],
            data: laporan.labaPerMotor
                .map((l) => [
                      _tglSingkat(l.penjualan.tanggalJual),
                      l.motor.platNomor?.isNotEmpty == true ? l.motor.platNomor! : '-',
                      l.motor.namaLengkap,
                      AppFormatter.rupiah(l.penjualan.hargaJual),
                      AppFormatter.rupiah(l.penjualan.modalMotor),
                      AppFormatter.rupiah(l.laba),
                      l.penjualan.penjual,
                    ])
                .toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle:
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),

          // V5.5 — pengeluaran per kategori sekarang DETAIL: tiap transaksi
          // ditampilkan dengan tanggal, nominal, dan catatan (kalau ada) di
          // baris bawahnya — bukan cuma total per kategori.
          pw.Header(level: 1, text: 'Pengeluaran per Kategori (Detail)'),
          if (pengeluaranByKategori.isEmpty)
            _buildKeyValueTable(
              laporan.pengeluaranPerKategori
                  .map((k, v) => MapEntry(k, AppFormatter.rupiah(v))),
            )
          else
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: pengeluaranByKategori.entries.map((entry) {
                final total = entry.value.fold<double>(0, (s, p) => s + p.nominal);
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 10),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('${entry.key} - Total ${AppFormatter.rupiah(total)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 2),
                      ...entry.value.map((p) => pw.Padding(
                            padding: const pw.EdgeInsets.only(left: 8, top: 2),
                            child: pw.Text(
                              '${_tglSingkat(p.tanggal)} - ${AppFormatter.rupiah(p.nominal)}'
                              '${(p.keterangan?.isNotEmpty ?? false) ? "\n     Catatan: ${p.keterangan}" : ""}',
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          )),
                    ],
                  ),
                );
              }).toList(),
            ),
          pw.SizedBox(height: 16),

          pw.Header(level: 1, text: 'Penjualan per Orang'),
          _buildKeyValueTable(
            laporan.penjualanPerOrang
                .map((k, v) => MapEntry(k, '$v unit')),
          ),
          pw.SizedBox(height: 16),

          // V5.5/V5.7 — tabel perjalanan lengkap tiap unit motor dari beli
          // sampai jual (grid 2 kolom, kotak per motor dipertahankan —
          // hanya penataan posisi yang berubah, isi & border tetap sama).
          pw.Header(level: 1, text: 'Detail Perjalanan Unit Motor'),
          if (detailUnit.isEmpty)
            pw.Text('Tidak ada data.', style: const pw.TextStyle(fontSize: 9))
          else
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: _buildUnitMotorGrid(detailUnit),
            ),

          if (pembagianLaba != null) ...[
            pw.SizedBox(height: 16),
            pw.Header(level: 1, text: 'Pembagian Laba'),
            _buildKeyValueTable({
              'Laba Bersih': AppFormatter.rupiah(pembagianLaba.labaBersih),
              'Abah (25%)': AppFormatter.rupiah(pembagianLaba.bagianAbah),
              'Iki (27.5%)': AppFormatter.rupiah(pembagianLaba.bagianIki),
              'Andri (22.5%)': AppFormatter.rupiah(pembagianLaba.bagianAndri),
              'Ilham (15%)': AppFormatter.rupiah(pembagianLaba.bagianIlham),
              'Hadiah Penjualan (10%)':
                  AppFormatter.rupiah(pembagianLaba.totalHadiahPenjualan),
            }),
            pw.SizedBox(height: 8),
            pw.Text('Detail Bonus Penjualan:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['Nama', 'Unit', 'Bonus'],
              data: pembagianLaba.detailBonus
                  .map((d) => [
                        d.nama,
                        d.jumlahUnit.toString(),
                        AppFormatter.rupiah(d.totalBonus),
                      ])
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/laporan_${periode.namaPeriode.replaceAll(" ", "_")}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// V5.7 — satu kotak "Detail Perjalanan Unit Motor". Isi & border SAMA
  /// PERSIS seperti versi sebelumnya (1 kolom) — hanya dipanggil dari
  /// grid 2 kolom sekarang, bukan lagi ditumpuk penuh ke bawah.
  pw.Widget _buildUnitMotorBox(_DetailUnitMotor u) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${u.motor}${u.platNomor?.isNotEmpty == true ? " (${u.platNomor})" : ""}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 3),
          pw.Text('Harga Beli: ${AppFormatter.rupiah(u.hargaBeli)}',
              style: const pw.TextStyle(fontSize: 9)),
          if (u.biayaTambahan.isEmpty)
            pw.Text('Biaya Tambahan: -', style: const pw.TextStyle(fontSize: 9))
          else ...[
            pw.Text('Biaya Tambahan:', style: const pw.TextStyle(fontSize: 9)),
            ...u.biayaTambahan.map((b) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8),
                  child: pw.Text(
                    '- ${b.kategori}: ${AppFormatter.rupiah(b.nominal)}'
                    '${(b.keterangan?.isNotEmpty ?? false) ? " (${b.keterangan})" : ""}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                )),
            pw.Text('Total Modal: ${AppFormatter.rupiah(u.hargaBeli + u.totalBiayaTambahan)}',
                style: const pw.TextStyle(fontSize: 9)),
          ],
          if (u.biayaCalo > 0)
            pw.Text('Biaya Calo: ${AppFormatter.rupiah(u.biayaCalo)}',
                style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Harga Jual: ${AppFormatter.rupiah(u.hargaJual)}',
              style: const pw.TextStyle(fontSize: 9)),
          pw.Text(
            '${u.laba >= 0 ? "Laba" : "Rugi"}: ${AppFormatter.rupiah(u.laba.abs())}',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: u.laba >= 0 ? PdfColors.green800 : PdfColors.red800,
            ),
          ),
        ],
      ),
    );
  }

  /// V5.7 — susun kotak-kotak motor jadi grid 2 kolom (kiri-atas, kanan-
  /// atas, kiri-bawah, kanan-bawah, dst — urutan baris demi baris/row-major
  /// sesuai urutan `list`). Lebar kolom kiri & kanan selalu sama (masing-
  /// masing flex 1 di dalam pw.Row), tinggi tiap kotak menyesuaikan isi
  /// sendiri-sendiri (kotak kiri & kanan di baris yang sama TIDAK dipaksa
  /// setinggi satu sama lain, sesuai "tinggi otomatis mengikuti isi").
  /// Kalau jumlah motor ganjil, kotak terakhir tetap di kolom kiri dengan
  /// sisi kanan kosong (bukan melebar penuh), supaya lebar kolom tetap
  /// konsisten di semua baris.
  List<pw.Widget> _buildUnitMotorGrid(List<_DetailUnitMotor> list) {
    final rows = <pw.Widget>[];
    for (int i = 0; i < list.length; i += 2) {
      final kiri = _buildUnitMotorBox(list[i]);
      final adaKanan = i + 1 < list.length;
      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: kiri),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: adaKanan ? _buildUnitMotorBox(list[i + 1]) : pw.SizedBox(),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  pw.Widget _buildKeyValueTable(Map<String, String> data) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: data.entries
          .map((e) => pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 10)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(e.value, style: const pw.TextStyle(fontSize: 10)),
                ),
              ]))
          .toList(),
    );
  }

  Future<void> printOrShare(File file) async {
    await Printing.sharePdf(bytes: await file.readAsBytes(), filename: file.path.split('/').last);
  }

  Future<File> exportLaporanExcel({
    required PeriodeModel periode,
    required LaporanPeriodeData laporan,
  }) async {
    final excel = xls.Excel.createExcel();
    final detailUnit = await _kumpulkanDetailUnitMotor(laporan);
    final pengeluaranRaw =
        periode.id != null ? await _kumpulkanPengeluaran(periode.id!) : <PengeluaranModel>[];

    final sheet = excel['Laba per Motor'];
    excel.setDefaultSheet('Laba per Motor');

    // V5.5 — kolom "Kode" diganti Tanggal, tambah Plat Nomor.
    sheet.appendRow([
      xls.TextCellValue('Tanggal'),
      xls.TextCellValue('Plat Nomor'),
      xls.TextCellValue('Motor'),
      xls.TextCellValue('Harga Jual'),
      xls.TextCellValue('Modal'),
      xls.TextCellValue('Biaya Calo'),
      xls.TextCellValue('Laba'),
      xls.TextCellValue('Penjual'),
    ]);
    for (final l in laporan.labaPerMotor) {
      sheet.appendRow([
        xls.TextCellValue(_tglSingkat(l.penjualan.tanggalJual)),
        xls.TextCellValue(l.motor.platNomor?.isNotEmpty == true ? l.motor.platNomor! : '-'),
        xls.TextCellValue(l.motor.namaLengkap),
        xls.DoubleCellValue(l.penjualan.hargaJual),
        xls.DoubleCellValue(l.penjualan.modalMotor),
        xls.DoubleCellValue(l.penjualan.biayaCalo),
        xls.DoubleCellValue(l.laba),
        xls.TextCellValue(l.penjualan.penjual),
      ]);
    }

    // V5.5 — sheet Pengeluaran sekarang detail per transaksi (bukan cuma
    // total per kategori), dengan kolom Catatan.
    final sheetPengeluaran = excel['Pengeluaran'];
    sheetPengeluaran.appendRow([
      xls.TextCellValue('Tanggal'),
      xls.TextCellValue('Kategori'),
      xls.TextCellValue('Nominal'),
      xls.TextCellValue('Catatan'),
    ]);
    if (pengeluaranRaw.isEmpty) {
      // Fallback: tidak ada PengeluaranRepository di-inject -> tetap
      // tampilkan total per kategori seperti versi sebelumnya.
      for (final entry in laporan.pengeluaranPerKategori.entries) {
        sheetPengeluaran.appendRow([
          xls.TextCellValue('-'),
          xls.TextCellValue(entry.key),
          xls.DoubleCellValue(entry.value),
          xls.TextCellValue(''),
        ]);
      }
    } else {
      for (final p in pengeluaranRaw) {
        sheetPengeluaran.appendRow([
          xls.TextCellValue(_tglSingkat(p.tanggal)),
          xls.TextCellValue(p.kategori),
          xls.DoubleCellValue(p.nominal),
          xls.TextCellValue(p.keterangan ?? ''),
        ]);
      }
    }

    // V5.5 — sheet baru: Detail Perjalanan Unit Motor.
    final sheetUnit = excel['Detail Perjalanan Unit Motor'];
    sheetUnit.appendRow([
      xls.TextCellValue('Unit Motor'),
      xls.TextCellValue('Plat Nomor'),
      xls.TextCellValue('Harga Beli'),
      xls.TextCellValue('Kategori Biaya'),
      xls.TextCellValue('Nominal Biaya'),
      xls.TextCellValue('Catatan Biaya'),
      xls.TextCellValue('Harga Jual'),
      xls.TextCellValue('Laba/Rugi'),
    ]);
    for (final u in detailUnit) {
      if (u.biayaTambahan.isEmpty) {
        sheetUnit.appendRow([
          xls.TextCellValue(u.motor),
          xls.TextCellValue(u.platNomor ?? '-'),
          xls.DoubleCellValue(u.hargaBeli),
          xls.TextCellValue('-'),
          const xls.DoubleCellValue(0),
          xls.TextCellValue(''),
          xls.DoubleCellValue(u.hargaJual),
          xls.DoubleCellValue(u.laba),
        ]);
      } else {
        for (int i = 0; i < u.biayaTambahan.length; i++) {
          final b = u.biayaTambahan[i];
          // Baris pertama bawa info harga beli/jual/laba unit; baris
          // berikutnya (biaya tambahan lain unit yang sama) dikosongkan
          // supaya tidak duplikat angka saat dibaca sebagai tabel.
          sheetUnit.appendRow([
            xls.TextCellValue(i == 0 ? u.motor : ''),
            xls.TextCellValue(i == 0 ? (u.platNomor ?? '-') : ''),
            xls.DoubleCellValue(i == 0 ? u.hargaBeli : 0),
            xls.TextCellValue(b.kategori),
            xls.DoubleCellValue(b.nominal),
            xls.TextCellValue(b.keterangan ?? ''),
            xls.DoubleCellValue(i == 0 ? u.hargaJual : 0),
            xls.DoubleCellValue(i == 0 ? u.laba : 0),
          ]);
        }
      }
    }

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/laporan_${periode.namaPeriode.replaceAll(" ", "_")}.xlsx');
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
    return file;
  }
}
