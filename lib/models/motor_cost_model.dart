import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class MotorCostModel extends Equatable {
  final int? id;
  final int motorId;
  final String kategori;
  final double nominal;
  final String metodePembayaran; // CASH / TRANSFER / CAMPURAN
  final double cashDibayar;
  final double transferDibayar;
  final String? jenisTransfer; // V4.2.1
  final double biayaAdminTransfer; // V4.2.1
  final String? keterangan;
  final DateTime tanggal;
  final DateTime createdAt;

  const MotorCostModel({
    this.id,
    required this.motorId,
    required this.kategori,
    required this.nominal,
    this.metodePembayaran = AppConstants.metodeCash,
    this.cashDibayar = 0,
    this.transferDibayar = 0,
    this.jenisTransfer,
    this.biayaAdminTransfer = 0,
    this.keterangan,
    required this.tanggal,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'motor_id': motorId,
      'kategori': kategori,
      'nominal': nominal,
      'metode_pembayaran': metodePembayaran,
      'cash_dibayar': cashDibayar,
      'transfer_dibayar': transferDibayar,
      'jenis_transfer': jenisTransfer,
      'biaya_admin_transfer': biayaAdminTransfer,
      'keterangan': keterangan,
      'tanggal': tanggal.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory MotorCostModel.fromMap(Map<String, dynamic> map) {
    return MotorCostModel(
      id: map['id'] as int?,
      motorId: map['motor_id'] as int,
      kategori: map['kategori'] as String,
      nominal: (map['nominal'] as num).toDouble(),
      metodePembayaran:
          (map['metode_pembayaran'] as String?) ?? AppConstants.metodeCash,
      cashDibayar: (map['cash_dibayar'] as num?)?.toDouble() ?? 0,
      transferDibayar: (map['transfer_dibayar'] as num?)?.toDouble() ?? 0,
      jenisTransfer: map['jenis_transfer'] as String?,
      biayaAdminTransfer:
          (map['biaya_admin_transfer'] as num?)?.toDouble() ?? 0,
      keterangan: map['keterangan'] as String?,
      tanggal: DateTime.parse(map['tanggal'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  MotorCostModel copyWith({
    int? id,
    int? motorId,
    String? kategori,
    double? nominal,
    String? metodePembayaran,
    double? cashDibayar,
    double? transferDibayar,
    String? jenisTransfer,
    double? biayaAdminTransfer,
    String? keterangan,
    DateTime? tanggal,
    DateTime? createdAt,
  }) {
    return MotorCostModel(
      id: id ?? this.id,
      motorId: motorId ?? this.motorId,
      kategori: kategori ?? this.kategori,
      nominal: nominal ?? this.nominal,
      metodePembayaran: metodePembayaran ?? this.metodePembayaran,
      cashDibayar: cashDibayar ?? this.cashDibayar,
      transferDibayar: transferDibayar ?? this.transferDibayar,
      jenisTransfer: jenisTransfer ?? this.jenisTransfer,
      biayaAdminTransfer: biayaAdminTransfer ?? this.biayaAdminTransfer,
      keterangan: keterangan ?? this.keterangan,
      tanggal: tanggal ?? this.tanggal,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        motorId,
        kategori,
        nominal,
        metodePembayaran,
        cashDibayar,
        transferDibayar,
        jenisTransfer,
        biayaAdminTransfer,
        keterangan,
        tanggal,
        createdAt,
      ];
}
