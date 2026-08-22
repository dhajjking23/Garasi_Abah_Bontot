import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../core/utils/rupiah_input_formatter.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';

class GajihanScreen extends ConsumerStatefulWidget {
  const GajihanScreen({super.key});

  @override
  ConsumerState<GajihanScreen> createState() => _GajihanScreenState();
}

class _GajihanScreenState extends ConsumerState<GajihanScreen> {
  String _karyawan = AppConstants.karyawanDefault.first;
  final _gajiController = TextEditingController();
  final _kasbonController = TextEditingController(text: '0');
  final _talangController = TextEditingController(text: '0');
  String _sumber = AppConstants.sumberCash;
  double _kasbonTersedia = 0;
  double _talangTersedia = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _muatRingkasan();
  }

  @override
  void dispose() {
    _gajiController.dispose();
    _kasbonController.dispose();
    _talangController.dispose();
    super.dispose();
  }

  Future<void> _muatRingkasan() async {
    final repo = await ref.read(gajihanRepositoryProvider.future);
    final ringkasan = await repo.getRingkasanPotongan(_karyawan);
    if (!mounted) return;
    setState(() {
      _kasbonTersedia = ringkasan.kasbon;
      _talangTersedia = ringkasan.danaTalang;
      _kasbonController.text = RupiahInputFormatter.format(ringkasan.kasbon);
      _talangController.text = RupiahInputFormatter.format(ringkasan.danaTalang);
    });
  }

  double get _gaji => RupiahInputFormatter.parse(_gajiController.text);
  double get _kasbon => RupiahInputFormatter.parse(_kasbonController.text);
  double get _talang => RupiahInputFormatter.parse(_talangController.text);
  double get _netDiterima => _gaji - _kasbon - _talang;

  Future<void> _proses() async {
    if (_gaji <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Gaji pokok harus diisi')));
      return;
    }
    if (_kasbon > _kasbonTersedia + 0.5 || _talang > _talangTersedia + 0.5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Potongan tidak boleh melebihi kasbon/talangan yang tersedia')));
      return;
    }

    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Proses Gajihan $_karyawan?',
      message: 'Gaji pokok ${AppFormatter.rupiah(_gaji)} akan dicatat sebagai '
          'pengeluaran, dipotong kasbon ${AppFormatter.rupiah(_kasbon)} dan '
          'dana talang ${AppFormatter.rupiah(_talang)}. '
          'Diterima bersih: ${AppFormatter.rupiah(_netDiterima)}. Lanjutkan?',
      confirmLabel: 'Ya, Proses',
    );
    if (!konfirmasi) return;

    setState(() => _loading = true);
    try {
      final repo = await ref.read(gajihanRepositoryProvider.future);
      final periodeRepo = await ref.read(periodeRepositoryProvider.future);
      final periodeAktif = await periodeRepo.getPeriodeAktif();

      await repo.prosesGajihan(
        namaKaryawan: _karyawan,
        tanggal: DateTime.now(),
        gajiPokok: _gaji,
        kasbonDipotong: _kasbon,
        danaTalangDipotong: _talang,
        sumber: _sumber,
        periodeId: periodeAktif?.id,
      );
      refreshSemuaData(ref);
      _gajiController.clear();
      await _muatRingkasan();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gajihan berhasil diproses')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final riwayatAsync = ref.watch(daftarGajihanProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Gajihan & Tutup Buku')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Gaji pokok dicatat penuh sebagai pengeluaran. Kasbon & dana talang '
            'karyawan yang belum lunas otomatis dipotong dari gaji — sisa yang '
            'diterima karyawan sudah bersih.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _karyawan,
            decoration: const InputDecoration(labelText: 'Karyawan'),
            items: AppConstants.karyawanDefault
                .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                .toList(),
            onChanged: (v) {
              setState(() => _karyawan = v!);
              _muatRingkasan();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gajiController,
            decoration: const InputDecoration(
                labelText: 'Gaji Pokok', prefixText: 'Rp '),
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _kasbonController,
            decoration: InputDecoration(
              labelText: 'Potongan Kasbon',
              prefixText: 'Rp ',
              helperText: 'Tersedia: ${AppFormatter.rupiah(_kasbonTersedia)}',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _talangController,
            decoration: InputDecoration(
              labelText: 'Potongan Dana Talang',
              prefixText: 'Rp ',
              helperText: 'Tersedia: ${AppFormatter.rupiah(_talangTersedia)}',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: AppConstants.sumberCash, label: Text('Cash')),
              ButtonSegment(value: AppConstants.sumberBank, label: Text('Transfer')),
            ],
            selected: {_sumber},
            onSelectionChanged: (s) => setState(() => _sumber = s.first),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Diterima Bersih',
                    style: TextStyle(color: Colors.white70)),
                Text(
                  AppFormatter.rupiah(_netDiterima),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading ? null : _proses,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Proses Gajihan'),
          ),
          const SizedBox(height: 24),
          const SectionTitle(title: 'Riwayat Gajihan'),
          riwayatAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Text('Error: $e'),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(message: 'Belum ada riwayat gajihan');
              }
              return Column(
                children: [
                  for (final g in list)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () async {
                          final picked =
                              await pickTanggal(context, g.tanggal);
                          if (picked == null) return;
                          try {
                            final repo = await ref
                                .read(gajihanRepositoryProvider.future);
                            await repo.editTanggalGajihan(g.id!, picked);
                            refreshSemuaData(ref);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$e')));
                            }
                          }
                        },
                        title: Text(g.namaKaryawan,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${AppFormatter.tanggal(g.tanggal)} • Gaji ${AppFormatter.rupiah(g.gajiPokok)}'
                          '${g.kasbonDipotong > 0 ? " • Kasbon -${AppFormatter.rupiah(g.kasbonDipotong)}" : ""}'
                          '${g.danaTalangDipotong > 0 ? " • Talangan -${AppFormatter.rupiah(g.danaTalangDipotong)}" : ""}',
                        ),
                        trailing: Text(
                          AppFormatter.rupiah(g.totalDiterima),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: AppTheme.success),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
