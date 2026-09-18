import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/rupiah_input_formatter.dart';
import '../../core/utils/app_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/metode_pembayaran_field.dart';

class BuatPeriodeScreen extends ConsumerWidget {
  const BuatPeriodeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adaPeriodeSebelumnya = ref.watch(adaPeriodeSebelumnyaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Buat Periode Pembukuan')),
      body: adaPeriodeSebelumnya.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (ada) => ada
            ? const _CarryForwardForm()
            : const _PeriodePertamaForm(),
      ),
    );
  }
}

/// V5.9.4 — periode LANJUTAN: Modal Awal = Total Aset akhir closing
/// sebelumnya, dihitung LIVE lewat FinancialBalanceEngine.
///
/// V5.9.9 — Modal Awal ini sekarang BISA DIEDIT. Kalau user mengubahnya
/// dari nilai otomatis, selisihnya (naik atau turun) WAJIB memakai
/// metode Cash/Bank/Campuran — selisih itu BENAR-BENAR disuntik/ditarik
/// dari Cash/Bank sungguhan (bukan cuma mengubah angka referensi), lihat
/// `PeriodOpeningService.bukaPeriodeBaruDariClosing` /
/// `SaldoRepository.sesuaikanModalAwalPeriode`.
class _CarryForwardForm extends ConsumerStatefulWidget {
  const _CarryForwardForm();

  @override
  ConsumerState<_CarryForwardForm> createState() => _CarryForwardFormState();
}

class _CarryForwardFormState extends ConsumerState<_CarryForwardForm> {
  final _namaController = TextEditingController();
  final _modalAwalController = TextEditingController();
  DateTime _tanggalMulai = DateTime.now();
  bool _loading = false;
  bool _arsipkanLunas = true;
  bool _modalAwalInit = false;
  double _totalAsetOtomatis = 0;
  MetodePembayaranController? _selisihController;
  String? _errorMessage;

  @override
  void dispose() {
    _namaController.dispose();
    _modalAwalController.dispose();
    _selisihController?.dispose();
    super.dispose();
  }

  double get _modalAwalEdit => RupiahInputFormatter.parse(_modalAwalController.text);
  double get _selisih => _modalAwalEdit - _totalAsetOtomatis;

  void _syncSelisihController() {
    final target = _selisih.abs();
    if (target < 0.5) {
      _selisihController = null;
      return;
    }
    if (_selisihController == null) {
      _selisihController = MetodePembayaranController(total: target);
    } else {
      _selisihController!.updateTotal(target);
    }
  }

  Future<void> _simpan() async {
    if (_namaController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Nama periode wajib diisi');
      return;
    }
    String metodeSelisih = AppConstants.metodeCash;
    double cashSelisih = 0;
    double bankSelisih = 0;
    if (_selisih.abs() >= 0.5) {
      final ctrl = _selisihController;
      if (ctrl == null) {
        setState(() => _errorMessage = 'Isi metode pembayaran untuk selisih modal awal');
        return;
      }
      final validasi = ctrl.validasi();
      if (validasi != null) {
        setState(() => _errorMessage = validasi);
        return;
      }
      final hasil = ctrl.hasil;
      metodeSelisih = hasil.metode;
      cashSelisih = hasil.cash;
      bankSelisih = hasil.transfer;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final service = await ref.read(periodOpeningServiceProvider.future);
      await service.bukaPeriodeBaruDariClosing(
        namaPeriode: _namaController.text.trim(),
        tanggalMulai: _tanggalMulai,
        totalAsetOtomatis: _totalAsetOtomatis,
        modalAwalFinal: _modalAwalEdit,
        metodePembayaranSelisih: metodeSelisih,
        cashSelisih: cashSelisih,
        bankSelisih: bankSelisih,
        arsipkanTransaksiLunas: _arsipkanLunas,
      );
      refreshSemuaData(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() =>
          _errorMessage = e.toString().replaceFirst('StateError: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAsetAsync = ref.watch(_totalAsetOpeningProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_errorMessage!,
                  style: const TextStyle(color: Colors.red)),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Periode sebelumnya sudah ditutup. Modal Awal periode baru '
              'diambil OTOMATIS dari Total Aset Perusahaan saat ini '
              '(Cash + Bank + Stok + Piutang). Bisa diedit di bawah — kalau '
              'diubah, selisihnya akan BENAR-BENAR disuntik/ditarik dari '
              'Cash/Bank (bukan cuma angka), sesuai metode yang dipilih.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _namaController,
            decoration: const InputDecoration(
              labelText: 'Nama Periode',
              hintText: 'Contoh: Pembukuan #002',
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tanggal Mulai'),
            subtitle: Text(
                '${_tanggalMulai.day}/${_tanggalMulai.month}/${_tanggalMulai.year}'),
            trailing: const Icon(Icons.calendar_today, size: 18),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _tanggalMulai,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _tanggalMulai = picked);
            },
          ),
          const SizedBox(height: 20),
          const Text('Modal Awal (Total Aset Perusahaan)',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          totalAsetAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, st) => Text('Error hitung total aset: $e'),
            data: (report) {
              if (!_modalAwalInit) {
                _totalAsetOtomatis = report.totalAset;
                _modalAwalController.text =
                    RupiahInputFormatter.format(report.totalAset);
                _modalAwalInit = true;
              }
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...report.asetBreakdown
                        .where((c) => c.nilai != 0)
                        .map((c) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(c.label,
                                      style: const TextStyle(fontSize: 12)),
                                  Text(AppFormatter.rupiah(c.nilai),
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            )),
                    const Divider(),
                    Text('Total Otomatis: ${AppFormatter.rupiah(report.totalAset)}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _modalAwalController,
                      decoration: const InputDecoration(
                        labelText: 'Total Modal Awal (bisa diedit)',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      onChanged: (_) => setState(_syncSelisihController),
                    ),
                    if (_selisih.abs() >= 0.5) ...[
                      const SizedBox(height: 8),
                      Text(
                        _selisih > 0
                            ? 'Modal awal dinaikkan Rp${_selisih.toStringAsFixed(0)} — jumlah ini akan MASUK ke Cash/Bank sungguhan.'
                            : 'Modal awal diturunkan Rp${(-_selisih).toStringAsFixed(0)} — jumlah ini akan KELUAR dari Cash/Bank sungguhan.',
                        style: TextStyle(
                            fontSize: 12,
                            color: _selisih > 0 ? AppTheme.success : AppTheme.danger,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (_selisihController != null)
                        MetodePembayaranField(controller: _selisihController!),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Arsipkan transaksi lunas',
                style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              'Kasbon & Dana Talang yang sudah LUNAS disembunyikan dari '
              'daftar aktif (data TETAP tersimpan untuk audit, tidak dihapus).',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            value: _arsipkanLunas,
            onChanged: (v) => setState(() => _arsipkanLunas = v),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loading ? null : _simpan,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Buka Periode Baru'),
          ),
        ],
      ),
    );
  }
}

final _totalAsetOpeningProvider = FutureProvider.autoDispose((ref) async {
  final engine = await ref.watch(financialBalanceEngineProvider.future);
  return engine.hitung();
});

/// Form LAMA — hanya untuk periode PERTAMA kali (belum pernah ada
/// periode sama sekali), di mana modal awal memang benar-benar
/// suntikan cash/bank fisik pertama kali.
class _PeriodePertamaForm extends ConsumerStatefulWidget {
  const _PeriodePertamaForm();

  @override
  ConsumerState<_PeriodePertamaForm> createState() =>
      _PeriodePertamaFormState();
}

class _PeriodePertamaFormState extends ConsumerState<_PeriodePertamaForm> {
  final _formKey = GlobalKey<FormState>();
  final _namaController = TextEditingController();
  final _modalCashController = TextEditingController(text: '0');
  final _modalBankController = TextEditingController(text: '0');
  DateTime _tanggalMulai = DateTime.now();
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _namaController.dispose();
    _modalCashController.dispose();
    _modalBankController.dispose();
    super.dispose();
  }

  double get _modalCash =>
      RupiahInputFormatter.parse(_modalCashController.text);
  double get _modalBank =>
      RupiahInputFormatter.parse(_modalBankController.text);

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final repo = await ref.read(periodeRepositoryProvider.future);
      await repo.buatPeriode(
        namaPeriode: _namaController.text.trim(),
        tanggalMulai: _tanggalMulai,
        modalAwalCash: _modalCash,
        modalAwalBank: _modalBank,
      );
      refreshSemuaData(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('StateError: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Ini periode PERTAMA — belum ada periode sebelumnya yang '
                'ditutup. Modal Awal di sini adalah suntikan cash/bank '
                'fisik yang sungguhan ada di tangan saat mulai.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            TextFormField(
              controller: _namaController,
              decoration: const InputDecoration(
                labelText: 'Nama Periode',
                hintText: 'Contoh: Pembukuan #001',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tanggal Mulai'),
              subtitle: Text(
                  '${_tanggalMulai.day}/${_tanggalMulai.month}/${_tanggalMulai.year}'),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _tanggalMulai,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _tanggalMulai = picked);
              },
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Modal Awal',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Modal ini adalah patokan awal pembukuan (bukan cashflow — '
                'tidak berubah karena transaksi). Nominal yang diisi di sini '
                'juga otomatis mengisi saldo Cash & Saldo Bank sebagai modal '
                'fisik yang ada di tangan saat periode dimulai.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _modalCashController,
              decoration: const InputDecoration(
                labelText: 'Modal Cash',
                prefixText: 'Rp ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _modalBankController,
              decoration: const InputDecoration(
                labelText: 'Modal Saldo Bank',
                prefixText: 'Rp ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Total Modal Awal: Rp ${RupiahInputFormatter.format(_modalCash + _modalBank)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _simpan,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Buat Periode'),
            ),
          ],
        ),
      ),
    );
  }
}
