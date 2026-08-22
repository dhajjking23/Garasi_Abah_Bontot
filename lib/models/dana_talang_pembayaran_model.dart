import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class DanaTalangPembayaranModel extends Equatable {
  final int? id;
  final int danaTalangId;
  final DateTime tanggal;
  final double nominal;
  final String metodePembayaran; // CASH / TRANSFER / CAMPURAN
  final double cashTerpakai;
  final double transferTerpakai;
  final String? jenisTransfer; // V4.2.2
  final double biayaAdminTransfer; // V4.2.2
  final String? keterangan;
  final DateTime createdAt;

  const DanaTalangPembayaranModel({
    this.id,
    required this.danaTalangId,
    required this.tanggal,
    required this.nominal,
    this.metodePembayaran = AppConstants.metodeCash,
    this.cashTerpakai = 0,
    this.transferTerpakai = 0,
    this.jenisTransfer,
    this.biayaAdminTransfer = 0,
    this.keterangan,
    required this.createdAt,
  });

  DanaTalangPembayaranModel copyWith({
    int? id,
    int? danaTalangId,
    DateTime? tanggal,
    double? nominal,
    String? metodePembayaran,
    double? cashTerpakai,
    double? transferTerpakai,
    String? jenisTransfer,
    double? biayaAdminTransfer,
    String? keterangan,
    DateTime? createdAt,
  }) {
    return DanaTalangPembayaranModel(
      id: id ?? this.id,
      danaTalangId: danaTalangId ?? this.danaTalangId,
      tanggal: tanggal ?? this.tanggal,
      nominal: nominal ?? this.nominal,
      metodePembayaran: metodePembayaran ?? this.metodePembayaran,
      cashTerpakai: cashTerpakai ?? this.cashTerpakai,
      transferTerpakai: transferTerpakai ?? this.transferTerpakai,
      jenisTransfer: jenisTransfer ?? this.jenisTransfer,
      biayaAdminTransfer: biayaAdminTransfer ?? this.biayaAdminTransfer,
      keterangan: keterangan ?? this.keterangan,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'dana_talang_id': danaTalangId,
      'tanggal': tanggal.toIso8601String(),
      'nominal': nominal,
      'metode_pembayaran': metodePembayaran,
      'cash_terpakai': cashTerpakai,
      'transfer_terpakai': transferTerpakai,
      'jenis_transfer': jenisTransfer,
      'biaya_admin_transfer': biayaAdminTransfer,
      'keterangan': keterangan,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory DanaTalangPembayaranModel.fromMap(Map<String, dynamic> map) {
    return DanaTalangPembayaranModel(
      id: map['id'] as int?,
      danaTalangId: map['dana_talang_id'] as int,
      tanggal: DateTime.parse(map['tanggal'] as String),
      nominal: (map['nominal'] as num).toDouble(),
      metodePembayaran:
          (map['metode_pembayaran'] as String?) ?? AppConstants.metodeCash,
      cashTerpakai: (map['cash_terpakai'] as num?)?.toDouble() ?? 0,
      transferTerpakai: (map['transfer_terpakai'] as num?)?.toDouble() ?? 0,
      jenisTransfer: map['jenis_transfer'] as String?,
      biayaAdminTransfer:
          (map['biaya_admin_transfer'] as num?)?.toDouble() ?? 0,
      keterangan: map['keterangan'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        danaTalangId,
        tanggal,
        nominal,
        metodePembayaran,
        cashTerpakai,
        transferTerpakai,
        jenisTransfer,
        biayaAdminTransfer,
        keterangan,
        createdAt,
      ];
}
