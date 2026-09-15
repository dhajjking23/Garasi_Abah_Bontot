import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common_widgets.dart';

class ModalScreen extends ConsumerWidget {
  const ModalScreen({super.key});

  Future<void> _ubah(BuildContext context, WidgetRef ref,
      {required String jenis, required String aksi}) async {
    final judulJenis =
        jenis == AppConstants.modalJenisCash ? 'Modal Cash' : 'Modal Bank';
    final judulAksi = aksi == AppConstants.modalAksiTambah ? 'Tambah' : 'Kurangi';
    final result =
        await showNominalInputDialog(context, title: '$judulAksi $judulJenis');
    if (result == null) return;
    final repo = await ref.read(saldoRepositoryProvider.future);
    try {
      await repo.ubahModal(
        jenis: jenis,
        aksi: aksi,
        nominal: result.nominal,
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

  Future<void> _edit(BuildContext context, WidgetRef ref,
      {required String jenis, required double nilaiSaatIni}) async {
    final judulJenis =
        jenis == AppConstants.modalJenisCash ? 'Modal Cash' : 'Modal Bank';
    final result = await showNominalInputDialog(
      context,
      title: 'Edit $judulJenis',
      confirmLabel: 'Update',
      initialNominal: nilaiSaatIni,
      helperText: 'Nominal baru akan menggantikan $judulJenis saat ini.',
    );
    if (result == null) return;
    final repo = await ref.read(saldoRepositoryProvider.future);
    await repo.editModal(
      jenis: jenis,
      nominalBaru: result.nominal,
      keterangan: result.keterangan,
    );
    refreshSemuaData(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldoAsync = ref.watch(saldoProvider);
    final riwayatAsync = ref.watch(histroiModalProvider(null));
    final isOwner = ref.watch(isOwnerAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(saldoProvider);
              ref.invalidate(histroiModalProvider);
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
              ref.invalidate(histroiModalProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                      const Text('Modal Total',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(
                        AppFormatter.rupiah(saldo.modalTotal),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ModalJenisCard(
                  label: 'Modal Cash',
                  value: saldo.modalCash,
                  icon: Icons.payments_outlined,
                  isOwner: isOwner,
                  onTambah: () => _ubah(context, ref,
                      jenis: AppConstants.modalJenisCash,
                      aksi: AppConstants.modalAksiTambah),
                  onKurangi: () => _ubah(context, ref,
                      jenis: AppConstants.modalJenisCash,
                      aksi: AppConstants.modalAksiKurang),
                  onEdit: () => _edit(context, ref,
                      jenis: AppConstants.modalJenisCash,
                      nilaiSaatIni: saldo.modalCash),
                ),
                const SizedBox(height: 12),
                _ModalJenisCard(
                  label: 'Modal Bank',
                  value: saldo.modalBank,
                  icon: Icons.account_balance_outlined,
                  isOwner: isOwner,
                  onTambah: () => _ubah(context, ref,
                      jenis: AppConstants.modalJenisBank,
                      aksi: AppConstants.modalAksiTambah),
                  onKurangi: () => _ubah(context, ref,
                      jenis: AppConstants.modalJenisBank,
                      aksi: AppConstants.modalAksiKurang),
                  onEdit: () => _edit(context, ref,
                      jenis: AppConstants.modalJenisBank,
                      nilaiSaatIni: saldo.modalBank),
                ),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Riwayat Perubahan Modal'),
                riwayatAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Text('Error: $e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return const EmptyState(
                          message: 'Belum ada riwayat perubahan modal');
                    }
                    return Column(
                      children: [
                        for (final h in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RiwayatMutasiTile(
                              tanggal: h.tanggal,
                              label:
                                  '${h.aksi == AppConstants.modalAksiTambah ? "Tambah" : h.aksi == AppConstants.modalAksiKurang ? "Kurangi" : "Edit"} Modal ${h.jenis == AppConstants.modalJenisCash ? "Cash" : "Bank"}',
                              keterangan: h.keterangan,
                              nominal: h.aksi == AppConstants.modalAksiEdit
                                  ? (h.saldoSesudah - h.saldoSebelum).abs()
                                  : h.nominal,
                              isMasuk: h.aksi == AppConstants.modalAksiEdit
                                  ? h.saldoSesudah >= h.saldoSebelum
                                  : h.aksi == AppConstants.modalAksiTambah,
                              saldoSetelah: h.saldoSesudah,
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
}

class _ModalJenisCard extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final bool isOwner;
  final VoidCallback onTambah;
  final VoidCallback onKurangi;
  final VoidCallback onEdit;

  const _ModalJenisCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.isOwner,
    required this.onTambah,
    required this.onKurangi,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (isOwner)
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit $label',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppFormatter.rupiah(value),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (isOwner) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTambah,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Tambah'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onKurangi,
                    icon: const Icon(Icons.remove, size: 16),
                    label: const Text('Kurangi'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
