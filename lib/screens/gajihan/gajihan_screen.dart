import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../core/utils/rupiah_input_formatter.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/metode_pembayaran_field.dart';

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
  /// V5.9.7 — CASH/TRANSFER/CAMPURAN (bukan cuma Cash/Transfer single
  /// choice), pola sama persis dipakai Dana Talang & Tutup Buku.
  late final MetodePembayaranController _metodeController =
      MetodePembayaranController(total: 0);
  double _kasbonTersedia = 0;
  double _talangTersedia = 0;
  double _hakLabaKotor = 0;
  double _sudahDiambilPeriodeIni = 0;
  bool _adaPeriodeAktif = false;
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
    _metodeController.dispose();
    super.dispose();
  }

  /// V5.9.6 — "Gaji Pokok" untuk 4 partner (Abah/Iki/Andri/Ilham) BUKAN
  /// gaji flat, tapi HAK LABA mereka (persentase x laba bersih periode
  /// AKTIF berjalan) dikurangi yang sudah pernah diambil periode ini —
  /// sinkron dengan angka yang sama persis dipakai layar "Pembagian
  /// Laba" (`PembagianLabaService.hitungPreview`), supaya tidak ada dua
  /// angka berbeda untuk hak yang sama. Field TETAP bisa diedit manual
  /// (mis. kalau mau ambil lebih sedikit dari hak penuh).
  Future<void> _muatRingkasan() async {
    final gajihanRepo = await ref.read(gajihanRepositoryProvider.future);
    final periodeRepo = await ref.read(periodeRepositoryProvider.future);
    final pembagianLabaService =
        await ref.read(pembagianLabaServiceProvider.future);

    final ringkasan = await gajihanRepo.getRingkasanPotongan(_karyawan);
    final periodeAktif = await periodeRepo.getPeriodeAktif();

    double hakKotor = 0;
    double sudahDiambil = 0;
    if (periodeAktif?.id != null) {
      final preview =
          await pembagianLabaService.hitungPreview(periodeAktif!.id!);
      hakKotor = pembagianLabaService.bagianPartner(preview, _karyawan);
      sudahDiambil = await gajihanRepo.getTotalGajiDiambilPeriode(
          _karyawan, periodeAktif.id);
    }
    final sisaHak = (hakKotor - sudahDiambil).clamp(0, double.infinity).toDouble();

    if (!mounted) return;
    setState(() {
      _kasbonTersedia = ringkasan.kasbon;
      _talangTersedia = ringkasan.danaTalang;
      _hakLabaKotor = hakKotor;
      _sudahDiambilPeriodeIni = sudahDiambil;
      _adaPeriodeAktif = periodeAktif?.id != null;
      _gajiController.text = RupiahInputFormatter.format(sisaHak);
      _metodeController.updateTotal(sisaHak);
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
    final validasiMetode = _metodeController.validasi();
    if (validasiMetode != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(validasiMetode)));
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
      final hasilMetode = _metodeController.hasil;

      await repo.prosesGajihan(
        namaKaryawan: _karyawan,
        tanggal: DateTime.now(),
        gajiPokok: _gaji,
        kasbonDipotong: _kasbon,
        danaTalangDipotong: _talang,
        metodePembayaran: hasilMetode.metode,
        cashDibayar: hasilMetode.cash,
        transferDibayar: hasilMetode.transfer,
        jenisTransfer: _metodeController.jenisTransferTerpilih,
        periodeId: periodeAktif?.id,
      );

      // V5.9.6 — gaji partner sekarang berbasis hak laba (bukan
      // "standar" flat), jadi tidak ada lagi yang perlu disimpan
      // sebagai nilai standar di sini. `_muatRingkasan()` di bawah akan
      // otomatis menghitung ulang sisa hak laba terbaru.
      refreshSemuaData(ref);
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
            'Gaji Pokok = HAK LABA partner (persentase x laba bersih '
            'periode aktif) dikurangi yang sudah pernah diambil periode '
            'ini — sinkron dengan layar Pembagian Laba, bukan angka '
            'manual. Potongan Kasbon & Dana Talang otomatis dari sisa '
            'belum lunas. Semua tetap bisa diedit manual sebelum diproses.',
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
          if (!_adaPeriodeAktif)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Tidak ada periode aktif — hak laba tidak bisa dihitung. '
                'Isi Gaji Pokok manual kalau tetap ingin memproses.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          TextField(
            controller: _gajiController,
            decoration: InputDecoration(
              labelText: 'Gaji Pokok',
              prefixText: 'Rp ',
              helperText: _adaPeriodeAktif
                  ? 'Hak laba periode ini: ${AppFormatter.rupiah(_hakLabaKotor)} — '
                      'sudah diambil: ${AppFormatter.rupiah(_sudahDiambilPeriodeIni)} — '
                      'sisa: ${AppFormatter.rupiah((_hakLabaKotor - _sudahDiambilPeriodeIni).clamp(0, double.infinity).toDouble())} '
                      '(boleh diedit)'
                  : null,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            onChanged: (_) => setState(() => _metodeController.updateTotal(_gaji)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _kasbonController,
            decoration: InputDecoration(
              labelText: 'Potongan Kasbon',
              prefixText: 'Rp ',
              helperText:
                  'Otomatis dari sisa kasbon belum lunas: ${AppFormatter.rupiah(_kasbonTersedia)} (boleh diedit)',
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
              helperText:
                  'Otomatis dari sisa dana talang belum lunas: ${AppFormatter.rupiah(_talangTersedia)} (boleh diedit)',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          MetodePembayaranField(controller: _metodeController),
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
