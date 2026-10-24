import 'package:equatable/equatable.dart';

/// V5.9 — "Foto" hasil rekonsiliasi keuangan pada momen tertentu.
/// BUKAN mekanisme lock — periode & transaksi tetap 100% bisa diedit
/// kapan saja setelah snapshot ini dibuat. Kalau ada perubahan transaksi
/// setelahnya, jalankan closing baru (Recalculate) — snapshot lama tetap
/// tersimpan sebagai histori/revisi, tidak pernah ditimpa.
class ClosingSnapshotModel extends Equatable {
  final int? id;
  final int periodeId;
  final int closingNumber;
  final DateTime periodStart;
  final DateTime? periodEnd;
  final double totalModal;
  final double totalPenjualan;
  final double totalModalMotor;
  final double totalBiaya;
  final double totalLaba;
  final double cash;
  final double bank;
  final double stock;
  final double piutang;
  final double kasbon;
  final double hutang;
  final double danaTalang;
  final double totalAsset;
  final double totalLiability;
  final double totalEquity;
  final double balanceDifference;
  final String closingStatus; // BALANCE / TIDAK_BALANCE
  final DateTime createdAt;
  final String? createdBy;

  const ClosingSnapshotModel({
    this.id,
    required this.periodeId,
    required this.closingNumber,
    required this.periodStart,
    this.periodEnd,
    required this.totalModal,
    required this.totalPenjualan,
    required this.totalModalMotor,
    required this.totalBiaya,
    required this.totalLaba,
    required this.cash,
    required this.bank,
    required this.stock,
    required this.piutang,
    required this.kasbon,
    required this.hutang,
    required this.danaTalang,
    required this.totalAsset,
    required this.totalLiability,
    required this.totalEquity,
    required this.balanceDifference,
    required this.closingStatus,
    required this.createdAt,
    this.createdBy,
  });

  bool get isBalance => closingStatus == 'BALANCE';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'periode_id': periodeId,
      'closing_number': closingNumber,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd?.toIso8601String(),
      'total_modal': totalModal,
      'total_penjualan': totalPenjualan,
      'total_modal_motor': totalModalMotor,
      'total_biaya': totalBiaya,
      'total_laba': totalLaba,
      'cash': cash,
      'bank': bank,
      'stock': stock,
      'piutang': piutang,
      'kasbon': kasbon,
      'hutang': hutang,
      'dana_talang': danaTalang,
      'total_asset': totalAsset,
      'total_liability': totalLiability,
      'total_equity': totalEquity,
      'balance_difference': balanceDifference,
      'closing_status': closingStatus,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
    };
  }

  factory ClosingSnapshotModel.fromMap(Map<String, dynamic> map) {
    return ClosingSnapshotModel(
      id: map['id'] as int?,
      periodeId: map['periode_id'] as int,
      closingNumber: map['closing_number'] as int,
      periodStart: DateTime.parse(map['period_start'] as String),
      periodEnd: map['period_end'] != null
          ? DateTime.parse(map['period_end'] as String)
          : null,
      totalModal: (map['total_modal'] as num).toDouble(),
      totalPenjualan: (map['total_penjualan'] as num).toDouble(),
      totalModalMotor: (map['total_modal_motor'] as num).toDouble(),
      totalBiaya: (map['total_biaya'] as num).toDouble(),
      totalLaba: (map['total_laba'] as num).toDouble(),
      cash: (map['cash'] as num).toDouble(),
      bank: (map['bank'] as num).toDouble(),
      stock: (map['stock'] as num).toDouble(),
      piutang: (map['piutang'] as num).toDouble(),
      kasbon: (map['kasbon'] as num).toDouble(),
      hutang: (map['hutang'] as num).toDouble(),
      danaTalang: (map['dana_talang'] as num).toDouble(),
      totalAsset: (map['total_asset'] as num).toDouble(),
      totalLiability: (map['total_liability'] as num).toDouble(),
      totalEquity: (map['total_equity'] as num).toDouble(),
      balanceDifference: (map['balance_difference'] as num).toDouble(),
      closingStatus: map['closing_status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      createdBy: map['created_by'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        periodeId,
        closingNumber,
        periodStart,
        periodEnd,
        totalModal,
        totalPenjualan,
        totalModalMotor,
        totalBiaya,
        totalLaba,
        cash,
        bank,
        stock,
        piutang,
        kasbon,
        hutang,
        danaTalang,
        totalAsset,
        totalLiability,
        totalEquity,
        balanceDifference,
        closingStatus,
        createdAt,
        createdBy,
      ];
}
