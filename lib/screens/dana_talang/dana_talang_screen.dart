import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatter.dart';
import '../../models/dana_talang_model.dart';
import '../../repositories/dana_talang_repository.dart';
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

class _DanaTalangScreenState extends ConsumerState<DanaTalangScreen>
    with SingleTickerProviderStateMixin {
  String? _filterJenis;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
    final cicilController = TextEditingController();
    DateTime tanggal = DateTime.now();
    final formKey = GlobalKey<FormState>();
    // V5.5 — pilihan Cicil/Lunas. Sebelumnya field Cash/Transfer (bukan
    // Campuran) SELALU memakai `total` (=sisa) penuh -- tidak ada jalan
    // untuk bayar sebagian kecuali lewat Campuran dengan jumlah yang
    // harus pas sama dengan sisa juga. Toggle ini mengubah
    // `metodeController.total` jadi nominal cicilan, supaya Cash/
    // Transfer/Campuran otomatis mengacu ke nominal cicilan itu — bukan
    // fitur baru terpisah, cuma buka celah nominal yang sebelumnya terkunci.
    bool isLunas = true;

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
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Cicil')),
                        ButtonSegment(value: true, label: Text('Lunas')),
                      ],
                      selected: {isLunas},
                      onSelectionChanged: (s) {
                        setSheetState(() {
                          isLunas = s.first;
                          if (isLunas) {
                            metodeController.updateTotal(talang.sisa);
                          } else {
                            cicilController.clear();
                            metodeController.updateTotal(0);
                          }
                        });
                      },
                    ),
                    if (!isLunas) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: cicilController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [RupiahInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Nominal Dicicil',
                          prefixText: 'Rp ',
                        ),
                        onChanged: (v) {
                          final n = double.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                          setSheetState(() {
                            metodeController.updateTotal(n.clamp(0, talang.sisa));
                          });
                        },
                      ),
                    ],
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
                        onPressed: () {
                          if (!isLunas && metodeController.total <= 0) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('Isi nominal cicilan dulu')),
                            );
                            return;
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

  /// V5.9.3 — konversi SATU baris dana talang `SAYA_MENERIMA` (bukan
  /// agregat per partner seperti di tab Hubungan Partner) langsung dari
  /// tab Daftar. Cash/Bank TIDAK PERNAH disentuh. Mendukung konversi
  /// SEBAGIAN (nominal default = sisa penuh, bisa diturunkan).
  Future<void> _jadikanModalSatuan(DanaTalangModel talang) async {
    final result = await showNominalInputDialog(
      context,
      title: 'Jadikan Tambahan Modal',
      confirmLabel: 'Konversi',
      initialNominal: talang.sisa,
      keteranganLabel: 'Keterangan (opsional)',
      helperText:
          'Dana talang ${talang.namaPartner} (sisa Rp${talang.sisa.toStringAsFixed(0)}) '
          'akan dipindah jadi Tambahan Modal. Cash/Bank TIDAK berubah — ini '
          'BUKAN pembayaran.',
    );
    if (result == null) return;
    if (!mounted) return;

    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Konfirmasi Konversi Modal',
      message:
          'Dana Talang ${talang.namaPartner} -${AppFormatter.rupiah(result.nominal)}\n'
          'Tambahan Modal +${AppFormatter.rupiah(result.nominal)}\n\n'
          'Cash tidak berubah. Bank tidak berubah. Lanjutkan?',
      confirmLabel: 'Ya, Konversi',
      confirmColor: AppTheme.primary,
    );
    if (!konfirmasi) return;
    if (!mounted) return;

    final repo = await ref.read(danaTalangRepositoryProvider.future);
    try {
      await repo.konversiKeModal(
        danaTalangId: talang.id!,
        nominal: result.nominal,
        keterangan: result.keterangan,
      );
      refreshSemuaData(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// V5.5 — edit lengkap (nama, nominal, metode, keterangan), form yang
  /// sama seperti input awal. HANYA bisa dipakai selama belum ada
  /// pembayaran kembali sama sekali (dijaga juga di repository) — kalau
  /// sudah ada cicilan, nominal tidak bisa diubah begitu saja karena
  /// riwayat pembayaran & saldo sudah bergantung pada nilai lama.
  /// `jenis` (Menalangi/Menerima) & bentuk talangan TIDAK ikut bisa diubah
  /// di sini — itu mengubah arah aliran kas sepenuhnya, di luar cakupan
  /// "edit", lebih aman dihapus lalu dibuat ulang kalau memang salah jenis.
  Future<void> _editLengkap(DanaTalangModel talang) async {
    final namaController = TextEditingController(text: talang.namaPartner);
    final nominalController =
        TextEditingController(text: talang.nominal.toStringAsFixed(0));
    final keteranganController = TextEditingController(text: talang.keterangan ?? '');
    DateTime tanggal = talang.tanggal;
    final formKey = GlobalKey<FormState>();
    final metodeController = MetodePembayaranController(
      total: talang.nominal,
      tampilkanJenisTransfer: talang.isMenalangi,
    );
    metodeController.setMetode(talang.metodePembayaran);
    if (talang.metodePembayaran == AppConstants.metodeCampuran) {
      metodeController.cashController.text = talang.cashTerpakai.toStringAsFixed(0);
      metodeController.transferController.text = talang.transferTerpakai.toStringAsFixed(0);
    }
    String jenisTransfer = talang.jenisTransfer ?? AppConstants.jenisTransferGratis;
    final isNonTunai = talang.isNonTunai;

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
                      Text(
                        'Edit Dana Talang — ${talang.isMenalangi ? "Saya Menalangi" : "Saya Menerima"}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      TanggalEditField(
                        tanggal: tanggal,
                        onChanged: (v) => setSheetState(() => tanggal = v),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: namaController,
                        decoration: const InputDecoration(labelText: 'Nama Partner'),
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
                      if (!isNonTunai) MetodePembayaranField(controller: metodeController),
                      if (isNonTunai)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Non-Tunai: tidak memotong/menambah Cash atau Saldo Bank.',
                            style: TextStyle(fontSize: 11, color: Colors.black45),
                          ),
                        ),
                      if (talang.isMenalangi &&
                          !isNonTunai &&
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
                        decoration:
                            const InputDecoration(labelText: 'Keterangan (opsional)'),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (!formKey.currentState!.validate()) return;
                            if (!isNonTunai) {
                              final err = metodeController.validasi();
                              if (err != null) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text(err)));
                                return;
                              }
                            }
                            Navigator.pop(sheetContext, true);
                          },
                          child: const Text('Simpan Perubahan'),
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
      await repo.editDanaTalang(
        id: talang.id!,
        namaPartner: namaController.text.trim(),
        tanggal: tanggal,
        nominalBaru: hasil.cash + hasil.transfer,
        metodePembayaranBaru: hasil.metode,
        cashDibayarBaru: hasil.cash,
        transferDibayarBaru: hasil.transfer,
        jenisTransferBaru: talang.isMenalangi && hasil.metode != AppConstants.metodeCash
            ? jenisTransfer
            : null,
        keterangan: keteranganController.text.trim().isEmpty
            ? null
            : keteranganController.text.trim(),
      );
      refreshSemuaData(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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

  @override
  Widget build(BuildContext context) {
    final daftarAsync = ref.watch(daftarDanaTalangProvider(_filterJenis));
    final piutangAsync = ref.watch(totalPiutangPartnerProvider);
    final hutangAsync = ref.watch(totalHutangPartnerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dana Talang Partner'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Daftar'),
            Tab(text: 'Hubungan Partner'),
          ],
        ),
      ),
      floatingActionButton: ref.watch(isOwnerAdminProvider)
          ? FloatingActionButton.extended(
        onPressed: _tambahDanaTalang,
        icon: const Icon(Icons.add),
        label: const Text('Catat Dana Talang'),
      )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
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
                              if (talang.totalDikonversiModal > 0)
                                Text(
                                  'Sudah dikonversi modal: ${AppFormatter.rupiah(talang.totalDikonversiModal)} • Sisa: ${AppFormatter.rupiah(talang.sisa)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.primary),
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
                                    if (!talang.isMenalangi)
                                      TextButton(
                                        onPressed: () =>
                                            _jadikanModalSatuan(talang),
                                        child: const Text('Jadikan Modal'),
                                      ),
                                    const Spacer(),
                                    if (talang.totalDibayarKembali == 0 &&
                                        talang.totalDikonversiModal == 0)
                                      IconButton(
                                        onPressed: () => _editLengkap(talang),
                                        icon: const Icon(Icons.edit_outlined,
                                            color: AppTheme.primary, size: 20),
                                        tooltip: 'Edit Lengkap',
                                      ),
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
                                    if (talang.totalDibayarKembali == 0 &&
                                        talang.totalDikonversiModal == 0)
                                      IconButton(
                                        onPressed: () => _editLengkap(talang),
                                        icon: const Icon(Icons.edit_outlined,
                                            color: AppTheme.primary, size: 20),
                                        tooltip: 'Edit Lengkap',
                                      ),
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
          const _HubunganPartnerTab(),
        ],
      ),
    );
  }
}

/// V5.5 — Tab "Hubungan Partner": rekap talangan per nama partner (mis.
/// "Perusahaan menalangi Abah" / "Abah menalangi perusahaan") dikelompokkan
/// dari data dana_talang yang sudah ada — total masing-masing pihak,
/// selisih kewajiban, riwayat, dan tombol "Bayar Semua Selisih".
class _HubunganPartnerTab extends ConsumerWidget {
  const _HubunganPartnerTab();

  /// V5.9.3 — dipecah jadi aksi eksplisit (sebelumnya 1 tombol "Bayar
  /// Semua Selisih" otomatis melunasi KEDUA arah sekaligus penuh pakai
  /// cash, tidak ada pilihan cicil maupun konversi modal).
  ///
  /// Bottom sheet nominal+metode+tanggal, mirip `_bayarKembali` di tab
  /// Daftar tapi menyasar SEMUA transaksi aktif satu arah (jenis) milik
  /// partner ini sekaligus (FIFO lewat `bayarSemuaAktif`). Default
  /// nominal = sisa maksimum (artinya "Lunas" kalau user tidak ubah;
  /// user bisa turunkan nominalnya untuk "Cicil").
  Future<void> _settlementMassal(
    BuildContext context,
    WidgetRef ref,
    HubunganPartnerSummary h, {
    required String jenis,
    required String title,
    required double sisaMaks,
  }) async {
    final metodeController = MetodePembayaranController(
      total: sisaMaks,
      tampilkanJenisTransfer: jenis == AppConstants.danaTalangSayaMenerima,
    );
    final keteranganController = TextEditingController();
    final cicilController = TextEditingController();
    DateTime tanggal = DateTime.now();
    bool isLunas = true;

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$title — ${h.namaPartner}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Total sisa: ${AppFormatter.rupiah(sisaMaks)}'),
                  const SizedBox(height: 4),
                  const Text(
                    'Dialokasikan otomatis ke transaksi TERTUA dulu kalau '
                    'ada lebih dari satu transaksi aktif.',
                    style: TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Cicil')),
                      ButtonSegment(value: true, label: Text('Lunas Semua')),
                    ],
                    selected: {isLunas},
                    onSelectionChanged: (s) {
                      setSheetState(() {
                        isLunas = s.first;
                        if (isLunas) {
                          metodeController.updateTotal(sisaMaks);
                        } else {
                          cicilController.clear();
                          metodeController.updateTotal(0);
                        }
                      });
                    },
                  ),
                  if (!isLunas) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: cicilController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Nominal Dicicil',
                        prefixText: 'Rp ',
                      ),
                      onChanged: (v) {
                        final n = double.tryParse(
                                v.replaceAll(RegExp(r'[^0-9]'), '')) ??
                            0;
                        setSheetState(() {
                          metodeController.updateTotal(n.clamp(0, sisaMaks));
                        });
                      },
                    ),
                  ],
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
                    decoration:
                        const InputDecoration(labelText: 'Keterangan (opsional)'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (!isLunas && metodeController.total <= 0) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('Isi nominal cicilan dulu')),
                          );
                          return;
                        }
                        Navigator.pop(sheetContext, true);
                      },
                      child: const Text('Simpan'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != true) return;
    final hasil = metodeController.hasil;
    if (!context.mounted) return;

    final repo = await ref.read(danaTalangRepositoryProvider.future);
    try {
      await repo.bayarSemuaAktif(
        namaPartner: h.namaPartner,
        jenis: jenis,
        nominal: hasil.cash + hasil.transfer,
        metodePembayaran: hasil.metode,
        jenisTransfer: jenis == AppConstants.danaTalangSayaMenerima
            ? metodeController.jenisTransferTerpilih
            : null,
        tanggal: tanggal,
        keterangan: keteranganController.text.trim().isEmpty
            ? null
            : keteranganController.text.trim(),
      );
      refreshSemuaData(ref);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settlement berhasil dicatat.')),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// V5.9.3 — "Jadikan Tambahan Modal": khusus hutang KITA ke partner
  /// (SAYA_MENERIMA). Cash/Bank TIDAK PERNAH disentuh di jalur ini —
  /// tidak ada field metode pembayaran sama sekali, cuma nominal (boleh
  /// sebagian) + tanggal + keterangan. Lihat
  /// `DanaTalangRepository.konversiSemuaAktifKeModal`.
  Future<void> _jadikanModal(
      BuildContext context, WidgetRef ref, HubunganPartnerSummary h) async {
    final result = await showNominalInputDialog(
      context,
      title: 'Jadikan Tambahan Modal — ${h.namaPartner}',
      confirmLabel: 'Konversi',
      initialNominal: h.totalHutang,
      keteranganLabel: 'Keterangan (opsional)',
      helperText:
          'Hutang ke ${h.namaPartner} (maks Rp${h.totalHutang.toStringAsFixed(0)}) '
          'akan dipindah jadi Tambahan Modal. Cash/Bank TIDAK berubah sama '
          'sekali — ini BUKAN pembayaran.',
    );
    if (result == null) return;
    if (!context.mounted) return;

    final konfirmasi = await showConfirmDialog(
      context,
      title: 'Konfirmasi Konversi Modal',
      message:
          'Dana Talang ${h.namaPartner} -${AppFormatter.rupiah(result.nominal)}\n'
          'Tambahan Modal +${AppFormatter.rupiah(result.nominal)}\n\n'
          'Cash tidak berubah. Bank tidak berubah. Hutang partner berkurang, '
          'Modal bertambah. Lanjutkan?',
      confirmLabel: 'Ya, Konversi',
      confirmColor: AppTheme.primary,
    );
    if (!konfirmasi) return;
    if (!context.mounted) return;

    final repo = await ref.read(danaTalangRepositoryProvider.future);
    try {
      await repo.konversiSemuaAktifKeModal(
        namaPartner: h.namaPartner,
        nominal: result.nominal,
        keterangan: result.keterangan,
      );
      refreshSemuaData(ref);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konversi ke modal berhasil dicatat.')),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(hubunganPartnerProvider);
    final isOwner = ref.watch(isOwnerAdminProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(hubunganPartnerProvider),
      child: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Belum ada data dana talang partner.',
                      textAlign: TextAlign.center),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final h = list[index];
              final selisihPositif = h.selisih >= 0;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.namaPartner,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _RingkasanCard(
                            label: 'Kita Menalangi Dia',
                            value: h.totalPiutang,
                            color: AppTheme.success,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RingkasanCard(
                            label: 'Dia Menalangi Kita',
                            value: h.totalHutang,
                            color: AppTheme.danger,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (selisihPositif ? AppTheme.success : AppTheme.danger)
                            .withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            selisihPositif
                                ? '${h.namaPartner} berhutang bersih ke kita'
                                : 'Kita berhutang bersih ke ${h.namaPartner}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            AppFormatter.rupiah(h.selisih.abs()),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: selisihPositif ? AppTheme.success : AppTheme.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Detail Riwayat', style: TextStyle(fontSize: 13)),
                      children: [
                        for (final t in h.riwayat)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${AppFormatter.tanggal(t.tanggal)} • '
                                        '${t.isMenalangi ? "Menalangi" : "Menerima"} • '
                                        '${_statusLabel(t.status)}',
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.black54),
                                      ),
                                      if (t.keterangan?.isNotEmpty == true)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            t.keterangan!,
                                            style: const TextStyle(
                                                fontSize: 11, color: Colors.black38),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppFormatter.rupiah(t.sisa),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (isOwner && (h.totalPiutang > 0 || h.totalHutang > 0)) ...[
                      const SizedBox(height: 4),
                      if (h.totalPiutang > 0)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _settlementMassal(
                              context,
                              ref,
                              h,
                              jenis: AppConstants.danaTalangSayaMenalangi,
                              title: 'Terima Pembayaran Hutang',
                              sisaMaks: h.totalPiutang,
                            ),
                            icon: const Icon(Icons.call_received),
                            label: Text(
                                'Terima Pembayaran (${h.namaPartner} bayar kita)'),
                          ),
                        ),
                      if (h.totalHutang > 0) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _settlementMassal(
                              context,
                              ref,
                              h,
                              jenis: AppConstants.danaTalangSayaMenerima,
                              title: 'Bayar Hutang',
                              sisaMaks: h.totalHutang,
                            ),
                            icon: const Icon(Icons.call_made),
                            label: Text(
                                'Bayar Hutang (kita bayar ${h.namaPartner})'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _jadikanModal(context, ref, h),
                            icon: const Icon(Icons.savings_outlined),
                            label: const Text('Jadikan Tambahan Modal'),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              );
            },
          );
        },
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

/// V5.5 — dipisah dari _DanaTalangScreenState jadi top-level function
/// supaya bisa dipakai juga di _HubunganPartnerTab (class terpisah),
/// tanpa mengubah cara pemanggilan yang sudah ada (nama sama persis).
Color _statusColor(String status) {
  switch (status) {
    case AppConstants.statusDanaTalangLunas:
      return AppTheme.success;
    case AppConstants.statusDanaTalangDikonversiModal:
      return AppTheme.primary;
    case AppConstants.statusDanaTalangSebagianLunas:
    case AppConstants.statusDanaTalangSebagianDikonversi:
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
    case AppConstants.statusDanaTalangDikonversiModal:
      return 'Dikonversi Modal';
    case AppConstants.statusDanaTalangSebagianLunas:
      return 'Sebagian Lunas';
    case AppConstants.statusDanaTalangSebagianDikonversi:
      return 'Sebagian Dikonversi';
    case AppConstants.statusDanaTalangBatal:
      return 'Batal';
    case AppConstants.statusDanaTalangBelumLunas:
    default:
      return 'Belum Lunas';
  }
}
