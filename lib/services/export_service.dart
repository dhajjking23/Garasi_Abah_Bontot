import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../core/utils/app_formatter.dart';
import '../models/periode_model.dart';
import 'laporan_service.dart';
import '../services/pembagian_laba_service.dart';

/// Service untuk mengekspor laporan periode ke format PDF dan Excel.
/// File disimpan di direktori sementara aplikasi lalu dibuka lewat
/// dialog print/share bawaan `printing` package (PDF) atau dikembalikan
/// sebagai path file (Excel) untuk dibagikan.
class ExportService {
  Future<File> exportLaporanPdf({
    required PeriodeModel periode,
    required LaporanPeriodeData laporan,
    PreviewPembagianLaba? pembagianLaba,
  }) async {
    final pdf = pw.Document();

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

          pw.Header(level: 1, text: 'Laba per Motor'),
          pw.TableHelper.fromTextArray(
            headers: ['Kode', 'Motor', 'Harga Jual', 'Modal', 'Laba', 'Penjual'],
            data: laporan.labaPerMotor
                .map((l) => [
                      l.motor.kodeMotor,
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

          pw.Header(level: 1, text: 'Pengeluaran per Kategori'),
          _buildKeyValueTable(
            laporan.pengeluaranPerKategori
                .map((k, v) => MapEntry(k, AppFormatter.rupiah(v))),
          ),
          pw.SizedBox(height: 16),

          pw.Header(level: 1, text: 'Penjualan per Orang'),
          _buildKeyValueTable(
            laporan.penjualanPerOrang
                .map((k, v) => MapEntry(k, '$v unit')),
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
    final sheet = excel['Laba per Motor'];
    excel.setDefaultSheet('Laba per Motor');

    sheet.appendRow([
      xls.TextCellValue('Kode'),
      xls.TextCellValue('Motor'),
      xls.TextCellValue('Harga Jual'),
      xls.TextCellValue('Modal'),
      xls.TextCellValue('Laba'),
      xls.TextCellValue('Penjual'),
    ]);
    for (final l in laporan.labaPerMotor) {
      sheet.appendRow([
        xls.TextCellValue(l.motor.kodeMotor),
        xls.TextCellValue(l.motor.namaLengkap),
        xls.DoubleCellValue(l.penjualan.hargaJual),
        xls.DoubleCellValue(l.penjualan.modalMotor),
        xls.DoubleCellValue(l.laba),
        xls.TextCellValue(l.penjualan.penjual),
      ]);
    }

    final sheetPengeluaran = excel['Pengeluaran'];
    sheetPengeluaran
        .appendRow([xls.TextCellValue('Kategori'), xls.TextCellValue('Total')]);
    for (final entry in laporan.pengeluaranPerKategori.entries) {
      sheetPengeluaran.appendRow(
          [xls.TextCellValue(entry.key), xls.DoubleCellValue(entry.value)]);
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
