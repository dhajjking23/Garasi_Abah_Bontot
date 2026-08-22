import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../core/utils/rupiah_input_formatter.dart';

class BuatPeriodeScreen extends ConsumerStatefulWidget {
  const BuatPeriodeScreen({super.key});

  @override
  ConsumerState<BuatPeriodeScreen> createState() => _BuatPeriodeScreenState();
}

class _BuatPeriodeScreenState extends ConsumerState<BuatPeriodeScreen> {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Buat Periode Pembukuan')),
      body: Padding(
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
              const SizedBox(height: 8),
              Consumer(builder: (context, ref, _) {
                final nilaiStokAsync = ref.watch(nilaiStokMotorProvider);
                return nilaiStokAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, st) => const SizedBox.shrink(),
                  data: (nilai) {
                    if (nilai <= 0) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Masih ada stok motor senilai Rp ${RupiahInputFormatter.format(nilai)} '
                        'dari sebelumnya (belum terjual). Nilai ini TETAP dihitung sebagai '
                        'aset di Dashboard & Laporan — tidak dianggap hilang meskipun '
                        'periode berganti.',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    );
                  },
                );
              }),
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
      ),
    );
  }
}
