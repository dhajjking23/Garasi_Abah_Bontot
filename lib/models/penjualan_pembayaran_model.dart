import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class PenjualanPembayaranModel extends Equatable {
  final int? id;
  final int penjualanId;
  final DateTime tanggal;
  final double nominal;
  final String metodePembayaran; // CASH / TRANSFER / CAMPURAN
  final double cashTerpakai;
  final double transferTerpakai;
  final String? keterangan;
  final DateTime createdAt;

  const PenjualanPembayaranModel({
    this.id,
    required this.penjualanId,
    required this.tanggal,
    required this.nominal,
    this.metodePembayaran = AppConstants.metodeCash,
    this.cashTerpakai = 0,
    this.transferTerpakai = 0,
    this.keterangan,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'penjualan_id': penjualanId,
      'tanggal': tanggal.toIso8601String(),
      'nominal': nominal,
      'metode_pembayaran': metodePembayaran,
      'cash_terpakai': cashTerpakai,
      'transfer_terpakai': transferTerpakai,
      'keterangan': keterangan,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PenjualanPembayaranModel.fromMap(Map<String, dynamic> map) {
    return PenjualanPembayaranModel(
      id: map['id'] as int?,
      penjualanId: map['penjualan_id'] as int,
      tanggal: DateTime.parse(map['tanggal'] as String),
      nominal: (map['nominal'] as num).toDouble(),
      metodePembayaran:
          (map['metode_pembayaran'] as String?) ?? AppConstants.metodeCash,
      cashTerpakai: (map['cash_terpakai'] as num?)?.toDouble() ?? 0,
      transferTerpakai: (map['transfer_terpakai'] as num?)?.toDouble() ?? 0,
      keterangan: map['keterangan'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        penjualanId,
        tanggal,
        nominal,
        metodePembayaran,
        cashTerpakai,
        transferTerpakai,
        keterangan,
        createdAt,
      ];
}
