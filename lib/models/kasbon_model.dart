import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class KasbonModel extends Equatable {
  final int? id;
  final String namaKaryawan;
  final DateTime tanggal;
  final double jumlah;
  final String sumber; // CASH / BANK
  final String? jenisTransfer; // Gratis/BI_FAST/REALTIME, hanya jika sumber BANK
  final double biayaAdminTransfer; // V4.2.1 — biaya transfer global
  final String status;
  /// V5.9.2 — total yang sudah dibayar (cicilan). `jumlah - totalDibayar`
  /// = sisa outstanding. Untuk baris lama (sebelum fitur ini ada) selalu
  /// 0, jadi perilaku lama (outstanding = jumlah penuh) tidak berubah.
  final double totalDibayar;
  /// V5.9.4 — arsip (BUKAN hapus): true kalau kasbon ini disembunyikan
  /// dari daftar aktif karena sudah LUNAS saat periode baru dibuka.
  /// Data tetap ada di database untuk audit.
  final bool isArchived;
  final DateTime? tanggalLunas;
  final String? keterangan;
  final DateTime createdAt;
  final DateTime updatedAt;

  const KasbonModel({
    this.id,
    required this.namaKaryawan,
    required this.tanggal,
    required this.jumlah,
    this.sumber = AppConstants.sumberCash,
    this.jenisTransfer,
    this.biayaAdminTransfer = 0,
    this.status = AppConstants.statusKasbonBelumLunas,
    this.totalDibayar = 0,
    this.isArchived = false,
    this.tanggalLunas,
    this.keterangan,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isLunas => status == AppConstants.statusKasbonLunas;
  bool get isAktif => status != AppConstants.statusKasbonLunas;
  double get sisa => (jumlah - totalDibayar).clamp(0, jumlah);

  /// Total uang keluar sebenarnya (jumlah kasbon + biaya admin transfer).
  double get totalKeluar => jumlah + biayaAdminTransfer;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nama_karyawan': namaKaryawan,
      'tanggal': tanggal.toIso8601String(),
      'jumlah': jumlah,
      'sumber': sumber,
      'jenis_transfer': jenisTransfer,
      'biaya_admin_transfer': biayaAdminTransfer,
      'status': status,
      'total_dibayar': totalDibayar,
      'is_archived': isArchived ? 1 : 0,
      'tanggal_lunas': tanggalLunas?.toIso8601String(),
      'keterangan': keterangan,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory KasbonModel.fromMap(Map<String, dynamic> map) {
    return KasbonModel(
      id: map['id'] as int?,
      namaKaryawan: map['nama_karyawan'] as String,
      tanggal: DateTime.parse(map['tanggal'] as String),
      jumlah: (map['jumlah'] as num).toDouble(),
      sumber: (map['sumber'] as String?) ?? AppConstants.sumberCash,
      jenisTransfer: map['jenis_transfer'] as String?,
      biayaAdminTransfer:
          (map['biaya_admin_transfer'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String,
      totalDibayar: (map['total_dibayar'] as num?)?.toDouble() ?? 0,
      isArchived: (map['is_archived'] as int?) == 1,
      tanggalLunas: map['tanggal_lunas'] != null
          ? DateTime.parse(map['tanggal_lunas'] as String)
          : null,
      keterangan: map['keterangan'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  KasbonModel copyWith({
    int? id,
    String? namaKaryawan,
    DateTime? tanggal,
    double? jumlah,
    String? sumber,
    String? jenisTransfer,
    double? biayaAdminTransfer,
    String? status,
    double? totalDibayar,
    bool? isArchived,
    DateTime? tanggalLunas,
    String? keterangan,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KasbonModel(
      id: id ?? this.id,
      namaKaryawan: namaKaryawan ?? this.namaKaryawan,
      tanggal: tanggal ?? this.tanggal,
      jumlah: jumlah ?? this.jumlah,
      sumber: sumber ?? this.sumber,
      jenisTransfer: jenisTransfer ?? this.jenisTransfer,
      biayaAdminTransfer: biayaAdminTransfer ?? this.biayaAdminTransfer,
      status: status ?? this.status,
      totalDibayar: totalDibayar ?? this.totalDibayar,
      isArchived: isArchived ?? this.isArchived,
      tanggalLunas: tanggalLunas ?? this.tanggalLunas,
      keterangan: keterangan ?? this.keterangan,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        namaKaryawan,
        tanggal,
        jumlah,
        sumber,
        jenisTransfer,
        biayaAdminTransfer,
        status,
        totalDibayar,
        isArchived,
        tanggalLunas,
        keterangan,
        createdAt,
        updatedAt,
      ];
}
