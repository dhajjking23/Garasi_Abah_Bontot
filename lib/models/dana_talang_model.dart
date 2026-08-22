import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

/// Dana Talang Partner. BUKAN pengeluaran/pemasukan biasa — ini adalah
/// piutang (SAYA_MENALANGI, kita beri uang ke partner) atau hutang
/// (SAYA_MENERIMA, partner beri uang ke kita).
class DanaTalangModel extends Equatable {
  final int? id;
  final String namaPartner;
  final DateTime tanggal;
  final String jenis; // SAYA_MENALANGI / SAYA_MENERIMA
  final double nominal;
  final String metodePembayaran; // CASH / TRANSFER / CAMPURAN
  final double cashTerpakai;
  final double transferTerpakai;
  final String? jenisTransfer; // V4.2.1
  final double biayaAdminTransfer; // V4.2.1
  /// TUNAI / NON_TUNAI — lihat AppConstants.bentukTalangan*. Hanya
  /// relevan saat jenis == SAYA_MENERIMA.
  final String bentukTalangan;
  final String status; // BELUM_LUNAS / SEBAGIAN_LUNAS / LUNAS / BATAL
  final double totalDibayarKembali;
  final String? keterangan;
  final int? periodeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DanaTalangModel({
    this.id,
    required this.namaPartner,
    required this.tanggal,
    required this.jenis,
    required this.nominal,
    this.metodePembayaran = AppConstants.metodeCash,
    this.cashTerpakai = 0,
    this.transferTerpakai = 0,
    this.jenisTransfer,
    this.biayaAdminTransfer = 0,
    this.bentukTalangan = AppConstants.bentukTalanganTunai,
    this.status = AppConstants.statusDanaTalangBelumLunas,
    this.totalDibayarKembali = 0,
    this.keterangan,
    this.periodeId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isMenalangi => jenis == AppConstants.danaTalangSayaMenalangi;
  bool get isNonTunai => bentukTalangan == AppConstants.bentukTalanganNonTunai;
  bool get isAktif =>
      status != AppConstants.statusDanaTalangLunas &&
      status != AppConstants.statusDanaTalangBatal;
  double get sisa =>
      status == AppConstants.statusDanaTalangBatal
          ? 0
          : (nominal - totalDibayarKembali).clamp(0, nominal);

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nama_partner': namaPartner,
      'tanggal': tanggal.toIso8601String(),
      'jenis': jenis,
      'nominal': nominal,
      'metode_pembayaran': metodePembayaran,
      'cash_terpakai': cashTerpakai,
      'transfer_terpakai': transferTerpakai,
      'jenis_transfer': jenisTransfer,
      'biaya_admin_transfer': biayaAdminTransfer,
      'bentuk_talangan': bentukTalangan,
      'status': status,
      'total_dibayar_kembali': totalDibayarKembali,
      'keterangan': keterangan,
      'periode_id': periodeId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory DanaTalangModel.fromMap(Map<String, dynamic> map) {
    return DanaTalangModel(
      id: map['id'] as int?,
      namaPartner: map['nama_partner'] as String,
      tanggal: DateTime.parse(map['tanggal'] as String),
      jenis: map['jenis'] as String,
      nominal: (map['nominal'] as num).toDouble(),
      metodePembayaran:
          (map['metode_pembayaran'] as String?) ?? AppConstants.metodeCash,
      cashTerpakai: (map['cash_terpakai'] as num?)?.toDouble() ?? 0,
      transferTerpakai: (map['transfer_terpakai'] as num?)?.toDouble() ?? 0,
      jenisTransfer: map['jenis_transfer'] as String?,
      biayaAdminTransfer:
          (map['biaya_admin_transfer'] as num?)?.toDouble() ?? 0,
      bentukTalangan:
          (map['bentuk_talangan'] as String?) ?? AppConstants.bentukTalanganTunai,
      status:
          (map['status'] as String?) ?? AppConstants.statusDanaTalangBelumLunas,
      totalDibayarKembali:
          (map['total_dibayar_kembali'] as num?)?.toDouble() ?? 0,
      keterangan: map['keterangan'] as String?,
      periodeId: map['periode_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  DanaTalangModel copyWith({
    int? id,
    String? namaPartner,
    DateTime? tanggal,
    String? jenis,
    double? nominal,
    String? metodePembayaran,
    double? cashTerpakai,
    double? transferTerpakai,
    String? jenisTransfer,
    double? biayaAdminTransfer,
    String? bentukTalangan,
    String? status,
    double? totalDibayarKembali,
    String? keterangan,
    int? periodeId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DanaTalangModel(
      id: id ?? this.id,
      namaPartner: namaPartner ?? this.namaPartner,
      tanggal: tanggal ?? this.tanggal,
      jenis: jenis ?? this.jenis,
      nominal: nominal ?? this.nominal,
      metodePembayaran: metodePembayaran ?? this.metodePembayaran,
      cashTerpakai: cashTerpakai ?? this.cashTerpakai,
      transferTerpakai: transferTerpakai ?? this.transferTerpakai,
      jenisTransfer: jenisTransfer ?? this.jenisTransfer,
      biayaAdminTransfer: biayaAdminTransfer ?? this.biayaAdminTransfer,
      bentukTalangan: bentukTalangan ?? this.bentukTalangan,
      status: status ?? this.status,
      totalDibayarKembali: totalDibayarKembali ?? this.totalDibayarKembali,
      keterangan: keterangan ?? this.keterangan,
      periodeId: periodeId ?? this.periodeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        namaPartner,
        tanggal,
        jenis,
        nominal,
        metodePembayaran,
        cashTerpakai,
        transferTerpakai,
        jenisTransfer,
        biayaAdminTransfer,
        bentukTalangan,
        status,
        totalDibayarKembali,
        keterangan,
        periodeId,
        createdAt,
        updatedAt,
      ];
}
