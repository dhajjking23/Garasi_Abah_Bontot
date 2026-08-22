import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../models/periode_model.dart';
import '../../widgets/common_widgets.dart';
import '../pembagian_laba/pembagian_laba_screen.dart';

class RiwayatPeriodeScreen extends ConsumerWidget {
  const RiwayatPeriodeScreen({super.key});

  Future<void> _bukaKembali(
      BuildContext context, WidgetRef ref, PeriodeModel periode) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Buka Kembali Periode?',
      message:
          'Periode "${periode.namaPeriode}" akan diaktifkan kembali untuk koreksi transaksi. '
          'Pastikan tidak ada periode lain yang sedang aktif. Lanjutkan?',
      confirmLabel: 'Ya, Buka Kembali',
    );
    if (!konfirmasi) return;
    try {
      final repo = await ref.read(periodeRepositoryProvider.future);
      await repo.bukaPeriode(periode.id!);
      refreshSemuaData(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Periode berhasil dibuka kembali')),
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
    final periodeAsync = ref.watch(semuaPeriodeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Periode')),
      body: periodeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(message: 'Belum ada periode pembukuan');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final periode = list[i];
              final aktif = periode.status == AppConstants.statusPeriodeAktif;
              return Card(
                child: ListTile(
                  title: Text(periode.namaPeriode,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${AppFormatter.tanggal(periode.tanggalMulai)}'
                    '${periode.tanggalSelesai != null ? " - ${AppFormatter.tanggal(periode.tanggalSelesai!)}" : ""}'
                    '\nModal Awal: ${AppFormatter.rupiah(periode.modalAwal)}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: aktif
                              ? AppTheme.success.withOpacity(0.12)
                              : Colors.grey.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          aktif ? 'Aktif' : 'Tutup',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: aktif ? AppTheme.success : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      if (!aktif)
                        IconButton(
                          icon: const Icon(Icons.lock_open_outlined, size: 20),
                          tooltip: 'Buka Kembali Periode',
                          onPressed: () => _bukaKembali(context, ref, periode),
                        ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PembagianLabaScreen(
                          periodeId: periode.id!,
                          namaPeriode: periode.namaPeriode,
                          sudahTutup: !aktif,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
