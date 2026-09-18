import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_formatter.dart';
import '../../models/motor_cost_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/metode_pembayaran_field.dart';
import '../../widgets/kategori_dropdown_field.dart';
import '../../core/utils/rupiah_input_formatter.dart';

class _BiayaInput {
  String kategori;
  final TextEditingController nominalController;
  final TextEditingController keteranganController;

  _BiayaInput({required this.kategori})
      : nominalController = TextEditingController(),
        keteranganController = TextEditingController();

  void dispose() {
    nominalController.dispose();
    keteranganController.dispose();
  }
}

class TambahMotorScreen extends ConsumerStatefulWidget {
  const TambahMotorScreen({super.key});

  @override
  ConsumerState<TambahMotorScreen> createState() => _TambahMotorScreenState();
}

class _TambahMotorScreenState extends ConsumerState<TambahMotorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _merkController = TextEditingController();
  final _tipeController = TextEditingController();
  final _tahunController = TextEditingController();
  final _warnaController = TextEditingController();
  final _platController = TextEditingController();
  final _hargaBeliController = TextEditingController();
  DateTime _tanggalMasuk = DateTime.now();
  final List<_BiayaInput> _biayaList = [];
  final _metodeController =
      MetodePembayaranController(total: 0, tampilkanJenisTransfer: true);
  bool _loading = false;

  @override
  void dispose() {
    _merkController.dispose();
    _tipeController.dispose();
    _tahunController.dispose();
    _warnaController.dispose();
    _platController.dispose();
    _hargaBeliController.dispose();
    _metodeController.dispose();
    for (final b in _biayaList) {
      b.dispose();
    }
    super.dispose();
  }

  double get _totalBiaya {
    double total = 0;
    for (final b in _biayaList) {
      total += double.tryParse(b.nominalController.text.replaceAll('.', '')) ?? 0;
    }
    return total;
  }

  double get _totalModal {
    final hargaBeli =
        double.tryParse(_hargaBeliController.text.replaceAll('.', '')) ?? 0;
    return hargaBeli + _totalBiaya;
  }

  void _tambahBaris() {
    setState(() {
      _biayaList.add(_BiayaInput(kategori: AppConstants.kategoriMotorCost[1]));
    });
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    _metodeController.updateTotal(_totalModal);
    final metodeErr = _metodeController.validasi();
    if (metodeErr != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(metodeErr)));
      return;
    }
    setState(() => _loading = true);

    try {
      final motorRepo = await ref.read(motorRepositoryProvider.future);
      final periodeRepo = await ref.read(periodeRepositoryProvider.future);
      final periodeAktif = await periodeRepo.getPeriodeAktif();
      final hasil = _metodeController.hasil;

      final biayaAwal = _biayaList
          .where((b) => (double.tryParse(
                      b.nominalController.text.replaceAll('.', '')) ??
                  0) >
              0)
          .map((b) => MotorCostModel(
                motorId: 0, // diisi ulang di repository
                kategori: b.kategori,
                nominal: double.parse(
                    b.nominalController.text.replaceAll('.', '')),
                keterangan: b.keteranganController.text.trim().isEmpty
                    ? null
                    : b.keteranganController.text.trim(),
                tanggal: _tanggalMasuk,
                createdAt: DateTime.now(),
              ))
          .toList();

      await motorRepo.tambahMotor(
        merk: _merkController.text.trim(),
        tipe: _tipeController.text.trim(),
        tahun: int.tryParse(_tahunController.text),
        warna: _warnaController.text.trim().isEmpty
            ? null
            : _warnaController.text.trim(),
        platNomor: _platController.text.trim().isEmpty
            ? null
            : _platController.text.trim(),
        tanggalMasuk: _tanggalMasuk,
        hargaBeli:
            double.parse(_hargaBeliController.text.replaceAll('.', '')),
        metodePembayaran: hasil.metode,
        cashDibayar: hasil.cash,
        transferDibayar: hasil.transfer,
        jenisTransfer: _metodeController.jenisTransferTerpilih,
        periodeId: periodeAktif?.id,
        biayaAwal: biayaAwal,
      );

      refreshSemuaData(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Motor')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _merkController,
                    decoration: const InputDecoration(labelText: 'Merk'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Wajib' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _tipeController,
                    decoration: const InputDecoration(labelText: 'Tipe'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Wajib' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _tahunController,
                    decoration: const InputDecoration(labelText: 'Tahun'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _warnaController,
                    decoration: const InputDecoration(labelText: 'Warna'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _platController,
              decoration: const InputDecoration(labelText: 'Plat Nomor'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tanggal Masuk'),
              subtitle: Text(AppFormatter.tanggal(_tanggalMasuk)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _tanggalMasuk,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _tanggalMasuk = picked);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hargaBeliController,
              decoration: const InputDecoration(
                  labelText: 'Harga Beli', prefixText: 'Rp '),
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Wajib diisi' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Biaya Tambahan',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextButton.icon(
                  onPressed: _tambahBaris,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah Biaya'),
                ),
              ],
            ),
            ..._biayaList.asMap().entries.map((entry) {
              final index = entry.key;
              final biaya = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: KategoriDropdownField(
                              tipe: AppConstants.kategoriTipeMotorCost,
                              value: biaya.kategori,
                              label: 'Kategori Biaya',
                              exclude: const ['Pembelian Unit'],
                              onChanged: (v) {
                                setState(() => biaya.kategori = v);
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () {
                              setState(() {
                                biaya.dispose();
                                _biayaList.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: biaya.nominalController,
                        decoration: const InputDecoration(
                            labelText: 'Nominal', prefixText: 'Rp '),
                        keyboardType: TextInputType.number,
                        inputFormatters: [RupiahInputFormatter()],
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: biaya.keteranganController,
                        decoration:
                            const InputDecoration(labelText: 'Keterangan (opsional)'),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Biaya'),
                      Text(AppFormatter.rupiah(_totalBiaya)),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL MODAL UNIT',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        AppFormatter.rupiah(_totalModal),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Builder(builder: (_) {
              _metodeController.total = _totalModal;
              return MetodePembayaranField(controller: _metodeController);
            }),
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
                  : const Text('Simpan Motor'),
            ),
          ],
        ),
      ),
    );
  }
}
