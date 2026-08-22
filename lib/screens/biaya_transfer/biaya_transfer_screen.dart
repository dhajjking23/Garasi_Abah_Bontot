import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../core/utils/rupiah_input_formatter.dart';
import '../../models/biaya_transfer_manual_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../../providers/auth_provider.dart';

/// Halaman Biaya Transfer (V3.1 Patch #4).
///
/// Menampilkan riwayat biaya transfer MANUAL (dicatat langsung di sini)
/// dan mendukung tambah/edit/hapus. Biaya transfer manual TIDAK memotong
/// Cash/Saldo Bank — murni catatan biaya untuk laporan. Total gabungan
/// dengan biaya admin otomatis (dari transaksi Pengeluaran via Transfer)
/// ditampilkan di Dashboard & Laporan Periode sebagai "Biaya Transfer
/// (Periode)".
class BiayaTransferScreen extends ConsumerWidget {
  const BiayaTransferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodeAktifAsync = ref.watch(periodeAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Biaya Transfer')),
      body: periodeAktifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (periode) {
          final daftarAsync =
              ref.watch(daftarBiayaTransferManualProvider(periode?.id));
          return daftarAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
            data: (list) {
              final totalManual =
                  list.fold<double>(0, (s, b) => s + b.nominal);
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
                        const Text('Total Biaya Transfer Manual (Periode)',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          AppFormatter.rupiah(totalManual),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.danger,
                              fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Biaya transfer dari transaksi Pengeluaran (Transfer) '
                        'terhitung otomatis dan tidak perlu dicatat ulang di sini. '
                        'Gunakan halaman ini untuk biaya transfer manual lain '
                        '(mis. biaya admin bank yang tidak terkait pengeluaran '
                        'tertentu).',
                        style: TextStyle(fontSize: 11, color: Colors.black45),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: list.isEmpty
                        ? const EmptyState(
                            message: 'Belum ada biaya transfer manual')
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final b = list[i];
                              return Card(
                                child: ListTile(
                                  onTap: () =>
                                      _showEditDialog(context, ref, b),
                                  title: Text(b.namaTujuan,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    '${AppFormatter.tanggal(b.tanggal)}'
                                    '${b.keterangan != null && b.keterangan!.isNotEmpty ? " • ${b.keterangan}" : ""}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '-${AppFormatter.rupiah(b.nominal)}',
                                        style: const TextStyle(
                                            color: AppTheme.danger,
                                            fontWeight: FontWeight.w700),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: AppTheme.danger),
                                        onPressed: () =>
                                            _hapus(context, ref, b),
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

  void _showTambahDialog(BuildContext context, WidgetRef ref) {
    final namaTujuanController = TextEditingController();
    final keteranganController = TextEditingController();
    final nominalController = TextEditingController();
    DateTime tanggal = DateTime.now();
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah Biaya Transfer'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TanggalEditField(
                      tanggal: tanggal,
                      onChanged: (v) => setDialogState(() => tanggal = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: namaTujuanController,
                      decoration: const InputDecoration(
                          labelText: 'Nama Tujuan Transfer'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nominalController,
                      decoration: const InputDecoration(
                          labelText: 'Nominal Biaya', prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keteranganController,
                      decoration: const InputDecoration(
                          labelText: 'Keterangan (opsional)'),
                    ),
                  ],
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
                          final namaTujuan = namaTujuanController.text.trim();
                          final nominal = double.tryParse(
                              nominalController.text.replaceAll('.', ''));
                          if (namaTujuan.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Nama tujuan transfer harus diisi')));
                            return;
                          }
                          if (nominal == null || nominal <= 0) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Nominal biaya harus diisi')));
                            return;
                          }
                          setDialogState(() => loading = true);
                          try {
                            final repo = await ref.read(
                                biayaTransferManualRepositoryProvider.future);
                            final periodeRepo = await ref
                                .read(periodeRepositoryProvider.future);
                            final periodeAktif =
                                await periodeRepo.getPeriodeAktif();
                            await repo.tambah(
                              tanggal: tanggal,
                              namaTujuan: namaTujuan,
                              keterangan:
                                  keteranganController.text.trim().isEmpty
                                      ? null
                                      : keteranganController.text.trim(),
                              nominal: nominal,
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
      BuildContext context, WidgetRef ref, BiayaTransferManualModel b) {
    final namaTujuanController = TextEditingController(text: b.namaTujuan);
    final keteranganController =
        TextEditingController(text: b.keterangan ?? '');
    final nominalController =
        TextEditingController(text: b.nominal.toStringAsFixed(0));
    DateTime tanggal = b.tanggal;
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Biaya Transfer'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TanggalEditField(
                      tanggal: tanggal,
                      onChanged: (v) => setDialogState(() => tanggal = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: namaTujuanController,
                      decoration: const InputDecoration(
                          labelText: 'Nama Tujuan Transfer'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nominalController,
                      decoration: const InputDecoration(
                          labelText: 'Nominal Biaya', prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keteranganController,
                      decoration: const InputDecoration(
                          labelText: 'Keterangan (opsional)'),
                    ),
                  ],
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
                          final namaTujuan = namaTujuanController.text.trim();
                          final nominal = double.tryParse(
                              nominalController.text.replaceAll('.', ''));
                          if (namaTujuan.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Nama tujuan transfer harus diisi')));
                            return;
                          }
                          if (nominal == null || nominal <= 0) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Nominal biaya harus diisi')));
                            return;
                          }
                          setDialogState(() => loading = true);
                          try {
                            final repo = await ref.read(
                                biayaTransferManualRepositoryProvider.future);
                            await repo.edit(
                              id: b.id!,
                              tanggal: tanggal,
                              namaTujuan: namaTujuan,
                              keterangan:
                                  keteranganController.text.trim().isEmpty
                                      ? null
                                      : keteranganController.text.trim(),
                              nominal: nominal,
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
      BuildContext context, WidgetRef ref, BiayaTransferManualModel b) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Hapus Biaya Transfer?',
      message:
          'Biaya transfer ke "${b.namaTujuan}" (${AppFormatter.rupiah(b.nominal)}) akan dihapus dari catatan. Lanjutkan?',
      confirmLabel: 'Ya, Hapus',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    try {
      final repo =
          await ref.read(biayaTransferManualRepositoryProvider.future);
      await repo.hapus(b.id!);
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
