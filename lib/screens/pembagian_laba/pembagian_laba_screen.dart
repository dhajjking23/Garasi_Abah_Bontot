import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';

class PembagianLabaScreen extends ConsumerWidget {
  final int periodeId;
  final String namaPeriode;
  final bool sudahTutup;

  const PembagianLabaScreen({
    super.key,
    required this.periodeId,
    required this.namaPeriode,
    this.sudahTutup = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewAsync = ref.watch(previewPembagianLabaProvider(periodeId));

    return Scaffold(
      appBar: AppBar(title: Text('Pembagian Laba - $namaPeriode')),
      body: previewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (preview) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                    const Text('Laba Bersih Periode',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(
                      AppFormatter.rupiah(preview.labaBersih),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStat(
                            label: 'Laba Motor',
                            value: preview.totalLabaMotor,
                          ),
                        ),
                        Expanded(
                          child: _MiniStat(
                            label: 'Pengeluaran',
                            value: preview.totalPengeluaranLain,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionTitle(title: 'Pembagian ke Pemilik'),
              _BagianCard(
                nama: 'Abah',
                persen: '25%',
                nominal: preview.bagianAbah,
              ),
              _BagianCard(
                nama: 'Iki',
                persen: '27.5%',
                nominal: preview.bagianIki,
              ),
              _BagianCard(
                nama: 'Andri',
                persen: '22.5%',
                nominal: preview.bagianAndri,
              ),
              _BagianCard(
                nama: 'Ilham',
                persen: '15%',
                nominal: preview.bagianIlham,
              ),
              const SizedBox(height: 20),
              SectionTitle(
                title: 'Hadiah Penjualan (10%)',
                trailing: Text(
                  AppFormatter.rupiah(preview.totalHadiahPenjualan),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppTheme.accent),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${preview.unitInternalTerjual} unit internal terjual'),
                    Text(
                      '${AppFormatter.rupiah(preview.bonusPerUnit)}/unit',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (preview.detailBonus.isEmpty)
                const EmptyState(message: 'Belum ada penjualan internal')
              else
                ...preview.detailBonus.map((d) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(d.nama,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${d.jumlahUnit} unit'),
                        trailing: Text(
                          AppFormatter.rupiah(d.totalBonus),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent),
                        ),
                      ),
                    )),
              const SizedBox(height: 20),
              if (!sudahTutup)
                ElevatedButton(
                  onPressed: () => _konfirmasiTutupBuku(context, ref),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger),
                  child: const Text('Tutup Buku & Bagi Laba'),
                )
              else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: AppTheme.success),
                      SizedBox(width: 8),
                      Text('Periode ini sudah ditutup & dibagi'),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _konfirmasiTutupBuku(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tutup Buku?'),
        content: const Text(
          'Setelah ditutup, periode ini tidak dapat diedit lagi dan hasil '
          'pembagian laba akan tersimpan permanen sebagai histori. '
          'Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              try {
                final service =
                    await ref.read(pembagianLabaServiceProvider.future);
                await service.tutupBukuDanBagiLaba(periodeId);
                refreshSemuaData(ref);
                ref.invalidate(previewPembagianLabaProvider(periodeId));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Gagal: $e')));
                }
              }
            },
            child: const Text('Ya, Tutup Buku'),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final double value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        Text(
          AppFormatter.rupiah(value),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ],
    );
  }
}

class _BagianCard extends StatelessWidget {
  final String nama;
  final String persen;
  final double nominal;

  const _BagianCard({
    required this.nama,
    required this.persen,
    required this.nominal,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.1),
          child: Text(nama[0],
              style: const TextStyle(
                  color: AppTheme.primary, fontWeight: FontWeight.w700)),
        ),
        title: Text(nama, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(persen),
        trailing: Text(
          AppFormatter.rupiah(nominal),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
