import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common_widgets.dart';

class SaldoBankScreen extends ConsumerWidget {
  const SaldoBankScreen({super.key});

  Future<void> _tambahSaldo(BuildContext context, WidgetRef ref) async {
    final result =
        await showNominalInputDialog(context, title: 'Tambah Saldo Bank');
    if (result == null) return;
    final repo = await ref.read(saldoRepositoryProvider.future);
    await repo.mutasiBank(
      nominal: result.nominal,
      tipe: AppConstants.cashFlowMasuk,
      referensi: AppConstants.cashFlowRefPemasukan,
      keterangan: result.keterangan ?? 'Tambah Saldo Bank manual',
    );
    refreshSemuaData(ref);
  }

  Future<void> _kurangiSaldo(BuildContext context, WidgetRef ref) async {
    final result =
        await showNominalInputDialog(context, title: 'Kurangi Saldo Bank');
    if (result == null) return;
    final repo = await ref.read(saldoRepositoryProvider.future);
    final saldo = await repo.getSaldo();
    if (result.nominal > saldo.saldoBank) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saldo Bank tidak mencukupi')),
        );
      }
      return;
    }
    await repo.mutasiBank(
      nominal: result.nominal,
      tipe: AppConstants.cashFlowKeluar,
      referensi: AppConstants.cashFlowRefPengeluaran,
      keterangan: result.keterangan ?? 'Kurangi Saldo Bank manual',
    );
    refreshSemuaData(ref);
  }

  Future<void> _editSaldo(
      BuildContext context, WidgetRef ref, double saldoSaatIni) async {
    final result = await showNominalInputDialog(
      context,
      title: 'Edit Saldo Bank',
      confirmLabel: 'Update',
      initialNominal: saldoSaatIni,
      helperText: 'Nominal baru akan menggantikan Saldo Bank saat ini.',
    );
    if (result == null) return;
    final repo = await ref.read(saldoRepositoryProvider.future);
    await repo.editSaldoBank(result.nominal, keterangan: result.keterangan);
    refreshSemuaData(ref);
  }

  Future<void> _tarikTunai(
      BuildContext context, WidgetRef ref, double saldoSaatIni) async {
    final result = await showNominalInputDialog(
      context,
      title: 'Tarik Tunai',
      confirmLabel: 'Tarik',
      helperText:
          'Saldo Bank: ${AppFormatter.rupiah(saldoSaatIni)}. Nominal akan dipindah dari Saldo Bank ke Cash.',
    );
    if (result == null) return;
    final repo = await ref.read(saldoRepositoryProvider.future);
    try {
      await repo.tarikTunai(result.nominal, keterangan: result.keterangan);
      refreshSemuaData(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tarik tunai berhasil')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldoAsync = ref.watch(saldoProvider);
    final riwayatAsync =
        ref.watch(histroiCashFlowProvider(AppConstants.sumberBank));
    final isOwner = ref.watch(isOwnerAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saldo Bank'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(saldoProvider);
              ref.invalidate(histroiCashFlowProvider);
            },
          ),
        ],
      ),
      body: saldoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Gagal memuat: $e')),
        data: (saldo) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(saldoProvider);
              ref.invalidate(histroiCashFlowProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Saldo Bank',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(
                        AppFormatter.rupiah(saldo.saldoBank),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (isOwner)
                        IconButton(
                          onPressed: () =>
                              _editSaldo(context, ref, saldo.saldoBank),
                          icon: const Icon(Icons.edit,
                              color: Colors.white70, size: 18),
                          tooltip: 'Edit Saldo Bank',
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isOwner) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _tambahSaldo(context, ref),
                          icon: const Icon(Icons.add),
                          label: const Text('Tambah'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _kurangiSaldo(context, ref),
                          icon: const Icon(Icons.remove),
                          label: const Text('Kurangi'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _tarikTunai(context, ref, saldo.saldoBank),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Tarik Tunai'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const SectionTitle(title: 'Riwayat Transaksi Saldo Bank'),
                riwayatAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Text('Error: $e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return const EmptyState(
                          message: 'Belum ada riwayat Saldo Bank');
                    }
                    return Column(
                      children: [
                        for (final cf in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _isMutasiAntarSaldo(cf.referensi)
                                ? RiwayatMutasiTile(
                                    tanggal: cf.tanggal,
                                    label: _labelReferensi(cf.referensi),
                                    keterangan: cf.keterangan,
                                    nominal: cf.nominal,
                                    isMasuk: cf.tipe == AppConstants.cashFlowMasuk,
                                    saldoSetelah: cf.saldoSetelah,
                                    onTap: isOwner
                                        ? () => _editMutasiAntarSaldo(
                                            context, ref, cf.referensiId!, cf.nominal)
                                        : null,
                                    onDelete: isOwner
                                        ? () => _hapusMutasiAntarSaldo(
                                            context, ref, cf.referensiId!)
                                        : null,
                                  )
                                : RiwayatMutasiTile(
                                    tanggal: cf.tanggal,
                                    label: _labelReferensi(cf.referensi),
                                    keterangan: cf.keterangan,
                                    nominal: cf.nominal,
                                    isMasuk: cf.tipe == AppConstants.cashFlowMasuk,
                                    saldoSetelah: cf.saldoSetelah,
                                  ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _labelReferensi(String referensi) {
    switch (referensi) {
      case AppConstants.cashFlowRefMotorBeli:
        return 'Pembelian Motor';
      case AppConstants.cashFlowRefMotorCost:
        return 'Biaya Motor';
      case AppConstants.cashFlowRefPenjualan:
        return 'Penjualan Motor';
      case AppConstants.cashFlowRefPemasukan:
        return 'Pemasukan';
      case AppConstants.cashFlowRefPengeluaran:
        return 'Pengeluaran';
      case AppConstants.cashFlowRefKasbonAmbil:
        return 'Kasbon Diambil';
      case AppConstants.cashFlowRefKasbonBayar:
        return 'Kasbon Dibayar';
      case AppConstants.cashFlowRefDepositBank:
        return 'Deposit dari Cash';
      case AppConstants.cashFlowRefTarikTunai:
        return 'Tarik Tunai';
      case AppConstants.cashFlowRefAdjustment:
        return 'Penyesuaian Saldo';
      case AppConstants.cashFlowRefDanaTalangBeri:
        return 'Dana Talang (Beri)';
      case AppConstants.cashFlowRefDanaTalangTerima:
        return 'Dana Talang (Terima)';
      case AppConstants.cashFlowRefDanaTalangBayar:
        return 'Dana Talang (Bayar)';
      case AppConstants.cashFlowRefAdminTransfer:
        return 'Administrasi Bank';
      default:
        return referensi;
    }
  }

  bool _isMutasiAntarSaldo(String referensi) =>
      referensi == AppConstants.cashFlowRefDepositBank ||
      referensi == AppConstants.cashFlowRefTarikTunai;

  Future<void> _editMutasiAntarSaldo(
      BuildContext context, WidgetRef ref, int mutasiId, double nominalSaatIni) async {
    final result = await showNominalInputDialog(
      context,
      title: 'Edit Transaksi',
      confirmLabel: 'Update',
      initialNominal: nominalSaatIni,
      helperText: 'Nominal baru akan menggantikan transaksi ini; saldo Cash & Bank otomatis disesuaikan.',
    );
    if (result == null) return;
    try {
      final repo = await ref.read(saldoRepositoryProvider.future);
      await repo.editMutasiAntarSaldo(
        id: mutasiId,
        nominalBaru: result.nominal,
        keteranganBaru: result.keterangan,
      );
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _hapusMutasiAntarSaldo(
      BuildContext context, WidgetRef ref, int mutasiId) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Hapus Transaksi?',
      message: 'Transaksi ini akan dihapus dan saldo Cash & Bank dikembalikan seperti semula. Lanjutkan?',
      confirmLabel: 'Ya, Hapus',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    try {
      final repo = await ref.read(saldoRepositoryProvider.future);
      await repo.hapusMutasiAntarSaldo(mutasiId);
      refreshSemuaData(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
