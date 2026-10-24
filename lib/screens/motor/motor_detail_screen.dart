import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../models/motor_model.dart';
import '../../models/motor_cost_model.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/kategori_dropdown_field.dart';
import '../../widgets/metode_pembayaran_field.dart';
import '../../core/utils/rupiah_input_formatter.dart';

class MotorDetailScreen extends ConsumerWidget {
  final int motorId;

  const MotorDetailScreen({super.key, required this.motorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final motorListAsync = ref.watch(daftarMotorProvider(null));
    final riwayatAsync = ref.watch(riwayatBiayaMotorProvider(motorId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Motor'),
        actions: [
          motorListAsync.maybeWhen(
            data: (motorList) {
              final motor = motorList.firstWhere((m) => m.id == motorId,
                  orElse: () => motorList.first);
              return PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditDetailDialog(context, ref, motor);
                  } else if (value == 'status') {
                    _toggleStatus(context, ref, motor.status);
                  } else if (value == 'hapus') {
                    _hapusMotor(context, ref);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'edit', child: Text('Edit Detail Motor')),
                  const PopupMenuItem(
                      value: 'status', child: Text('Koreksi Status')),
                  const PopupMenuItem(
                      value: 'hapus', child: Text('Hapus Motor')),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: motorListAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (motorList) {
          final motor = motorList.firstWhere((m) => m.id == motorId);
          final isTerjual = motor.isTerjual;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          motor.kodeMotor,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isTerjual ? 'Terjual' : 'Tersedia',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      motor.namaLengkap,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (motor.platNomor != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          motor.platNomor!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _DetailRow(label: 'Harga Beli', value: AppFormatter.rupiah(motor.hargaBeli)),
                      const Divider(height: 20),
                      _DetailRow(
                        label: 'TOTAL MODAL',
                        value: AppFormatter.rupiah(motor.totalModal),
                        bold: true,
                        valueColor: AppTheme.primary,
                      ),
                      const Divider(height: 20),
                      _DetailRow(
                          label: 'Tanggal Masuk',
                          value: AppFormatter.tanggal(motor.tanggalMasuk)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked =
                                await pickTanggal(context, motor.tanggalMasuk);
                            if (picked == null) return;
                            try {
                              final repo = await ref
                                  .read(motorRepositoryProvider.future);
                              await repo.editTanggalMasuk(motorId, picked);
                              refreshSemuaData(ref);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$e')));
                              }
                            }
                          },
                          icon: const Icon(Icons.edit_calendar_outlined,
                              size: 16),
                          label: const Text('Ubah Tanggal Masuk'),
                        ),
                      ),
                      const Divider(height: 20),
                      _DetailRow(
                          label: 'Metode Pembayaran',
                          value: motor.metodePembayaran == AppConstants.metodeCampuran
                              ? 'Campuran (Cash ${AppFormatter.rupiah(motor.cashDibayar)} + Transfer ${AppFormatter.rupiah(motor.transferDibayar)})'
                              : motor.metodePembayaran == AppConstants.metodeTransfer
                                  ? 'Transfer'
                                  : 'Cash'),
                      if (motor.warna != null) ...[
                        const Divider(height: 20),
                        _DetailRow(label: 'Warna', value: motor.warna!),
                      ],
                      if (motor.tahun != null) ...[
                        const Divider(height: 20),
                        _DetailRow(
                            label: 'Tahun', value: motor.tahun.toString()),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SectionTitle(title: 'Riwayat Biaya'),
              riwayatAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, st) => Text('Error: $e'),
                data: (biayaList) {
                  if (biayaList.isEmpty) {
                    return const EmptyState(message: 'Belum ada biaya tambahan');
                  }
                  return Column(
                    children: biayaList.map((b) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _showEditBiayaDialog(context, ref, b),
                          title: Text(b.kategori,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${AppFormatter.tanggal(b.tanggal)} • ${b.metodePembayaran}'
                            '${b.keterangan != null ? " • ${b.keterangan}" : ""}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                AppFormatter.rupiah(b.nominal),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppTheme.danger),
                                onPressed: () => _hapusBiaya(context, ref, b.id!),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              if (!isTerjual)
                ElevatedButton.icon(
                  onPressed: () => _showTambahBiayaDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah Biaya Susulan'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showTambahBiayaDialog(BuildContext context, WidgetRef ref) {
    final nominalController = TextEditingController();
    final keteranganController = TextEditingController();
    String kategori = AppConstants.kategoriMotorCost[1];
    final metodeController =
        MetodePembayaranController(total: 0, tampilkanJenisTransfer: true);
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah Biaya'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KategoriDropdownField(
                      tipe: AppConstants.kategoriTipeMotorCost,
                      value: kategori,
                      label: 'Kategori Biaya',
                      exclude: const ['Pembelian Unit'],
                      onChanged: (v) => setDialogState(() => kategori = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nominalController,
                      decoration: const InputDecoration(
                          labelText: 'Nominal', prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      onChanged: (v) => setDialogState(() =>
                          metodeController.total = RupiahInputFormatter.parse(v)),
                    ),
                    const SizedBox(height: 12),
                    MetodePembayaranField(controller: metodeController),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keteranganController,
                      decoration:
                          const InputDecoration(labelText: 'Keterangan (opsional)'),
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
                          final nominal = double.tryParse(
                              nominalController.text.replaceAll('.', ''));
                          if (nominal == null || nominal <= 0) return;
                          final err = metodeController.validasi();
                          if (err != null) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(err)));
                            return;
                          }

                          setDialogState(() => loading = true);
                          try {
                            final repo =
                                await ref.read(motorRepositoryProvider.future);
                            final hasil = metodeController.hasil;
                            await repo.tambahBiaya(
                              motorId: motorId,
                              kategori: kategori,
                              nominal: nominal,
                              metodePembayaran: hasil.metode,
                              cashDibayar: hasil.cash,
                              transferDibayar: hasil.transfer,
                              jenisTransfer: metodeController.jenisTransferTerpilih,
                              keterangan: keteranganController.text.trim().isEmpty
                                  ? null
                                  : keteranganController.text.trim(),
                            );
                            refreshSemuaData(ref);
                            ref.invalidate(riwayatBiayaMotorProvider(motorId));
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

  void _showEditDetailDialog(
      BuildContext context, WidgetRef ref, MotorModel motor) {
    final merkController = TextEditingController(text: motor.merk);
    final tipeController = TextEditingController(text: motor.tipe);
    final tahunController =
        TextEditingController(text: motor.tahun?.toString() ?? '');
    final platController = TextEditingController(text: motor.platNomor ?? '');
    final catatanController = TextEditingController(text: motor.catatan ?? '');
    final hargaBeliController =
        TextEditingController(text: RupiahInputFormatter.format(motor.hargaBeli));
    final metodeController = MetodePembayaranController(
        total: motor.hargaBeli, tampilkanJenisTransfer: true);
    metodeController.metode = motor.metodePembayaran;
    metodeController.jenisTransfer =
        motor.jenisTransfer ?? AppConstants.jenisTransferGratis;
    if (motor.metodePembayaran == AppConstants.metodeCampuran) {
      metodeController.cashController.text =
          RupiahInputFormatter.format(motor.cashDibayar);
      metodeController.transferController.text =
          RupiahInputFormatter.format(motor.transferDibayar);
    }
    String status = motor.status;
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Detail Motor'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: merkController,
                      decoration: const InputDecoration(labelText: 'Merk'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tipeController,
                      decoration: const InputDecoration(labelText: 'Tipe'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tahunController,
                      decoration: const InputDecoration(labelText: 'Tahun'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: platController,
                      decoration: const InputDecoration(labelText: 'Plat Nomor'),
                    ),
                    const SizedBox(height: 12),
                    if (!motor.isTerjual) ...[
                      TextField(
                        controller: hargaBeliController,
                        decoration: const InputDecoration(
                            labelText: 'Harga Beli', prefixText: 'Rp '),
                        keyboardType: TextInputType.number,
                        inputFormatters: [RupiahInputFormatter()],
                        onChanged: (v) => setDialogState(() =>
                            metodeController.total =
                                RupiahInputFormatter.parse(v)),
                      ),
                      const SizedBox(height: 12),
                      MetodePembayaranField(controller: metodeController),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(
                            value: AppConstants.statusMotorTersedia,
                            child: Text('Tersedia')),
                        DropdownMenuItem(
                            value: AppConstants.statusMotorTerjual,
                            child: Text('Terjual')),
                      ],
                      onChanged: (v) => setDialogState(() => status = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: catatanController,
                      decoration: const InputDecoration(labelText: 'Catatan'),
                      maxLines: 2,
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
                          setDialogState(() => loading = true);
                          try {
                            final repo =
                                await ref.read(motorRepositoryProvider.future);

                            // Harga beli/metode pembayaran hanya bisa
                            // diedit selagi motor belum terjual (rollback
                            // saldo tetap sederhana & akurat).
                            if (!motor.isTerjual) {
                              final hargaBaru = RupiahInputFormatter.parse(
                                  hargaBeliController.text);
                              if (hargaBaru != motor.hargaBeli ||
                                  metodeController.metode !=
                                      motor.metodePembayaran) {
                                final err = metodeController.validasi();
                                if (err != null) {
                                  throw ArgumentError(err);
                                }
                                final hasil = metodeController.hasil;
                                await repo.editPembelian(
                                  motorId: motor.id!,
                                  hargaBeliBaru: hargaBaru,
                                  metodePembayaranBaru: hasil.metode,
                                  cashDibayarBaru: hasil.cash,
                                  transferDibayarBaru: hasil.transfer,
                                  jenisTransferBaru:
                                      metodeController.jenisTransferTerpilih,
                                );
                              }
                            }

                            // Field non-finansial + status (catatan
                            // dikosongkan lewat konstruksi langsung karena
                            // copyWith tidak bisa clear ke null).
                            final motorTerbaru =
                                await repo.getById(motor.id!) ?? motor;
                            final catatanBaru =
                                catatanController.text.trim().isEmpty
                                    ? null
                                    : catatanController.text.trim();
                            await repo.updateMotor(MotorModel(
                              id: motorTerbaru.id,
                              kodeMotor: motorTerbaru.kodeMotor,
                              merk: merkController.text.trim(),
                              tipe: tipeController.text.trim(),
                              tahun: int.tryParse(tahunController.text),
                              warna: motorTerbaru.warna,
                              platNomor: platController.text.trim().isEmpty
                                  ? null
                                  : platController.text.trim(),
                              tanggalMasuk: motorTerbaru.tanggalMasuk,
                              hargaBeli: motorTerbaru.hargaBeli,
                              totalModal: motorTerbaru.totalModal,
                              status: status,
                              metodePembayaran: motorTerbaru.metodePembayaran,
                              cashDibayar: motorTerbaru.cashDibayar,
                              transferDibayar: motorTerbaru.transferDibayar,
                              catatan: catatanBaru,
                              periodeId: motorTerbaru.periodeId,
                              createdAt: motorTerbaru.createdAt,
                              updatedAt: DateTime.now(),
                            ));

                            refreshSemuaData(ref);
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            setDialogState(() => loading = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$e')));
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

  void _showEditBiayaDialog(
      BuildContext context, WidgetRef ref, MotorCostModel biaya) {
    final nominalController =
        TextEditingController(text: RupiahInputFormatter.format(biaya.nominal));
    final keteranganController =
        TextEditingController(text: biaya.keterangan ?? '');
    String kategori = biaya.kategori;
    final metodeController = MetodePembayaranController(
        total: biaya.nominal, tampilkanJenisTransfer: true);
    metodeController.metode = biaya.metodePembayaran;
    metodeController.jenisTransfer =
        biaya.jenisTransfer ?? AppConstants.jenisTransferGratis;
    DateTime tanggal = biaya.tanggal;
    if (biaya.metodePembayaran == AppConstants.metodeCampuran) {
      metodeController.cashController.text =
          RupiahInputFormatter.format(biaya.cashDibayar);
      metodeController.transferController.text =
          RupiahInputFormatter.format(biaya.transferDibayar);
    }
    bool loading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Biaya'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TanggalEditField(
                      tanggal: tanggal,
                      onChanged: (v) => setDialogState(() => tanggal = v),
                    ),
                    const SizedBox(height: 12),
                    KategoriDropdownField(
                      tipe: AppConstants.kategoriTipeMotorCost,
                      value: kategori,
                      label: 'Kategori Biaya',
                      exclude: const ['Pembelian Unit'],
                      onChanged: (v) => setDialogState(() => kategori = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nominalController,
                      decoration: const InputDecoration(
                          labelText: 'Nominal', prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      onChanged: (v) => setDialogState(() =>
                          metodeController.total = RupiahInputFormatter.parse(v)),
                    ),
                    const SizedBox(height: 12),
                    MetodePembayaranField(controller: metodeController),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keteranganController,
                      decoration:
                          const InputDecoration(labelText: 'Keterangan (opsional)'),
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
                          final nominal = RupiahInputFormatter.parse(
                              nominalController.text);
                          if (nominal <= 0) return;
                          final err = metodeController.validasi();
                          if (err != null) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(err)));
                            return;
                          }
                          setDialogState(() => loading = true);
                          try {
                            final repo =
                                await ref.read(motorRepositoryProvider.future);
                            final hasil = metodeController.hasil;
                            await repo.editBiaya(
                              biayaId: biaya.id!,
                              kategori: kategori,
                              nominalBaru: nominal,
                              metodePembayaran: hasil.metode,
                              cashDibayar: hasil.cash,
                              transferDibayar: hasil.transfer,
                              jenisTransfer: metodeController.jenisTransferTerpilih,
                              keterangan: keteranganController.text.trim().isEmpty
                                  ? null
                                  : keteranganController.text.trim(),
                            );
                            if (tanggal != biaya.tanggal) {
                              await repo.editTanggalBiaya(biaya.id!, tanggal);
                            }
                            refreshSemuaData(ref);
                            ref.invalidate(riwayatBiayaMotorProvider(motorId));
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            setDialogState(() => loading = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _hapusBiaya(BuildContext context, WidgetRef ref, int biayaId) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Hapus Biaya?',
      message:
          'Biaya ini akan dihapus, saldo dikembalikan, dan modal motor dihitung ulang. Lanjutkan?',
      confirmLabel: 'Ya, Hapus',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    try {
      final repo = await ref.read(motorRepositoryProvider.future);
      await repo.hapusBiaya(biayaId);
      refreshSemuaData(ref);
      ref.invalidate(riwayatBiayaMotorProvider(motorId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleStatus(
      BuildContext context, WidgetRef ref, String statusSaatIni) async {
    final statusBaru = statusSaatIni == AppConstants.statusMotorTersedia
        ? AppConstants.statusMotorTerjual
        : AppConstants.statusMotorTersedia;
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Koreksi Status Motor?',
      message: statusSaatIni == AppConstants.statusMotorTersedia
          ? 'Ini hanya untuk MENGOREKSI kesalahan input status. Untuk menjual '
              'motor secara resmi (tercatat laba & saldo), gunakan menu Jual '
              'Motor di halaman Penjualan. Lanjutkan ubah status ke Terjual?'
          : 'Motor ini punya catatan penjualan resmi. Untuk membatalkan '
              'penjualan (rollback saldo & laba), hapus transaksinya lewat '
              'menu Penjualan, bukan di sini. Lanjutkan ubah status ke Tersedia '
              '(TANPA mengubah saldo/laba)?',
      confirmLabel: 'Ya, Ubah',
    );
    if (!konfirmasi) return;
    try {
      final repo = await ref.read(motorRepositoryProvider.future);
      final motor = await repo.getById(motorId);
      if (motor == null) return;
      await repo.updateMotor(motor.copyWith(status: statusBaru));
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _hapusMotor(BuildContext context, WidgetRef ref) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Hapus Motor Ini?',
      message:
          'Semua catatan pembelian, biaya, dan penjualan (jika sudah terjual) '
          'akan dihapus, dan saldo Cash/Bank dikembalikan seperti sebelum '
          'motor ini pernah dicatat. Tindakan ini tidak bisa dibatalkan. '
          'Lanjutkan?',
      confirmLabel: 'Ya, Hapus Permanen',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    try {
      final repo = await ref.read(motorRepositoryProvider.future);
      await repo.hapusMotor(motorId);
      refreshSemuaData(ref);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
