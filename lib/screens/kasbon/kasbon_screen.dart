import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../models/kasbon_model.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/metode_pembayaran_field.dart';
import '../../core/utils/rupiah_input_formatter.dart';
import '../../providers/auth_provider.dart';

class KasbonScreen extends ConsumerWidget {
  const KasbonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kasbonAsync = ref.watch(daftarKasbonProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kasbon Karyawan')),
      body: kasbonAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(message: 'Belum ada data kasbon');
          }
          final belumLunas = list
              .where((k) => k.status == AppConstants.statusKasbonBelumLunas)
              .fold<double>(0, (s, k) => s + k.jumlah);

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
                    const Text('Total Piutang Belum Lunas',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      AppFormatter.rupiah(belumLunas),
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
                    final k = list[i];
                    final lunas = k.isLunas;
                    return Card(
                      child: ListTile(
                        onTap: lunas
                            ? null
                            : () => _showEditDialog(context, ref, k),
                        title: Text(k.namaKaryawan,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${AppFormatter.tanggal(k.tanggal)}${k.keterangan != null ? " • ${k.keterangan}" : ""}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  AppFormatter.rupiah(k.jumlah),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                if (lunas)
                                  const Text('Lunas',
                                      style: TextStyle(
                                          color: AppTheme.success,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700))
                                else
                                  GestureDetector(
                                    onTap: () async {
                                      final repo = await ref
                                          .read(kasbonRepositoryProvider.future);
                                      await repo.bayarKasbon(k.id!);
                                      refreshSemuaData(ref);
                                    },
                                    child: const Text('Tandai Lunas',
                                        style: TextStyle(
                                            color: AppTheme.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            decoration:
                                                TextDecoration.underline)),
                                  ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: AppTheme.danger),
                              onPressed: () => _hapus(context, ref, k),
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
      ),
      floatingActionButton: ref.watch(isOwnerAdminProvider)
          ? FloatingActionButton.extended(
        onPressed: () => _showTambahDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Kasbon Baru'),
      )
          : null,
    );
  }

  void _showTambahDialog(BuildContext context, WidgetRef ref) {
    final jumlahController = TextEditingController();
    final keteranganController = TextEditingController();
    String namaKaryawan = AppConstants.karyawanDefault.first;
    DateTime tanggal = DateTime.now();
    String sumber = AppConstants.sumberCash;
    String jenisTransfer = AppConstants.jenisTransferGratis;
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Kasbon Baru'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TanggalEditField(
                      tanggal: tanggal,
                      onChanged: (v) => setDialogState(() => tanggal = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: namaKaryawan,
                      decoration: const InputDecoration(labelText: 'Karyawan'),
                      items: AppConstants.karyawanDefault
                          .map((k) =>
                              DropdownMenuItem(value: k, child: Text(k)))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => namaKaryawan = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: jumlahController,
                      decoration: const InputDecoration(
                          labelText: 'Jumlah', prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: AppConstants.sumberCash,
                            label: Text('Cash')),
                        ButtonSegment(
                            value: AppConstants.sumberBank,
                            label: Text('Transfer')),
                      ],
                      selected: {sumber},
                      onSelectionChanged: (s) =>
                          setDialogState(() => sumber = s.first),
                    ),
                    if (sumber == AppConstants.sumberBank) ...[
                      const SizedBox(height: 12),
                      JenisTransferField(
                        value: jenisTransfer,
                        onChanged: (v) => setDialogState(
                            () => jenisTransfer = v ?? AppConstants.jenisTransferGratis),
                      ),
                    ],
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
                          final jumlah = double.tryParse(
                              jumlahController.text.replaceAll('.', ''));
                          if (jumlah == null || jumlah <= 0) return;
                          setDialogState(() => loading = true);
                          try {
                            final repo = await ref
                                .read(kasbonRepositoryProvider.future);
                            await repo.ambilKasbon(
                              namaKaryawan: namaKaryawan,
                              tanggal: tanggal,
                              jumlah: jumlah,
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

  void _showEditDialog(BuildContext context, WidgetRef ref, KasbonModel k) {
    final jumlahController =
        TextEditingController(text: k.jumlah.toStringAsFixed(0));
    final keteranganController = TextEditingController(text: k.keterangan ?? '');
    String namaKaryawan = k.namaKaryawan;
    DateTime tanggal = k.tanggal;
    String sumber = k.sumber;
    String jenisTransfer = k.jenisTransfer ?? AppConstants.jenisTransferGratis;
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Kasbon'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TanggalEditField(
                      tanggal: tanggal,
                      onChanged: (v) => setDialogState(() => tanggal = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: AppConstants.karyawanDefault.contains(namaKaryawan)
                          ? namaKaryawan
                          : AppConstants.karyawanDefault.first,
                      decoration: const InputDecoration(labelText: 'Karyawan'),
                      items: AppConstants.karyawanDefault
                          .map((n) =>
                              DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => namaKaryawan = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: jumlahController,
                      decoration: const InputDecoration(
                          labelText: 'Jumlah', prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: AppConstants.sumberCash,
                            label: Text('Cash')),
                        ButtonSegment(
                            value: AppConstants.sumberBank,
                            label: Text('Transfer')),
                      ],
                      selected: {sumber},
                      onSelectionChanged: (s) =>
                          setDialogState(() => sumber = s.first),
                    ),
                    if (sumber == AppConstants.sumberBank) ...[
                      const SizedBox(height: 12),
                      JenisTransferField(
                        value: jenisTransfer,
                        onChanged: (v) => setDialogState(
                            () => jenisTransfer = v ?? AppConstants.jenisTransferGratis),
                      ),
                    ],
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
                          final jumlah = double.tryParse(
                              jumlahController.text.replaceAll('.', ''));
                          if (jumlah == null || jumlah <= 0) return;
                          setDialogState(() => loading = true);
                          try {
                            final repo = await ref
                                .read(kasbonRepositoryProvider.future);
                            await repo.editKasbon(
                              kasbonId: k.id!,
                              namaKaryawan: namaKaryawan,
                              tanggal: tanggal,
                              jumlahBaru: jumlah,
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

  Future<void> _hapus(BuildContext context, WidgetRef ref, KasbonModel k) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Hapus Kasbon?',
      message: k.isLunas
          ? 'Kasbon ${k.namaKaryawan} yang sudah lunas ini akan dihapus dari catatan (tidak mempengaruhi saldo karena sudah lunas). Lanjutkan?'
          : 'Kasbon ${k.namaKaryawan} (${AppFormatter.rupiah(k.jumlah)}) akan dihapus dan Cash akan dikembalikan. Lanjutkan?',
      confirmLabel: 'Ya, Hapus',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    try {
      final repo = await ref.read(kasbonRepositoryProvider.future);
      await repo.hapusKasbon(k.id!);
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
