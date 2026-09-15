import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../penjualan/penjualan_screen.dart';
import '../pemasukan/pemasukan_screen.dart';
import '../pengeluaran/pengeluaran_screen.dart';

/// V5.5 — Halaman rangkuman pembukuan lengkap, dibuka lewat tap kartu
/// "Total Aset" di Dashboard. Versi in-app dari laporan PDF/Excel:
/// komposisi aset, laba/rugi, dan perjalanan transaksi (pemasukan,
/// pengeluaran, transaksi motor, perubahan saldo) — semua dari data yang
/// SUDAH ADA (DashboardSummary, LaporanPeriodeData, cash_flow), tidak ada
/// perhitungan baru/berbeda dari yang sudah dipakai di layar lain.
class TotalAsetDetailScreen extends ConsumerWidget {
  const TotalAsetDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final periodeAktifAsync = ref.watch(periodeAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rangkuman Total Aset')),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Gagal memuat data: $e')),
        data: (summary) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Aset Saat Ini',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      AppFormatter.rupiah(summary.totalAset),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const SectionTitle(title: 'Komposisi Aset'),
              _RingkasanCard(rows: [
                _Row('Cash', summary.cash),
                _Row('Saldo Bank', summary.saldoBank),
                _Row('Nilai Stok Motor', summary.nilaiStokMotor),
                _Row('Piutang Kasbon', summary.piutangKasbon),
                _Row('Piutang Penjualan (DP)', summary.piutangPenjualan),
                _Row('Piutang Partner', summary.piutangPartner),
                _Row('Total Aset', summary.totalAset, bold: true, divider: true),
              ]),
              const SizedBox(height: 8),
              _RingkasanCard(rows: [
                _Row('Hutang Partner (kewajiban, tidak mengurangi Total Aset)',
                    summary.hutangPartner, color: AppTheme.danger),
              ]),

              const SizedBox(height: 20),
              const SectionTitle(title: 'Laba / Rugi'),
              periodeAktifAsync.when(
                data: (periode) {
                  if (periode?.id == null) {
                    return const _InfoBox(
                        text: 'Belum ada periode pembukuan aktif — buat periode dulu untuk melihat laba/rugi berjalan.');
                  }
                  final laporanAsync = ref.watch(laporanPeriodeProvider(periode!.id!));
                  return laporanAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, st) => Text('Error: $e'),
                    data: (lap) => _RingkasanCard(rows: [
                      _Row('Total Penjualan (periode ini)', lap.totalPenjualan),
                      _Row('Total Pemasukan Lain', lap.totalPemasukan),
                      _Row('Total Pengeluaran', lap.totalPengeluaran, color: AppTheme.danger),
                      _Row('Laba dari Transaksi Motor', lap.totalLabaMotor,
                          bold: true,
                          color: lap.totalLabaMotor >= 0 ? AppTheme.success : AppTheme.danger,
                          divider: true),
                      _Row('Selisih Aset vs Modal Awal (diagnostik, BUKAN laba)', lap.labaPerubahanModal,
                          bold: true,
                          color: lap.labaPerubahanModal >= 0 ? AppTheme.success : AppTheme.danger),
                    ]),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, st) => Text('Error: $e'),
              ),

              const SizedBox(height: 20),
              _SectionHeaderWithAction(
                title: 'Transaksi Motor Terbaru',
                onLihatSemua: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PenjualanScreen())),
              ),
              Consumer(builder: (context, ref, __) {
                final asyncList = ref.watch(daftarPenjualanProvider(null));
                return asyncList.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, st) => Text('Error: $e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return const _InfoBox(text: 'Belum ada transaksi penjualan motor.');
                    }
                    final top = list.take(5).toList();
                    return _RingkasanCard(rows: [
                      for (final p in top)
                        _Row(
                          '${AppFormatter.tanggal(p.tanggalJual)} • ${p.penjual}',
                          p.laba,
                          color: p.laba >= 0 ? AppTheme.success : AppTheme.danger,
                          subtitle: 'Jual ${AppFormatter.rupiah(p.hargaJual)}'
                              '${p.biayaCalo > 0 ? " (calo -${AppFormatter.rupiah(p.biayaCalo)})" : ""}',
                        ),
                    ]);
                  },
                );
              }),

              const SizedBox(height: 20),
              _SectionHeaderWithAction(
                title: 'Pemasukan Terbaru',
                onLihatSemua: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PemasukanScreen())),
              ),
              Consumer(builder: (context, ref, __) {
                final asyncList = ref.watch(daftarPemasukanProvider(null));
                return asyncList.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, st) => Text('Error: $e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return const _InfoBox(text: 'Belum ada catatan pemasukan.');
                    }
                    final top = list.take(5).toList();
                    return _RingkasanCard(rows: [
                      for (final m in top)
                        _Row(
                          '${AppFormatter.tanggal(m.tanggal)} • ${m.kategori}',
                          m.nominal,
                          color: AppTheme.success,
                          subtitle: m.keterangan,
                        ),
                    ]);
                  },
                );
              }),

              const SizedBox(height: 20),
              _SectionHeaderWithAction(
                title: 'Pengeluaran Terbaru',
                onLihatSemua: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PengeluaranScreen())),
              ),
              Consumer(builder: (context, ref, __) {
                final asyncList = ref.watch(daftarPengeluaranProvider(null));
                return asyncList.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, st) => Text('Error: $e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return const _InfoBox(text: 'Belum ada catatan pengeluaran.');
                    }
                    final top = list.take(5).toList();
                    return _RingkasanCard(rows: [
                      for (final k in top)
                        _Row(
                          '${AppFormatter.tanggal(k.tanggal)} • ${k.kategori}',
                          -k.nominal,
                          color: AppTheme.danger,
                          subtitle: k.keterangan,
                        ),
                    ]);
                  },
                );
              }),

              const SizedBox(height: 20),
              const SectionTitle(title: 'Perubahan Saldo Terbaru'),
              Consumer(builder: (context, ref, __) {
                final asyncList = ref.watch(riwayatCashFlowProvider);
                return asyncList.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, st) => Text('Error: $e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return const _InfoBox(text: 'Belum ada riwayat perubahan saldo.');
                    }
                    final top = list.take(10).toList();
                    return _RingkasanCard(rows: [
                      for (final c in top)
                        _Row(
                          '${AppFormatter.tanggal(c.tanggal)} • ${c.sumber} • ${c.referensi}',
                          c.tipe == AppConstants.cashFlowMasuk ? c.nominal : -c.nominal,
                          color: c.tipe == AppConstants.cashFlowMasuk
                              ? AppTheme.success
                              : AppTheme.danger,
                          subtitle: c.keterangan,
                        ),
                    ]);
                  },
                );
              }),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _Row {
  final String label;
  final double value;
  final bool bold;
  final bool divider;
  final Color? color;
  final String? subtitle;
  _Row(this.label, this.value,
      {this.bold = false, this.divider = false, this.color, this.subtitle});
}

class _RingkasanCard extends StatelessWidget {
  final List<_Row> rows;
  const _RingkasanCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (rows[i].divider) const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rows[i].label,
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: rows[i].bold ? FontWeight.w700 : FontWeight.w400,
                            )),
                        if (rows[i].subtitle?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              rows[i].subtitle!,
                              style: const TextStyle(fontSize: 11, color: Colors.black38),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppFormatter.rupiah(rows[i].value),
                    style: TextStyle(
                      fontWeight: rows[i].bold ? FontWeight.w800 : FontWeight.w600,
                      color: rows[i].color ?? Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeaderWithAction extends StatelessWidget {
  final String title;
  final VoidCallback onLihatSemua;
  const _SectionHeaderWithAction({required this.title, required this.onLihatSemua});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SectionTitle(title: title),
        TextButton(onPressed: onLihatSemua, child: const Text('Lihat Semua')),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String text;
  const _InfoBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(color: Colors.black54, fontSize: 12)),
    );
  }
}
