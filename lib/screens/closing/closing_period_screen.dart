import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../models/closing_snapshot_model.dart';
import '../../providers/app_providers.dart';
import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';

/// V5.9 — CLOSING PERIOD (Reconciliation + Snapshot + Report).
///
/// PERIOD LOCKING TIDAK DIIMPLEMENTASIKAN DI SINI. "Tutup Buku" di layar
/// ini HANYA menghitung & menyimpan snapshot kondisi keuangan — semua
/// transaksi (motor, penjualan, kasbon, dana talang, dst) TETAP 100%
/// bisa ditambah/edit/hapus kapan saja, sebelum maupun sesudah closing.
/// Kalau ada perubahan setelah closing terakhir, layar ini menampilkan
/// peringatan + tombol "Rekalkulasi Closing" (BUKAN "Unlock", karena
/// memang tidak pernah ada yang dikunci).
class ClosingPeriodScreen extends ConsumerWidget {
  final int periodeId;
  const ClosingPeriodScreen({super.key, required this.periodeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(closingChangeStatusProvider(periodeId));
    final riwayatAsync = ref.watch(riwayatClosingProvider(periodeId));
    final balanceAsync = ref.watch(financialBalanceReportProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Closing Period')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(closingChangeStatusProvider(periodeId));
          ref.invalidate(riwayatClosingProvider(periodeId));
          ref.invalidate(financialBalanceReportProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionTitle(title: 'Status Neraca (Saat Ini)'),
            balanceAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) => Text('Error: $e'),
              data: (report) => _BalanceStatusCard(report: report),
            ),
            const SizedBox(height: 20),
            const SectionTitle(title: 'Closing Terakhir'),
            statusAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) => Text('Error: $e'),
              data: (status) => _ClosingStatusCard(
                status: status,
                onJalankanClosing: () => _jalankanClosing(context, ref),
              ),
            ),
            const SizedBox(height: 20),
            const SectionTitle(title: 'Riwayat Closing'),
            riwayatAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) => Text('Error: $e'),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Belum pernah closing untuk periode ini.',
                        style: TextStyle(color: Colors.black45, fontSize: 12)),
                  );
                }
                return Column(
                  children: list.map((s) => _RiwayatClosingTile(snapshot: s)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _jalankanClosing(BuildContext context, WidgetRef ref) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Jalankan Closing?',
      message:
          'Ini akan menghitung ulang kondisi keuangan saat ini dan menyimpannya '
          'sebagai snapshot baru. Transaksi TIDAK akan dikunci — Anda tetap bisa '
          'menambah/mengedit transaksi kapan saja setelah ini.',
      confirmLabel: 'Ya, Jalankan',
      confirmColor: AppTheme.primary,
    );
    if (!konfirmasi) return;

    try {
      final service = await ref.read(closingSnapshotServiceProvider.future);
      final username = AuthService.instance.currentUser?.username;
      await service.jalankanClosing(periodeId, createdBy: username);
      ref.invalidate(closingChangeStatusProvider(periodeId));
      ref.invalidate(riwayatClosingProvider(periodeId));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Closing berhasil disimpan.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal closing: $e')));
      }
    }
  }
}

class _BalanceStatusCard extends StatelessWidget {
  final dynamic report; // FinancialBalanceReport
  const _BalanceStatusCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final balance = report.isBalance as bool;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (balance ? AppTheme.success : AppTheme.danger).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(balance ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: balance ? AppTheme.success : AppTheme.danger),
              const SizedBox(width: 8),
              Text(
                balance ? 'BALANCE' : 'TIDAK BALANCE',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: balance ? AppTheme.success : AppTheme.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _row('Total Aset', report.totalAset),
          _row('Total Kewajiban', report.totalKewajiban),
          _row('Modal', report.modal),
          _row('Laba (akumulasi + berjalan)', report.totalLaba),
          const Divider(height: 20),
          _row('Expected (Kewajiban+Modal+Laba)', report.expected),
          _row('Selisih', report.selisih,
              color: balance ? null : AppTheme.danger, bold: true),
          if (!balance) ...[
            const SizedBox(height: 8),
            const Text(
              'Selisih bisa berasal dari laba yang sudah dibagikan/dibayar '
              'tunai ke partner tapi belum dicatat sebagai Pengeluaran atau '
              'pengurangan Modal di aplikasi. Cek riwayat transaksi terkait.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, double value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          Text(
            AppFormatter.rupiah(value),
            style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color),
          ),
        ],
      ),
    );
  }
}

class _ClosingStatusCard extends StatelessWidget {
  final dynamic status; // ClosingChangeStatus
  final VoidCallback onJalankanClosing;
  const _ClosingStatusCard({required this.status, required this.onJalankanClosing});

  @override
  Widget build(BuildContext context) {
    final pernahClosing = status.pernahClosing as bool;
    final berubah = status.berubah as bool;
    final terakhir = status.closingTerakhir as ClosingSnapshotModel?;

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
          if (!pernahClosing)
            const Text('Belum pernah closing untuk periode ini.',
                style: TextStyle(fontSize: 13))
          else ...[
            Text('Closing #${terakhir!.closingNumber} — ${AppFormatter.tanggal(terakhir.createdAt)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Total Laba saat itu: ${AppFormatter.rupiah(terakhir.totalLaba)}'),
            Text('Status: ${terakhir.closingStatus}'),
          ],
          if (berubah) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                      SizedBox(width: 6),
                      Text('PERIODE BERUBAH SETELAH CLOSING',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ada transaksi yang berubah sejak closing terakhir.\n'
                    'Closing terakhir: ${AppFormatter.rupiah(terakhir!.totalLaba)}\n'
                    'Perhitungan terbaru: ${AppFormatter.rupiah((status.nilaiTerbaru as ClosingSnapshotModel).totalLaba)}\n'
                    'Perubahan: ${AppFormatter.rupiah((status.selisihLaba as double).abs())}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onJalankanClosing,
              icon: Icon(berubah ? Icons.refresh : Icons.task_alt),
              label: Text(berubah
                  ? 'REKALKULASI CLOSING'
                  : (pernahClosing ? 'Jalankan Closing Baru' : 'Tutup Buku / Finalisasi Periode')),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiwayatClosingTile extends StatelessWidget {
  final ClosingSnapshotModel snapshot;
  const _RiwayatClosingTile({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final balance = snapshot.isBalance;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Closing #${snapshot.closingNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(AppFormatter.tanggalWaktu(snapshot.createdAt),
                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(AppFormatter.rupiah(snapshot.totalLaba),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(
                balance ? 'BALANCE' : 'TIDAK BALANCE',
                style: TextStyle(
                    fontSize: 11, color: balance ? AppTheme.success : AppTheme.danger),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
