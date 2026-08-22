import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../models/penjualan_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/metode_pembayaran_field.dart';
import '../../core/utils/rupiah_input_formatter.dart';
import '../../providers/auth_provider.dart';

class PenjualanScreen extends ConsumerWidget {
  const PenjualanScreen({super.key});

  Future<void> _bayarPiutang(
      BuildContext context, WidgetRef ref, PenjualanModel p) async {
    final result = await showNominalInputDialog(
      context,
      title: 'Cicil / Lunasi Piutang',
      confirmLabel: 'Simpan',
      initialNominal: p.sisaPembayaran,
      helperText: 'Sisa piutang: ${AppFormatter.rupiah(p.sisaPembayaran)}',
    );
    if (result == null) return;
    if (!context.mounted) return;
    final tanggal = await pickTanggal(context, DateTime.now()) ?? DateTime.now();
    try {
      final repo = await ref.read(penjualanRepositoryProvider.future);
      await repo.bayarPiutangPenjualan(
        penjualanId: p.id!,
        tanggal: tanggal,
        nominal: result.nominal,
        metodePembayaran: AppConstants.metodeCash,
        cashDibayar: result.nominal,
        keterangan: result.keterangan,
      );
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _editTanggal(
      BuildContext context, WidgetRef ref, PenjualanModel p) async {
    final picked = await pickTanggal(context, p.tanggalJual);
    if (picked == null) return;
    try {
      final repo = await ref.read(penjualanRepositoryProvider.future);
      await repo.editTanggalPenjualan(p.id!, picked);
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _hapus(
      BuildContext context, WidgetRef ref, PenjualanModel p) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Hapus Penjualan?',
      message:
          'Penjualan seharga ${AppFormatter.rupiah(p.hargaJual)} akan dihapus. '
          'Saldo dikembalikan dan status motor kembali TERSEDIA. Lanjutkan?',
      confirmLabel: 'Ya, Hapus',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    try {
      final repo = await ref.read(penjualanRepositoryProvider.future);
      await repo.hapusPenjualan(p.id!);
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodeAktifAsync = ref.watch(periodeAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Penjualan Motor')),
      body: periodeAktifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (periode) {
          final penjualanAsync =
              ref.watch(daftarPenjualanProvider(periode?.id));

          return penjualanAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
            data: (penjualanList) {
              if (penjualanList.isEmpty) {
                return const EmptyState(
                  message: 'Belum ada penjualan pada periode ini',
                  icon: Icons.sell_outlined,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: penjualanList.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final p = penjualanList[index];
                  final isCalo = p.penjual == AppConstants.penjualCalo;
                  final belumLunas = !p.isLunas;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(p.penjual,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  if (isCalo) ...[
                                    const SizedBox(width: 6),
                                    const _Badge(
                                        label: 'Tanpa Bonus',
                                        color: Colors.orange),
                                  ],
                                  if (belumLunas) ...[
                                    const SizedBox(width: 6),
                                    const _Badge(
                                        label: 'DP - Belum Lunas',
                                        color: AppTheme.danger),
                                  ],
                                ],
                              ),
                              Row(
                                children: [
                                  Text(AppFormatter.tanggal(p.tanggalJual),
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.black45)),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.edit_calendar_outlined,
                                        size: 18,
                                        color: AppTheme.primary),
                                    onPressed: () =>
                                        _editTanggal(context, ref, p),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18, color: AppTheme.danger),
                                    onPressed: () => _hapus(context, ref, p),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Harga Jual'),
                              Text(AppFormatter.rupiah(p.hargaJual)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Modal Motor'),
                              Text(AppFormatter.rupiah(p.modalMotor)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Diterima'),
                              Text(
                                  '${AppFormatter.rupiah(p.totalDiterima)} (${p.metodePembayaran})'),
                            ],
                          ),
                          if (belumLunas) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Sisa Piutang',
                                    style:
                                        TextStyle(color: AppTheme.danger)),
                                Text(
                                  AppFormatter.rupiah(p.sisaPembayaran),
                                  style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Laba',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                AppFormatter.rupiah(p.laba),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: p.laba >= 0
                                      ? AppTheme.success
                                      : AppTheme.danger,
                                ),
                              ),
                            ],
                          ),
                          if (belumLunas) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => _bayarPiutang(context, ref, p),
                                child: const Text('Cicil / Lunasi Piutang'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: ref.watch(isOwnerAdminProvider)
          ? FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _JualMotorSheet(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Jual Motor'),
      )
          : null,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _JualMotorSheet extends ConsumerStatefulWidget {
  const _JualMotorSheet();

  @override
  ConsumerState<_JualMotorSheet> createState() => _JualMotorSheetState();
}

class _JualMotorSheetState extends ConsumerState<_JualMotorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _hargaJualController = TextEditingController();
  final _dpController = TextEditingController();
  final _metodeController = MetodePembayaranController(total: 0);
  int? _motorIdTerpilih;
  String _penjual = AppConstants.daftarPenjual.first;
  DateTime _tanggalJual = DateTime.now();
  bool _bayarPenuh = true;
  bool _loading = false;

  @override
  void dispose() {
    _hargaJualController.dispose();
    _dpController.dispose();
    _metodeController.dispose();
    super.dispose();
  }

  double get _hargaJual =>
      double.tryParse(_hargaJualController.text.replaceAll('.', '')) ?? 0;
  double get _jumlahDibayarSekarang => _bayarPenuh
      ? _hargaJual
      : (double.tryParse(_dpController.text.replaceAll('.', '')) ?? 0);

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate() || _motorIdTerpilih == null) {
      if (_motorIdTerpilih == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pilih motor terlebih dahulu')));
      }
      return;
    }
    if (!_bayarPenuh && (_jumlahDibayarSekarang <= 0 || _jumlahDibayarSekarang >= _hargaJual)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nominal DP harus lebih dari 0 dan kurang dari harga jual')));
      return;
    }
    _metodeController.updateTotal(_jumlahDibayarSekarang);
    final metodeErr = _metodeController.validasi();
    if (metodeErr != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(metodeErr)));
      return;
    }
    setState(() => _loading = true);

    try {
      final repo = await ref.read(penjualanRepositoryProvider.future);
      final periodeRepo = await ref.read(periodeRepositoryProvider.future);
      final periodeAktif = await periodeRepo.getPeriodeAktif();
      final hasil = _metodeController.hasil;

      await repo.jualMotor(
        motorId: _motorIdTerpilih!,
        tanggalJual: _tanggalJual,
        hargaJual: _hargaJual,
        penjual: _penjual,
        metodePembayaran: hasil.metode,
        cashDiterima: hasil.cash,
        transferDiterima: hasil.transfer,
        jumlahDibayarSekarang: _jumlahDibayarSekarang,
        periodeId: periodeAktif?.id,
      );

      refreshSemuaData(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stokAsync = ref.watch(stokMotorTersediaProvider);
    final isCalo = _penjual == AppConstants.penjualCalo;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Jual Motor',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                stokAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Text('Error: $e'),
                  data: (stok) {
                    if (stok.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Tidak ada stok motor tersedia'),
                      );
                    }
                    return DropdownButtonFormField<int>(
                      value: _motorIdTerpilih,
                      decoration: const InputDecoration(labelText: 'Pilih Motor'),
                      items: stok
                          .map((m) => DropdownMenuItem(
                                value: m.id,
                                child: Text(
                                    '${m.kodeMotor} - ${m.namaLengkap}'),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _motorIdTerpilih = v),
                      validator: (v) => v == null ? 'Wajib dipilih' : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hargaJualController,
                  decoration: const InputDecoration(
                      labelText: 'Harga Jual', prefixText: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Wajib diisi' : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _penjual,
                  decoration: const InputDecoration(labelText: 'Penjual'),
                  items: AppConstants.daftarPenjual
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _penjual = v!),
                ),
                if (isCalo)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Penjualan lewat Calo: laba tetap tercatat, namun '
                      'tidak ikut pembagian hadiah penjualan (bonus 10%). '
                      'Fee calo tidak dicatat sistem.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tanggal Jual'),
                  subtitle: Text(AppFormatter.tanggal(_tanggalJual)),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _tanggalJual,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _tanggalJual = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bayar Lunas Sekarang'),
                  subtitle: const Text('Matikan jika pembeli baru DP dulu'),
                  value: _bayarPenuh,
                  onChanged: (v) => setState(() => _bayarPenuh = v),
                ),
                if (!_bayarPenuh) ...[
                  TextFormField(
                    controller: _dpController,
                    decoration: const InputDecoration(
                        labelText: 'Jumlah DP Sekarang', prefixText: 'Rp '),
                    keyboardType: TextInputType.number,
                    inputFormatters: [RupiahInputFormatter()],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hargaJual > 0
                        ? 'Sisa akan tercatat sebagai piutang: ${AppFormatter.rupiah((_hargaJual - _jumlahDibayarSekarang).clamp(0, _hargaJual))}'
                        : '',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 12),
                Builder(builder: (_) {
                  _metodeController.total = _jumlahDibayarSekarang;
                  return MetodePembayaranField(controller: _metodeController);
                }),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _simpan,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Simpan Penjualan'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
