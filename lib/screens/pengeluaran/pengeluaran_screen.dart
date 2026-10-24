import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../models/pengeluaran_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/kategori_dropdown_field.dart';
import '../../widgets/metode_pembayaran_field.dart';
import '../../core/utils/rupiah_input_formatter.dart';
import '../../providers/auth_provider.dart';

class PengeluaranScreen extends ConsumerWidget {
  const PengeluaranScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodeAktifAsync = ref.watch(periodeAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran')),
      body: periodeAktifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (periode) {
          final pengeluaranAsync =
              ref.watch(daftarPengeluaranProvider(periode?.id));
          return pengeluaranAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(message: 'Belum ada pengeluaran');
              }
              final total = list.fold<double>(0, (s, p) => s + p.totalKeluar);
              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Pengeluaran (+ Admin Bank)',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          AppFormatter.rupiah(total),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.danger,
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
                        final isKasbon = p.kategori == 'Kasbon';
                        return Card(
                          child: ListTile(
                            onTap: isKasbon
                                ? null
                                : () => _showEditDialog(context, ref, p),
                            title: Text(p.kategori,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${AppFormatter.tanggal(p.tanggal)} • '
                              '${p.sumber == AppConstants.sumberBank ? "Transfer" : "Cash"}'
                              '${p.biayaAdmin > 0 ? " (+admin ${AppFormatter.rupiah(p.biayaAdmin)})" : ""}'
                              '${p.keterangan != null ? " • ${p.keterangan}" : ""}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '-${AppFormatter.rupiah(p.totalKeluar)}',
                                  style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontWeight: FontWeight.w700),
                                ),
                                if (!isKasbon)
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

  Widget _formFields({
    required BuildContext context,
    required String kategori,
    required ValueChanged<String> onKategoriChanged,
    required TextEditingController nominalController,
    required TextEditingController keteranganController,
    required String sumber,
    required ValueChanged<String> onSumberChanged,
    required String jenisTransfer,
    required ValueChanged<String?> onJenisTransferChanged,
    required DateTime tanggal,
    required ValueChanged<DateTime> onTanggalChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TanggalEditField(tanggal: tanggal, onChanged: onTanggalChanged),
        const SizedBox(height: 12),
        KategoriDropdownField(
          tipe: AppConstants.kategoriTipePengeluaran,
          value: kategori,
          exclude: const ['Kasbon'],
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
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: AppConstants.sumberCash, label: Text('Cash')),
            ButtonSegment(
                value: AppConstants.sumberBank, label: Text('Transfer')),
          ],
          selected: {sumber},
          onSelectionChanged: (s) => onSumberChanged(s.first),
        ),
        if (sumber == AppConstants.sumberBank) ...[
          const SizedBox(height: 12),
          JenisTransferField(value: jenisTransfer, onChanged: onJenisTransferChanged),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: keteranganController,
          decoration: const InputDecoration(labelText: 'Keterangan'),
        ),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Catatan: untuk kasbon karyawan, gunakan menu Kasbon '
            'agar tercatat sebagai piutang, bukan kerugian.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ),
      ],
    );
  }

  void _showTambahDialog(BuildContext context, WidgetRef ref) {
    final nominalController = TextEditingController();
    final keteranganController = TextEditingController();
    String kategori = 'Pengeluaran Lain';
    String sumber = AppConstants.sumberCash;
    String jenisTransfer = AppConstants.jenisTransferGratis;
    DateTime tanggal = DateTime.now();
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah Pengeluaran'),
              content: SingleChildScrollView(
                child: _formFields(
                  context: context,
                  kategori: kategori,
                  onKategoriChanged: (v) => setDialogState(() => kategori = v),
                  nominalController: nominalController,
                  keteranganController: keteranganController,
                  sumber: sumber,
                  onSumberChanged: (v) => setDialogState(() => sumber = v),
                  jenisTransfer: jenisTransfer,
                  onJenisTransferChanged: (v) =>
                      setDialogState(() => jenisTransfer = v ?? AppConstants.jenisTransferGratis),
                  tanggal: tanggal,
                  onTanggalChanged: (v) => setDialogState(() => tanggal = v),
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
                          setDialogState(() => loading = true);
                          try {
                            final repo = await ref
                                .read(pengeluaranRepositoryProvider.future);
                            final periodeRepo = await ref
                                .read(periodeRepositoryProvider.future);
                            final periodeAktif =
                                await periodeRepo.getPeriodeAktif();
                            await repo.tambahPengeluaran(
                              tanggal: tanggal,
                              kategori: kategori,
                              nominal: nominal,
                              sumber: sumber,
                              jenisTransfer:
                                  sumber == AppConstants.sumberBank ? jenisTransfer : null,
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
      BuildContext context, WidgetRef ref, PengeluaranModel p) {
    final nominalController =
        TextEditingController(text: p.nominal.toStringAsFixed(0));
    final keteranganController = TextEditingController(text: p.keterangan ?? '');
    String kategori = p.kategori;
    String sumber = p.sumber;
    String jenisTransfer = p.jenisTransfer ?? AppConstants.jenisTransferGratis;
    DateTime tanggal = p.tanggal;
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Pengeluaran'),
              content: SingleChildScrollView(
                child: _formFields(
                  context: context,
                  kategori: kategori,
                  onKategoriChanged: (v) => setDialogState(() => kategori = v),
                  nominalController: nominalController,
                  keteranganController: keteranganController,
                  sumber: sumber,
                  onSumberChanged: (v) => setDialogState(() => sumber = v),
                  jenisTransfer: jenisTransfer,
                  onJenisTransferChanged: (v) =>
                      setDialogState(() => jenisTransfer = v ?? AppConstants.jenisTransferGratis),
                  tanggal: tanggal,
                  onTanggalChanged: (v) => setDialogState(() => tanggal = v),
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
                          setDialogState(() => loading = true);
                          try {
                            final repo = await ref
                                .read(pengeluaranRepositoryProvider.future);
                            await repo.editPengeluaran(
                              id: p.id!,
                              tanggal: tanggal,
                              kategori: kategori,
                              nominal: nominal,
                              sumber: sumber,
                              jenisTransfer:
                                  sumber == AppConstants.sumberBank ? jenisTransfer : null,
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
                              ScaffoldMessenger.of(dialogContext)
                                  .showSnackBar(SnackBar(content: Text('$e')));
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
      title: 'Hapus Pengeluaran?',
      message:
          'Pengeluaran "$kategori" akan dihapus dan saldo (termasuk biaya admin bila ada) akan dikembalikan. Lanjutkan?',
      confirmLabel: 'Ya, Hapus',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    try {
      final repo = await ref.read(pengeluaranRepositoryProvider.future);
      await repo.hapusPengeluaran(id);
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
