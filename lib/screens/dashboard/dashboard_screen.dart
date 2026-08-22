import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/hidden_debug_trigger.dart';
import '../../widgets/hidden_server_fallback_dialog.dart';
import '../pembukuan/buat_periode_screen.dart';
import '../modal/modal_screen.dart';
import '../cash/cash_screen.dart';
import '../saldo_bank/saldo_bank_screen.dart';
import '../dana_talang/dana_talang_screen.dart';
import '../motor/motor_list_screen.dart';
import '../penjualan/penjualan_screen.dart';
import '../kasbon/kasbon_screen.dart';
import '../biaya_transfer/biaya_transfer_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final periodeAktifAsync = ref.watch(periodeAktifProvider);

    return Scaffold(
      appBar: AppBar(
        title: HiddenDebugTrigger(
          onTriggered: () => showHiddenServerFallback(context, ref),
          child: const Text('Garasi Abah Bontot'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(dashboardSummaryProvider);
              ref.invalidate(periodeAktifProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardSummaryProvider);
          ref.invalidate(periodeAktifProvider);
        },
        child: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Gagal memuat data: $e')),
          data: (summary) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                periodeAktifAsync.when(
                  data: (periode) => _PeriodeBanner(
                    namaPeriode: periode?.namaPeriode,
                    onBuatPeriode: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BuatPeriodeScreen(),
                        ),
                      ).then((_) => refreshSemuaData(ref));
                    },
                  ),
                  loading: () => const SizedBox(
                    height: 60,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, st) => Text('Error: $e'),
                ),
                const SizedBox(height: 16),
                const SectionTitle(title: 'Ringkasan Keuangan'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    SummaryCard(
                      label: 'Modal',
                      value: summary.modal,
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppTheme.primary,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ModalScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                    ),
                    SummaryCard(
                      label: 'Cash',
                      value: summary.cash,
                      icon: Icons.payments_outlined,
                      color: AppTheme.success,
                      isHighlight: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CashScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                    ),
                    SummaryCard(
                      label: 'Saldo Bank',
                      value: summary.saldoBank,
                      icon: Icons.account_balance_outlined,
                      color: AppTheme.primaryLight,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SaldoBankScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                    ),
                    SummaryCard(
                      label: 'Nilai Stok Motor',
                      value: summary.nilaiStokMotor,
                      icon: Icons.motorcycle_outlined,
                      color: AppTheme.accent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MotorListScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                    ),
                    SummaryCard(
                      label: 'Piutang Kasbon',
                      value: summary.piutangKasbon,
                      icon: Icons.receipt_long_outlined,
                      color: AppTheme.danger,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const KasbonScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                    ),
                    SummaryCard(
                      label: 'Piutang Penjualan (DP)',
                      value: summary.piutangPenjualan,
                      icon: Icons.hourglass_bottom_outlined,
                      color: AppTheme.danger,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PenjualanScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                    ),
                    SummaryCard(
                      label: 'Piutang Partner',
                      value: summary.piutangPartner,
                      icon: Icons.call_received,
                      color: AppTheme.success,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DanaTalangScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                    ),
                    SummaryCard(
                      label: 'Hutang Partner',
                      value: summary.hutangPartner,
                      icon: Icons.call_made,
                      color: AppTheme.danger,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DanaTalangScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                    ),
                    SummaryCard(
                      label: 'Total Aset',
                      value: summary.totalAset,
                      icon: Icons.pie_chart_outline,
                      color: AppTheme.primary,
                      isHighlight: true,
                    ),
                    SummaryCard(
                      label: 'Biaya Transfer (Periode)',
                      value: summary.totalBiayaTransferPeriode,
                      icon: Icons.compare_arrows,
                      color: AppTheme.danger,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BiayaTransferScreen()),
                        ).then((_) => refreshSemuaData(ref));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const SectionTitle(title: 'Periode Berjalan'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: Column(
                    children: [
                      _StatRow(
                        label: 'Unit Tersedia',
                        value: '${summary.jumlahUnitTersedia} unit',
                      ),
                      const Divider(height: 20),
                      _StatRow(
                        label: 'Unit Terjual (periode ini)',
                        value: '${summary.jumlahUnitTerjualPeriodeAktif} unit',
                      ),
                      const Divider(height: 20),
                      _StatRow(
                        label: 'Total Penjualan',
                        value: AppFormatter.rupiah(
                            summary.totalPenjualanPeriodeAktif),
                      ),
                      const Divider(height: 20),
                      _StatRow(
                        label: 'Laba Berjalan',
                        value:
                            AppFormatter.rupiah(summary.totalLabaPeriodeAktif),
                        valueColor: AppTheme.success,
                        bold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PeriodeBanner extends StatelessWidget {
  final String? namaPeriode;
  final VoidCallback onBuatPeriode;

  const _PeriodeBanner({required this.namaPeriode, required this.onBuatPeriode});

  @override
  Widget build(BuildContext context) {
    if (namaPeriode == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.danger.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Belum ada periode pembukuan aktif',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: onBuatPeriode, child: const Text('Buat')),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.menu_book, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Periode Aktif',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  namaPeriode!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const _StatRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
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
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
