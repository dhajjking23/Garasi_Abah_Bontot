import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../services/partner_settlement_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/metode_pembayaran_field.dart';

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
              // V5.8 — Partner Net Settlement Engine: hak laba tiap
              // partner dipotong Kasbon & Dana Talang yang masih
              // berjalan, supaya kelihatan berapa yang BENAR-BENAR bisa
              // dibayarkan tunai (bukan cuma hak kotor di atas). Murni
              // tampilan tambahan — tidak mengubah angka Tutup Buku.
              const SectionTitle(title: 'Net Settlement (Setelah Potongan)'),
              Consumer(builder: (context, ref, _) {
                final settlementAsync =
                    ref.watch(partnerNetSettlementProvider(periodeId));
                return settlementAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, st) => Text('Error: $e'),
                  data: (list) => Column(
                    children: list
                        .map((s) => _NetSettlementCard(settlement: s))
                        .toList(),
                  ),
                );
              }),
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
    String? errorMsg;
    bool loading = false;
    MetodePembayaranController? controller;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return Consumer(builder: (context, ref, _) {
            final saldoAsync = ref.watch(saldoProvider);
            final totalNetAsync =
                ref.watch(totalNetTutupBukuProvider(periodeId));

            return totalNetAsync.when(
              loading: () => const AlertDialog(
                content: SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, st) => AlertDialog(
                title: const Text('Gagal Memuat'),
                content: Text('$e'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
              data: (total) {
                // Dibuat SEKALI (lazy) supaya input cash/transfer yang
                // sudah diketik user tidak hilang tiap kali dialog
                // rebuild (mis. setelah error validasi).
                controller ??= MetodePembayaranController(total: total);
                final ctrl = controller!;
                final tersediaCash = saldoAsync.maybeWhen(
                    data: (s) => s.cash, orElse: () => null);
                final tersediaBank = saldoAsync.maybeWhen(
                    data: (s) => s.saldoBank, orElse: () => null);

                return AlertDialog(
                    title: const Text('Tutup Buku?'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Periode ini akan ditutup, dan Cash/Bank BENAR-BENAR '
                            'akan berkurang untuk membayar SISA distribusi laba '
                            '(Abah/Iki/Andri/Ilham, setelah dikurangi yang sudah '
                            'diambil lewat Gajihan periode ini) + bonus penjualan. '
                            'Periode TETAP bisa dibuka lagi untuk koreksi kalau '
                            'diperlukan (closing bukan kunci permanen).',
                          ),
                          const SizedBox(height: 12),
                          Text('Total dibayar sekarang: ${AppFormatter.rupiah(total)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          if (tersediaCash != null)
                            Text('Cash tersedia: ${AppFormatter.rupiah(tersediaCash)}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                          if (tersediaBank != null)
                            Text('Saldo Bank tersedia: ${AppFormatter.rupiah(tersediaBank)}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                          const SizedBox(height: 12),
                          MetodePembayaranField(controller: ctrl),
                          if (errorMsg != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(errorMsg!,
                                  style: const TextStyle(
                                      color: AppTheme.danger, fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed:
                            loading ? null : () => Navigator.pop(dialogContext),
                        child: const Text('Batal'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.danger),
                        onPressed: loading
                            ? null
                            : () async {
                                final validasi = ctrl.validasi();
                                if (validasi != null) {
                                  setDialogState(() => errorMsg = validasi);
                                  return;
                                }
                                setDialogState(() {
                                  loading = true;
                                  errorMsg = null;
                                });
                                try {
                                  final hasil = ctrl.hasil;
                                  final service = await ref.read(
                                      pembagianLabaServiceProvider.future);
                                  await service.tutupBukuDanBagiLaba(
                                    periodeId,
                                    metodePembayaran: hasil.metode,
                                    cashDibayar: hasil.cash,
                                    transferDibayar: hasil.transfer,
                                    jenisTransfer:
                                        ctrl.jenisTransferTerpilih,
                                  );
                                  refreshSemuaData(ref);
                                  ref.invalidate(
                                      previewPembagianLabaProvider(periodeId));
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                  if (context.mounted) Navigator.pop(context);
                                } catch (e) {
                                  setDialogState(() {
                                    loading = false;
                                    errorMsg = '$e';
                                  });
                                }
                              },
                        child: loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Ya, Tutup Buku & Bayar'),
                      ),
                    ],
                  );
              },
            );
          });
        },
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

/// V5.8 — kartu detail net settlement per partner.
class _NetSettlementCard extends StatelessWidget {
  final PartnerNetSettlement settlement;
  const _NetSettlementCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    final netPositif = s.netPayment >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.nama, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          _row('Hak Laba', s.hakLaba),
          if (s.hadiahPenjualan > 0)
            _row('+ Hadiah Penjualan', s.hadiahPenjualan, color: AppTheme.success),
          if (s.danaTalangHakPartner > 0)
            _row('+ Dana Talang (hak partner)', s.danaTalangHakPartner, color: AppTheme.success),
          if (s.kasbonPartner > 0)
            _row('- Kasbon (belum lunas)', -s.kasbonPartner, color: AppTheme.danger),
          if (s.piutangPartner > 0)
            _row('- Piutang Partner (kita talangi dia)', -s.piutangPartner, color: AppTheme.danger),
          if (s.sudahDiambilGajihan > 0)
            _row('- Sudah Diambil (Gajihan)', -s.sudahDiambilGajihan, color: AppTheme.danger),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Net Settlement', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(
                AppFormatter.rupiah(s.netSettlement),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: netPositif ? AppTheme.success : AppTheme.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, double value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text(
            '${value < 0 ? "- " : ""}${AppFormatter.rupiah(value.abs())}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
