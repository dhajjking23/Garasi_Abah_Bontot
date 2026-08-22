import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class PenjualanModel extends Equatable {
  final int? id;
  final int motorId;
  final DateTime tanggalJual;
  final double hargaJual;
  final double modalMotor;
  final double laba;
  final String penjual;
  final bool bonusEligible;
  final String metodePembayaran; // CASH / TRANSFER / CAMPURAN
  /// Total kumulatif yang SUDAH diterima lewat Cash (DP + semua cicilan).
  final double cashDiterima;
  /// Total kumulatif yang SUDAH diterima lewat Transfer (DP + cicilan).
  final double transferDiterima;
  /// LUNAS atau BELUM_LUNAS (DP/dicicil). Lihat AppConstants.statusPembayaran*.
  final String statusPembayaran;
  final int? periodeId;
  final DateTime createdAt;

  const PenjualanModel({
    this.id,
    required this.motorId,
    required this.tanggalJual,
    required this.hargaJual,
    required this.modalMotor,
    required this.laba,
    required this.penjual,
    this.bonusEligible = true,
    this.metodePembayaran = AppConstants.metodeCash,
    this.cashDiterima = 0,
    this.transferDiterima = 0,
    this.statusPembayaran = AppConstants.statusPembayaranLunas,
    this.periodeId,
    required this.createdAt,
  });

  double get totalDiterima => cashDiterima + transferDiterima;
  double get sisaPembayaran =>
      (hargaJual - totalDiterima).clamp(0, hargaJual);
  bool get isLunas => statusPembayaran == AppConstants.statusPembayaranLunas;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'motor_id': motorId,
      'tanggal_jual': tanggalJual.toIso8601String(),
      'harga_jual': hargaJual,
      'modal_motor': modalMotor,
      'laba': laba,
      'penjual': penjual,
      'bonus_eligible': bonusEligible ? 1 : 0,
      'metode_pembayaran': metodePembayaran,
      'cash_diterima': cashDiterima,
      'transfer_diterima': transferDiterima,
      'status_pembayaran': statusPembayaran,
      'periode_id': periodeId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PenjualanModel.fromMap(Map<String, dynamic> map) {
    return PenjualanModel(
      id: map['id'] as int?,
      motorId: map['motor_id'] as int,
      tanggalJual: DateTime.parse(map['tanggal_jual'] as String),
      hargaJual: (map['harga_jual'] as num).toDouble(),
      modalMotor: (map['modal_motor'] as num).toDouble(),
      laba: (map['laba'] as num).toDouble(),
      penjual: map['penjual'] as String,
      bonusEligible: (map['bonus_eligible'] as int) == 1,
      metodePembayaran:
          (map['metode_pembayaran'] as String?) ?? AppConstants.metodeCash,
      cashDiterima: (map['cash_diterima'] as num?)?.toDouble() ?? 0,
      transferDiterima: (map['transfer_diterima'] as num?)?.toDouble() ?? 0,
      statusPembayaran: (map['status_pembayaran'] as String?) ??
          AppConstants.statusPembayaranLunas,
      periodeId: map['periode_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  PenjualanModel copyWith({
    int? id,
    int? motorId,
    DateTime? tanggalJual,
    double? hargaJual,
    double? modalMotor,
    double? laba,
    String? penjual,
    bool? bonusEligible,
    String? metodePembayaran,
    double? cashDiterima,
    double? transferDiterima,
    String? statusPembayaran,
    int? periodeId,
    DateTime? createdAt,
  }) {
    return PenjualanModel(
      id: id ?? this.id,
      motorId: motorId ?? this.motorId,
      tanggalJual: tanggalJual ?? this.tanggalJual,
      hargaJual: hargaJual ?? this.hargaJual,
      modalMotor: modalMotor ?? this.modalMotor,
      laba: laba ?? this.laba,
      penjual: penjual ?? this.penjual,
      bonusEligible: bonusEligible ?? this.bonusEligible,
      metodePembayaran: metodePembayaran ?? this.metodePembayaran,
      cashDiterima: cashDiterima ?? this.cashDiterima,
      transferDiterima: transferDiterima ?? this.transferDiterima,
      statusPembayaran: statusPembayaran ?? this.statusPembayaran,
      periodeId: periodeId ?? this.periodeId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        motorId,
        tanggalJual,
        hargaJual,
        modalMotor,
        laba,
        penjual,
        bonusEligible,
        metodePembayaran,
        cashDiterima,
        transferDiterima,
        statusPembayaran,
        periodeId,
        createdAt,
      ];
}
