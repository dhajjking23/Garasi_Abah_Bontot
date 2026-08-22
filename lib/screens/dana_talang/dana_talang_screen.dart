import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../models/dana_talang_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/metode_pembayaran_field.dart';
import '../../core/utils/rupiah_input_formatter.dart';
import '../../providers/auth_provider.dart';

class DanaTalangScreen extends ConsumerStatefulWidget {
  const DanaTalangScreen({super.key});

  @override
  ConsumerState<DanaTalangScreen> createState() => _DanaTalangScreenState();
}

class _DanaTalangScreenState extends ConsumerState<DanaTalangScreen> {
  String? _filterJenis;

  Future<void> _tambahDanaTalang() async {
    final namaController = TextEditingController();
    final nominalController = TextEditingController();
    final keteranganController = TextEditingController();
    String jenis = AppConstants.danaTalangSayaMenalangi;
    String bentukTalangan = AppConstants.bentukTalanganTunai;
    DateTime tanggal = DateTime.now();
    final formKey = GlobalKey<FormState>();
    final metodeController = MetodePembayaranController(total: 0);
    String jenisTransfer = AppConstants.jenisTransferGratis;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Catat Dana Talang',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      TanggalEditField(
                        tanggal: tanggal,
                        onChanged: (v) => setSheetState(() => tanggal = v),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: AppConstants.danaTalangSayaMenalangi,
                            label: Text('Saya Menalangi'),
                          ),
                          ButtonSegment(
                            value: AppConstants.danaTalangSayaMenerima,
                            label: Text('Saya Menerima'),
                          ),
                        ],
                        selected: {jenis},
                        onSelectionChanged: (s) =>
                            setSheetState(() => jenis = s.first),
                      ),
                      if (jenis == AppConstants.danaTalangSayaMenerima) ...[
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: AppConstants.bentukTalanganTunai,
                              label: Text('Tunai'),
                            ),
                            ButtonSegment(
                              value: AppConstants.bentukTalanganNonTunai,
                              label: Text('Non-Tunai'),
                            ),
                          ],
                          selected: {bentukTalangan},
                          onSelectionChanged: (s) =>
                              setSheetState(() => bentukTalangan = s.first),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bentukTalangan == AppConstants.bentukTalanganTunai
                              ? 'Partner benar-benar transfer/kasih cash ke saya — Cash/Saldo Bank saya bertambah.'
                              : 'Partner membayarkan sesuatu atas nama saya (mis. bayar motor duluan) — BUKAN uang masuk, Cash/Saldo Bank saya tidak berubah, hanya hutang yang tercatat.',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black45),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: namaController,
                        decoration:
                            const InputDecoration(labelText: 'Nama Partner'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nominalController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [RupiahInputFormatter()],
                        decoration: const InputDecoration(
                            labelText: 'Nominal', prefixText: 'Rp '),
                        validator: (v) {
                          final n = double.tryParse(
                              (v ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
                          if (n == null || n <= 0) return 'Nominal tidak valid';
                          return null;
                        },
                        onChanged: (v) {
                          final n = double.tryParse(
                                  v.replaceAll(RegExp(r'[^0-9]'), '')) ??
                              0;
                          metodeController.updateTotal(n);
                        },
                      ),
                      const SizedBox(height: 12),
                      if (!(jenis == AppConstants.danaTalangSayaMenerima &&
                          bentukTalangan == AppConstants.bentukTalanganNonTunai))
                        MetodePembayaranField(controller: metodeController),
                      // Biaya transfer HANYA relevan untuk SAYA_MENALANGI
                      // (uang keluar) — bukan saat menerima talangan.
                      if (jenis == AppConstants.danaTalangSayaMenalangi &&
                          metodeController.metode != AppConstants.metodeCash) ...[
                        const SizedBox(height: 12),
                        JenisTransferField(
                          value: jenisTransfer,
                          onChanged: (v) => setSheetState(
                              () => jenisTransfer = v ?? AppConstants.jenisTransferGratis),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: keteranganController,
                        decoration: const InputDecoration(
                            labelText: 'Keterangan (opsional)'),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (!formKey.currentState!.validate()) return;
                            final isNonTunai = jenis ==
                                    AppConstants.danaTalangSayaMenerima &&
                                bentukTalangan ==
                                    AppConstants.bentukTalanganNonTunai;
                            if (!isNonTunai) {
                              final err = metodeController.validasi();
                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err)));
                                return;
                              }
                            }
                            Navigator.pop(sheetContext, true);
                          },
                          child: const Text('Simpan'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (result != true) return;
    final hasil = metodeController.hasil;
    final repo = await ref.read(danaTalangRepositoryProvider.future);
    try {
      await repo.tambahDanaTalang(
        namaPartner: namaController.text.trim(),
        tanggal: tanggal,
        jenis: jenis,
        nominal: hasil.cash + hasil.transfer,
        metodePembayaran: hasil.metode,
        cashDibayar: hasil.cash,
        transferDibayar: hasil.transfer,
        jenisTransfer: jenis == AppConstants.danaTalangSayaMenalangi &&
                hasil.metode != AppConstants.metodeCash
            ? jenisTransfer
            : null,
        bentukTalangan: bentukTalangan,
        keterangan: keteranganController.text.trim().isEmpty
            ? null
            : keteranganController.text.trim(),
      );
      refreshSemuaData(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _bayarKembali(DanaTalangModel talang) async {
    final metodeController = MetodePembayaranController(
        total: talang.sisa,
        tampilkanJenisTransfer: !talang.isMenalangi);
    final keteranganController = TextEditingController();
    DateTime tanggal = DateTime.now();
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      talang.isMenalangi ? 'Terima Pembayaran Kembali' : 'Bayar Kembali',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('Sisa: ${AppFormatter.rupiah(talang.sisa)}'),
                    const SizedBox(height: 12),
                    TanggalEditField(
                      tanggal: tanggal,
                      onChanged: (t) => setSheetState(() => tanggal = t),
                    ),
                    const SizedBox(height: 12),
                    MetodePembayaranField(controller: metodeController),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keteranganController,
                      decoration: const InputDecoration(labelText: 'Keterangan (opsional)'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: const Text('Simpan'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != true) return;
    final hasil = metodeController.hasil;
    if (!mounted) return;

    final repo = await ref.read(danaTalangRepositoryProvider.future);
    try {
      await repo.bayarKembali(
        danaTalangId: talang.id!,
        tanggal: tanggal,
        nominal: hasil.cash + hasil.transfer,
        metodePembayaran: hasil.metode,
        cashDibayar: hasil.cash,
        transferDibayar: hasil.transfer,
        jenisTransfer: !talang.isMenalangi ? metodeController.jenisTransferTerpilih : null,
        keterangan: keteranganController.text.trim().isEmpty
            ? null
            : keteranganController.text.trim(),
      );
      refreshSemuaData(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _editTanggal(DanaTalangModel talang) async {
    final picked = await pickTanggal(context, talang.tanggal);
    if (picked == null) return;
    final repo = await ref.read(danaTalangRepositoryProvider.future);
    try {
      await repo.editTanggalDanaTalang(talang.id!, picked);
      refreshSemuaData(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _hapus(DanaTalangModel talang) async {
    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Hapus Dana Talang?',
      message:
          'Dana talang ${talang.namaPartner} (${AppFormatter.rupiah(talang.nominal)}) akan dihapus. '
          'Saldo Cash/Bank akan dikembalikan seperti sebelum transaksi ini. Lanjutkan?',
      confirmLabel: 'Ya, Hapus',
      confirmColor: AppTheme.danger,
    );
    if (!konfirmasi) return;
    final repo = await ref.read(danaTalangRepositoryProvider.future);
    try {
      await repo.hapusDanaTalang(talang.id!);
      refreshSemuaData(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case AppConstants.statusDanaTalangLunas:
        return AppTheme.success;
      case AppConstants.statusDanaTalangSebagianLunas:
        return AppTheme.accent;
      case AppConstants.statusDanaTalangBatal:
        return Colors.black45;
      case AppConstants.statusDanaTalangBelumLunas:
      default:
        return AppTheme.danger;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case AppConstants.statusDanaTalangLunas:
        return 'Lunas';
      case AppConstants.statusDanaTalangSebagianLunas:
        return 'Sebagian Lunas';
      case AppConstants.statusDanaTalangBatal:
        return 'Batal';
      case AppConstants.statusDanaTalangBelumLunas:
      default:
        return 'Belum Lunas';
    }
  }

  @override
  Widget build(BuildContext context) {
    final daftarAsync = ref.watch(daftarDanaTalangProvider(_filterJenis));
    final piutangAsync = ref.watch(totalPiutangPartnerProvider);
    final hutangAsync = ref.watch(totalHutangPartnerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dana Talang Partner')),
      floatingActionButton: ref.watch(isOwnerAdminProvider)
          ? FloatingActionButton.extended(
        onPressed: _tambahDanaTalang,
        icon: const Icon(Icons.add),
        label: const Text('Catat Dana Talang'),
      )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => refreshSemuaData(ref),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: _RingkasanCard(
                    label: 'Piutang Partner',
                    value: piutangAsync.value ?? 0,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RingkasanCard(
                    label: 'Hutang Partner',
                    value: hutangAsync.value ?? 0,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Semua'),
                    selected: _filterJenis == null,
                    onSelected: (_) => setState(() => _filterJenis = null),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Saya Menalangi'),
                    selected:
                        _filterJenis == AppConstants.danaTalangSayaMenalangi,
                    onSelected: (_) => setState(
                        () => _filterJenis = AppConstants.danaTalangSayaMenalangi),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Saya Menerima'),
                    selected:
                        _filterJenis == AppConstants.danaTalangSayaMenerima,
                    onSelected: (_) => setState(
                        () => _filterJenis = AppConstants.danaTalangSayaMenerima),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            daftarAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Text('Error: $e'),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(message: 'Belum ada dana talang');
                }
                return Column(
                  children: [
                    for (final talang in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    talang.isMenalangi
                                        ? Icons.call_made
                                        : Icons.call_received,
                                    size: 18,
                                    color: talang.isMenalangi
                                        ? AppTheme.success
                                        : AppTheme.danger,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(talang.namaPartner,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _statusColor(talang.status)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _statusLabel(talang.status),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _statusColor(talang.status),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                AppFormatter.tanggal(talang.tanggal),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black45),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${talang.isMenalangi ? "Ditalangi" : "Diterima"}: ${AppFormatter.rupiah(talang.nominal)}'
                                '${talang.isNonTunai ? " (Non-Tunai)" : ""}',
                              ),
                              if (talang.totalDibayarKembali > 0)
                                Text(
                                  'Sudah dibayar: ${AppFormatter.rupiah(talang.totalDibayarKembali)} • Sisa: ${AppFormatter.rupiah(talang.sisa)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                              if (talang.keterangan != null)
                                Text(talang.keterangan!,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.black45)),
                              const SizedBox(height: 8),
                              if (talang.isAktif)
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _bayarKembali(talang),
                                      child: const Text('Bayar Kembali'),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      onPressed: () => _editTanggal(talang),
                                      icon: const Icon(
                                          Icons.edit_calendar_outlined,
                                          color: AppTheme.primary,
                                          size: 20),
                                      tooltip: 'Ubah Tanggal',
                                    ),
                                    IconButton(
                                      onPressed: () => _hapus(talang),
                                      icon: const Icon(Icons.delete_outline,
                                          color: AppTheme.danger, size: 20),
                                      tooltip: 'Hapus',
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      onPressed: () => _editTanggal(talang),
                                      icon: const Icon(
                                          Icons.edit_calendar_outlined,
                                          color: AppTheme.primary,
                                          size: 20),
                                      tooltip: 'Ubah Tanggal',
                                    ),
                                    IconButton(
                                      onPressed: () => _hapus(talang),
                                      icon: const Icon(Icons.delete_outline,
                                          color: AppTheme.danger, size: 20),
                                      tooltip: 'Hapus',
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RingkasanCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _RingkasanCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(
            AppFormatter.rupiah(value),
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15, color: color),
          ),
        ],
      ),
    );
  }
}
