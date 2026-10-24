import 'package:equatable/equatable.dart';

class SaldoModel extends Equatable {
  final double cash;
  final double saldoBank;
  final double modalCash;
  final double modalBank;
  final DateTime updatedAt;

  const SaldoModel({
    required this.cash,
    required this.saldoBank,
    this.modalCash = 0,
    this.modalBank = 0,
    required this.updatedAt,
  });

  double get modalTotal => modalCash + modalBank;
  double get totalKas => cash + saldoBank;

  Map<String, dynamic> toMap() {
    return {
      'id': 1,
      'cash': cash,
      'saldo_bank': saldoBank,
      'modal_cash': modalCash,
      'modal_bank': modalBank,
      'modal_total': modalTotal,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory SaldoModel.fromMap(Map<String, dynamic> map) {
    return SaldoModel(
      cash: (map['cash'] as num).toDouble(),
      saldoBank: (map['saldo_bank'] as num).toDouble(),
      modalCash: (map['modal_cash'] as num?)?.toDouble() ?? 0,
      modalBank: (map['modal_bank'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  SaldoModel copyWith({
    double? cash,
    double? saldoBank,
    double? modalCash,
    double? modalBank,
    DateTime? updatedAt,
  }) {
    return SaldoModel(
      cash: cash ?? this.cash,
      saldoBank: saldoBank ?? this.saldoBank,
      modalCash: modalCash ?? this.modalCash,
      modalBank: modalBank ?? this.modalBank,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props =>
      [cash, saldoBank, modalCash, modalBank, updatedAt];
}
