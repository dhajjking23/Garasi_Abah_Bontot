import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../models/pemasukan_model.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/kategori_dropdown_field.dart';
import '../../core/utils/rupiah_input_formatter.dart';
import '../../providers/auth_provider.dart';

class PemasukanScreen extends ConsumerWidget {
  const PemasukanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodeAktifAsync = ref.watch(periodeAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pemasukan')),
      body: periodeAktifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (periode) {
          final pemasukanAsync =
              ref.watch(daftarPemasukanProvider(periode?.id));
          return pemasukanAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(message: 'Belum ada pemasukan');
              }
              final total = list.fold<double>(0, (s, p) => s + p.nominal);
              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Pemasukan',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          AppFormatter.rupiah(total),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.success,
                              fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final p = list[i];
                        final isPenjualan = p.kategori == 'Penjualan Motor';
                        return Card(
                          child: ListTile(
                            onTap: isPenjualan
                                ? null
                                : () => _showEditDialog(context, ref, p),
                            title: Text(p.kategori,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '${AppFormatter.tanggal(p.tanggal)} • ${_labelSumber(p)}${p.keterangan != null ? " • ${p.keterangan}" : ""}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '+${AppFormatter.rupiah(p.nominal)}',
                                  style: const TextStyle(
                                      color: AppTheme.success,
                                      fontWeight: FontWeight.w700),
                                ),
                                if (!isPenjualan)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18, color: AppTheme.danger),
                                    onPressed: () =>
                                        _hapus(context, ref, p.id!, p.kategori),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: ref.watch(isOwnerAdminProvider)
          ? FloatingActionButton.extended(
        onPressed: () => _showTambahDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      )
          : null,
    );
  }

  String _labelSumber(PemasukanModel p) {
    switch (p.sumber) {
      case AppConstants.sumberBank:
        return 'Saldo Bank';
      case AppConstants.sumberCampuran:
        return 'Campuran (Cash ${AppFormatter.rupiah(p.cashMasuk)} + Bank ${AppFormatter.rupiah(p.bankMasuk)})';
      case AppConstants.sumberCash:
      default:
        return 'Cash';
    }
  }

  /// Form field bersama untuk dialog tambah & edit pemasukan.
  /// Mendukung 3 tujuan uang masuk: Cash, Saldo Bank, Campuran (V3.1 #2).
  Widget _formFields({
    required BuildContext context,
    required String kategori,
    required ValueChanged<String> onKategoriChanged,
    required TextEditingController nominalController,
    required TextEditingController keteranganController,
    required String sumber,
    required ValueChanged<String> onSumberChanged,
    required DateTime tanggal,
    required ValueChanged<DateTime> onTanggalChanged,
    required TextEditingController cashController,
    required TextEditingController bankController,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TanggalEditField(tanggal: tanggal, onChanged: onTanggalChanged),
        const SizedBox(height: 12),
        KategoriDropdownField(
          tipe: AppConstants.kategoriTipePemasukan,
          value: kategori,
          exclude: const ['Penjualan Motor'],
          onChanged: onKategoriChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: nominalController,
          decoration:
              const InputDecoration(labelText: 'Nominal', prefixText: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
        const SizedBox(height: 12),
        if (kategori != 'Tambah Modal') ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Tujuan Uang Masuk',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: AppConstants.sumberCash, label: Text('Cash')),
              ButtonSegment(
                  value: AppConstants.sumberBank, label: Text('Saldo Bank')),
              ButtonSegment(
                  value: AppConstants.sumberCampuran,
                  label: Text('Campuran')),
            ],
            selected: {sumber},
            onSelectionChanged: (s) => onSumberChanged(s.first),
          ),
          if (sumber == AppConstants.sumberCampuran) ...[
            const SizedBox(height: 12),
            TextField(
              controller: cashController,
              decoration: const InputDecoration(
                  labelText: 'Jumlah Cash', prefixText: 'Rp '),
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bankController,
              decoration: const InputDecoration(
                  labelText: 'Jumlah Saldo Bank', prefixText: 'Rp '),
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Cash + Saldo Bank harus sama dengan Nominal di atas.',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
        TextField(
          controller: keteranganController,
          decoration: const InputDecoration(labelText: 'Keterangan'),
        ),
      ],
    );
  }

  void _showTambahDialog(BuildContext context, WidgetRef ref) {
    final nominalController = TextEditingController();
    final keteranganController = TextEditingController();
    final cashController = TextEditingController();
    final bankController = TextEditingController();
    String kategori = AppConstants.kategoriPemasukan.first;
    String sumber = AppConstants.sumberCash;
    DateTime tanggal = DateTime.now();
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah Pemasukan'),
              content: SingleChildScrollView(
                child: _formFields(
                  context: context,
                  kategori: kategori,
                  onKategoriChanged: (v) => setDialogState(() => kategori = v),
                  nominalController: nominalController,
                  keteranganController: keteranganController,
                  sumber: sumber,
                  onSumberChanged: (v) => setDialogState(() => sumber = v),
                  tanggal: tanggal,
                  onTanggalChanged: (v) => setDialogState(() => tanggal = v),
                  cashController: cashController,
                  bankController: bankController,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final nominal = double.tryParse(
                              nominalController.text.replaceAll('.', ''));
                          if (nominal == null || nominal <= 0) return;
                          final cashMasuk = double.tryParse(
                                  cashController.text.replaceAll('.', '')) ??
                              0;
                          final bankMasuk = double.tryParse(
                                  bankController.text.replaceAll('.', '')) ??
                              0;
                          setDialogState(() => loading = true);
                          try {
                            final repo = await ref
                                .read(pemasukanRepositoryProvider.future);
                            final periodeRepo = await ref
                                .read(periodeRepositoryProvider.future);
                            final periodeAktif =
                                await periodeRepo.getPeriodeAktif();
                            await repo.tambahPemasukan(
                              tanggal: tanggal,
                              kategori: kategori,
                              nominal: nominal,
                              sumber: sumber,
                              cashMasuk: cashMasuk,
                              bankMasuk: bankMasuk,
                              keterangan: keteranganController.text.trim().isEmpty
                                  ? null
                                  : keteranganController.text.trim(),
                              periodeId: periodeAktif?.id,
                            );
                            refreshSemuaData(ref);
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            setDialogState(() => loading = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext)
                                  .showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditDialog(
      BuildContext context, WidgetRef ref, PemasukanModel p) {
    final nominalController =
        TextEditingController(text: p.nominal.toStringAsFixed(0));
    final keteranganController = TextEditingController(text: p.keterangan ?? '');
    final cashController =
        TextEditingController(text: p.cashMasuk.toStringAsFixed(0));
    final bankController =
        TextEditingController(text: p.bankMasuk.toStringAsFixed(0));
    String kategori = p.kategori;
    String sumber = p.sumber;
    DateTime tanggal = p.tanggal;
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Pemasukan'),
              content: SingleChildScrollView(
                child: _formFields(
                  context: context,
                  kategori: kategori,
                  onKategoriChanged: (v) => setDialogState(() => kategori = v),
                  nominalController: nominalController,
                  keteranganController: keteranganController,
                  sumber: sumber,
                  onSumberChanged: (v) => setDialogState(() => sumber = v),
                  tanggal: tanggal,
                  onTanggalChanged: (v) => setDialogState(() => tanggal = v),
                  cashController: cashController,
                  bankController: bankController,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final nominal = double.tryParse(
                              nominalController.text.replaceAll('.', ''));
                          if (nominal == null || nominal <= 0) return;
                          final cashMasuk = double.tryParse(
                                  cashController.text.replaceAll('.', '')) ??
                              0;
                          final bankMasuk = double.tryParse(
                                  bankController.text.replaceAll('.', '')) ??
                              0;
                          setDialogState(() => loading = true);
                          try {
                            final repo = await ref
                                .read(pemasukanRepositoryProvider.future);
                            await repo.editPemasukan(
                              id: p.id!,
                              tanggal: tanggal,
                              kategori: kategori,
                              nominal: nominal,
                              sumber: sumber,
                              cashMasuk: cashMasuk,
                              bankMasuk: bankMasuk,
                              keterangan: keteranganController.text.trim().isEmpty
                                  ? null
                                  : keteranganController.text.trim(),
                            );
                            refreshSemuaData(ref);
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            setDialogState(() => loading = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text('$e')));
                            }
                          }
                        },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _hapus(
      BuildContext context, WidgetRef ref, int id, String kategori) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Hapus Pemasukan?',
      message:
          'Pemasukan "$kategori" akan dihapus dan saldo akan dikembalikan. Lanjutkan?',
      confirmLabel: 'Ya, Hapus',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    try {
      final repo = await ref.read(pemasukanRepositoryProvider.future);
      await repo.hapusPemasukan(id);
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
