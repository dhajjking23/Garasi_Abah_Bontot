import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class PeriodeModel extends Equatable {
  final int? id;
  final String namaPeriode;
  final DateTime tanggalMulai;
  final DateTime? tanggalSelesai;
  final String status;

  /// Modal Awal — SNAPSHOT/ANCHOR nilai modal saat periode dibuat.
  /// Ini BUKAN cashflow: nilainya TIDAK berubah karena transaksi
  /// (pembelian motor, penjualan, dsb) selama periode berjalan. Dipakai
  /// sebagai patokan untuk menghitung "Laba berdasarkan perubahan
  /// modal" = Total Aset Akhir - Modal Awal.
  final double modalAwalCash;
  final double modalAwalBank;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PeriodeModel({
    this.id,
    required this.namaPeriode,
    required this.tanggalMulai,
    this.tanggalSelesai,
    this.status = AppConstants.statusPeriodeAktif,
    this.modalAwalCash = 0,
    this.modalAwalBank = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAktif => status == AppConstants.statusPeriodeAktif;
  double get modalAwal => modalAwalCash + modalAwalBank;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nama_periode': namaPeriode,
      'tanggal_mulai': tanggalMulai.toIso8601String(),
      'tanggal_selesai': tanggalSelesai?.toIso8601String(),
      'status': status,
      'modal_awal': modalAwal,
      'modal_awal_cash': modalAwalCash,
      'modal_awal_bank': modalAwalBank,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PeriodeModel.fromMap(Map<String, dynamic> map) {
    final modalAwalCash = (map['modal_awal_cash'] as num?)?.toDouble();
    final modalAwalLama = (map['modal_awal'] as num?)?.toDouble() ?? 0;
    return PeriodeModel(
      id: map['id'] as int?,
      namaPeriode: map['nama_periode'] as String,
      tanggalMulai: DateTime.parse(map['tanggal_mulai'] as String),
      tanggalSelesai: map['tanggal_selesai'] != null
          ? DateTime.parse(map['tanggal_selesai'] as String)
          : null,
      status: map['status'] as String,
      // Fallback ke modal_awal lama (semua dianggap cash) jika kolom
      // baru belum terisi — jaga-jaga untuk baris hasil migrasi lama.
      modalAwalCash: modalAwalCash ?? modalAwalLama,
      modalAwalBank: (map['modal_awal_bank'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  PeriodeModel copyWith({
    int? id,
    String? namaPeriode,
    DateTime? tanggalMulai,
    DateTime? tanggalSelesai,
    String? status,
    double? modalAwalCash,
    double? modalAwalBank,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PeriodeModel(
      id: id ?? this.id,
      namaPeriode: namaPeriode ?? this.namaPeriode,
      tanggalMulai: tanggalMulai ?? this.tanggalMulai,
      tanggalSelesai: tanggalSelesai ?? this.tanggalSelesai,
      status: status ?? this.status,
      modalAwalCash: modalAwalCash ?? this.modalAwalCash,
      modalAwalBank: modalAwalBank ?? this.modalAwalBank,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        namaPeriode,
        tanggalMulai,
        tanggalSelesai,
        status,
        modalAwalCash,
        modalAwalBank,
        createdAt,
        updatedAt,
      ];
}
