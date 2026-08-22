import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class MotorModel extends Equatable {
  final int? id;
  final String kodeMotor;
  final String merk;
  final String tipe;
  final int? tahun;
  final String? warna;
  final String? platNomor;
  final DateTime tanggalMasuk;
  final double hargaBeli;
  final double totalModal;
  final String status;
  final String metodePembayaran; // CASH / TRANSFER / CAMPURAN
  final String? catatan;
  final double cashDibayar;
  final double transferDibayar;
  final String? jenisTransfer; // V4.2.1
  final double biayaAdminTransfer; // V4.2.1
  final int? periodeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MotorModel({
    this.id,
    required this.kodeMotor,
    required this.merk,
    required this.tipe,
    this.tahun,
    this.warna,
    this.platNomor,
    required this.tanggalMasuk,
    this.hargaBeli = 0,
    this.totalModal = 0,
    this.status = AppConstants.statusMotorTersedia,
    this.metodePembayaran = AppConstants.metodeCash,
    this.catatan,
    this.cashDibayar = 0,
    this.transferDibayar = 0,
    this.jenisTransfer,
    this.biayaAdminTransfer = 0,
    this.periodeId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isTerjual => status == AppConstants.statusMotorTerjual;
  String get namaLengkap => '$merk $tipe${tahun != null ? " ($tahun)" : ""}';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'kode_motor': kodeMotor,
      'merk': merk,
      'tipe': tipe,
      'tahun': tahun,
      'warna': warna,
      'plat_nomor': platNomor,
      'tanggal_masuk': tanggalMasuk.toIso8601String(),
      'harga_beli': hargaBeli,
      'total_modal': totalModal,
      'status': status,
      'metode_pembayaran': metodePembayaran,
      'cash_dibayar': cashDibayar,
      'transfer_dibayar': transferDibayar,
      'jenis_transfer': jenisTransfer,
      'biaya_admin_transfer': biayaAdminTransfer,
      'catatan': catatan,
      'periode_id': periodeId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory MotorModel.fromMap(Map<String, dynamic> map) {
    return MotorModel(
      id: map['id'] as int?,
      kodeMotor: map['kode_motor'] as String,
      merk: map['merk'] as String,
      tipe: map['tipe'] as String,
      tahun: map['tahun'] as int?,
      warna: map['warna'] as String?,
      platNomor: map['plat_nomor'] as String?,
      tanggalMasuk: DateTime.parse(map['tanggal_masuk'] as String),
      hargaBeli: (map['harga_beli'] as num).toDouble(),
      totalModal: (map['total_modal'] as num).toDouble(),
      status: map['status'] as String,
      metodePembayaran:
          (map['metode_pembayaran'] as String?) ?? AppConstants.metodeCash,
      cashDibayar: (map['cash_dibayar'] as num?)?.toDouble() ?? 0,
      transferDibayar: (map['transfer_dibayar'] as num?)?.toDouble() ?? 0,
      jenisTransfer: map['jenis_transfer'] as String?,
      biayaAdminTransfer:
          (map['biaya_admin_transfer'] as num?)?.toDouble() ?? 0,
      catatan: map['catatan'] as String?,
      periodeId: map['periode_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  MotorModel copyWith({
    int? id,
    String? kodeMotor,
    String? merk,
    String? tipe,
    int? tahun,
    String? warna,
    String? platNomor,
    DateTime? tanggalMasuk,
    double? hargaBeli,
    double? totalModal,
    String? status,
    String? metodePembayaran,
    double? cashDibayar,
    double? transferDibayar,
    String? jenisTransfer,
    double? biayaAdminTransfer,
    String? catatan,
    int? periodeId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MotorModel(
      id: id ?? this.id,
      kodeMotor: kodeMotor ?? this.kodeMotor,
      merk: merk ?? this.merk,
      tipe: tipe ?? this.tipe,
      tahun: tahun ?? this.tahun,
      warna: warna ?? this.warna,
      platNomor: platNomor ?? this.platNomor,
      tanggalMasuk: tanggalMasuk ?? this.tanggalMasuk,
      hargaBeli: hargaBeli ?? this.hargaBeli,
      totalModal: totalModal ?? this.totalModal,
      status: status ?? this.status,
      metodePembayaran: metodePembayaran ?? this.metodePembayaran,
      cashDibayar: cashDibayar ?? this.cashDibayar,
      transferDibayar: transferDibayar ?? this.transferDibayar,
      jenisTransfer: jenisTransfer ?? this.jenisTransfer,
      biayaAdminTransfer: biayaAdminTransfer ?? this.biayaAdminTransfer,
      catatan: catatan ?? this.catatan,
      periodeId: periodeId ?? this.periodeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        kodeMotor,
        merk,
        tipe,
        tahun,
        warna,
        platNomor,
        tanggalMasuk,
        hargaBeli,
        totalModal,
        status,
        metodePembayaran,
        cashDibayar,
        transferDibayar,
        jenisTransfer,
        biayaAdminTransfer,
        catatan,
        periodeId,
        createdAt,
        updatedAt,
      ];
}
