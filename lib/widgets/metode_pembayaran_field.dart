import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_formatter.dart';
import '../core/utils/rupiah_input_formatter.dart';

/// Hasil pilihan metode pembayaran: metode + split cash/transfer.
/// Untuk CASH: cash == total, transfer == 0. Untuk TRANSFER: sebaliknya.
/// Untuk CAMPURAN: cash + transfer == total (divalidasi oleh widget).
class MetodePembayaranResult {
  final String metode;
  final double cash;
  final double transfer;
  const MetodePembayaranResult(
      {required this.metode, required this.cash, required this.transfer});
}

/// Form-section untuk memilih metode pembayaran Cash/Transfer/Campuran.
/// [total] adalah nominal transaksi (harga motor, harga jual, dsb) yang
/// harus dipenuhi persis oleh Cash+Transfer saat CAMPURAN. Panggil
/// [controller.hasil] untuk membaca hasil saat submit, dan pastikan
/// memanggil [controller.validasi] dulu (return null jika valid).
class MetodePembayaranController extends ChangeNotifier {
  String metode = AppConstants.metodeCash;
  final TextEditingController cashController = TextEditingController();
  final TextEditingController transferController = TextEditingController();
  double total;

  /// V4.2.1 — PAYMENT FLOW GLOBAL. Set true untuk transaksi yang
  /// MENGELUARKAN uang lewat transfer (pembelian motor, biaya motor,
  /// dana talang keluar, dst) supaya field pilihan biaya transfer
  /// (Gratis/BI FAST/Realtime) otomatis muncul saat metode Transfer/
  /// Campuran dipilih. Biarkan false (default) untuk transaksi uang
  /// MASUK (mis. penjualan) — tidak relevan dikenai biaya transfer.
  final bool tampilkanJenisTransfer;
  String jenisTransfer = AppConstants.jenisTransferGratis;

  MetodePembayaranController({
    required this.total,
    this.tampilkanJenisTransfer = false,
  });

  void setJenisTransfer(String j) {
    jenisTransfer = j;
    notifyListeners();
  }

  /// null jika metode CASH (tidak relevan) atau tampilkanJenisTransfer
  /// dimatikan.
  String? get jenisTransferTerpilih =>
      (tampilkanJenisTransfer && metode != AppConstants.metodeCash)
          ? jenisTransfer
          : null;

  void updateTotal(double t) {
    total = t;
    notifyListeners();
  }

  void setMetode(String m) {
    metode = m;
    notifyListeners();
  }

  /// Dipanggil widget saat input cash/transfer berubah, supaya UI
  /// (total, validasi) ikut ter-refresh. notifyListeners() sendiri
  /// bersifat protected di ChangeNotifier, jadi dibungkus method publik
  /// ini agar aman dipanggil dari luar class.
  void refresh() {
    notifyListeners();
  }

  double get _cashVal =>
      double.tryParse(cashController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  double get _transferVal => double.tryParse(
          transferController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
      0;

  String? validasi() {
    if (metode == AppConstants.metodeCampuran) {
      final jumlah = _cashVal + _transferVal;
      if ((jumlah - total).abs() > 0.5) {
        return 'Cash + Transfer harus sama dengan total (${AppFormatter.rupiah(total)})';
      }
    }
    return null;
  }

  MetodePembayaranResult get hasil {
    switch (metode) {
      case AppConstants.metodeTransfer:
        return MetodePembayaranResult(metode: metode, cash: 0, transfer: total);
      case AppConstants.metodeCampuran:
        return MetodePembayaranResult(
            metode: metode, cash: _cashVal, transfer: _transferVal);
      case AppConstants.metodeCash:
      default:
        return MetodePembayaranResult(metode: metode, cash: total, transfer: 0);
    }
  }

  @override
  void dispose() {
    cashController.dispose();
    transferController.dispose();
    super.dispose();
  }
}

class MetodePembayaranField extends StatelessWidget {
  final MetodePembayaranController controller;

  const MetodePembayaranField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Metode Pembayaran',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: AppConstants.metodeCash, label: Text('Cash')),
                ButtonSegment(
                    value: AppConstants.metodeTransfer,
                    label: Text('Transfer')),
                ButtonSegment(
                    value: AppConstants.metodeCampuran,
                    label: Text('Campuran')),
              ],
              selected: {controller.metode},
              onSelectionChanged: (s) => controller.setMetode(s.first),
            ),
            if (controller.metode == AppConstants.metodeCampuran) ...[
              const SizedBox(height: 12),
              TextField(
                controller: controller.cashController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                    labelText: 'Jumlah Cash', prefixText: 'Rp '),
                onChanged: (_) => controller.refresh(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller.transferController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(
                    labelText: 'Jumlah Transfer', prefixText: 'Rp '),
                onChanged: (_) => controller.refresh(),
              ),
              const SizedBox(height: 4),
              Text(
                'Total: ${AppFormatter.rupiah(controller.total)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            if (controller.tampilkanJenisTransfer &&
                controller.metode != AppConstants.metodeCash) ...[
              const SizedBox(height: 12),
              JenisTransferField(
                value: controller.jenisTransfer,
                onChanged: (v) => controller.setJenisTransfer(
                    v ?? AppConstants.jenisTransferGratis),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Picker sederhana untuk jenis transfer (biaya admin) — Gratis/BI
/// FAST/Realtime.
class JenisTransferField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const JenisTransferField({super.key, required this.value, required this.onChanged});

  String _label(String j) {
    switch (j) {
      case AppConstants.jenisTransferBiFast:
        return 'BI FAST antar bank (Rp2.500)';
      case AppConstants.jenisTransferRealtime:
        return 'Realtime antar bank (Rp6.500)';
      case AppConstants.jenisTransferGratis:
      default:
        return 'Gratis sesama bank (Rp0)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value ?? AppConstants.jenisTransferGratis,
      decoration: const InputDecoration(labelText: 'Jenis Transfer (Biaya Admin)'),
      items: AppConstants.daftarJenisTransfer
          .map((j) => DropdownMenuItem(value: j, child: Text(_label(j))))
          .toList(),
      onChanged: onChanged,
    );
  }
}
