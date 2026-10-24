import '../../services/auth_service.dart';

/// Dilempar ketika VIEWER mencoba melakukan operasi tulis (insert/update/delete).
/// Semua repository & service WAJIB memanggil [requireWriteAccess] di awal
/// setiap method yang mengubah data — validasi UI saja tidak cukup, karena
/// role harus ditegakkan di layer data (repository/service), bukan hanya UI.
class PermissionDeniedException implements Exception {
  final String message;
  const PermissionDeniedException([this.message = 'Akses ditolak: akun VIEWER hanya bisa melihat data (read-only).']);

  @override
  String toString() => message;
}

/// Panggil di baris pertama setiap method tambah/edit/hapus/update/bayar/dll.
/// Melempar [PermissionDeniedException] jika user aktif adalah VIEWER atau
/// belum login sama sekali.
void requireWriteAccess() {
  if (!AuthService.instance.canWrite()) {
    throw const PermissionDeniedException();
  }
}
