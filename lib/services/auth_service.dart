import '../models/user_model.dart';
import '../repositories/user_repository.dart';

/// AuthService — session sederhana in-memory (single device login).
/// Role hanya OWNER_ADMIN (Andri, full access) dan VIEWER (Partner, read only).
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final UserRepository _userRepository = UserRepository();

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  bool get isLoggedIn => _currentUser != null;
  bool get isOwnerAdmin => _currentUser?.isOwnerAdmin ?? false;
  bool get isViewer => _currentUser?.isViewer ?? false;

  Future<UserModel?> login(String username, String password) async {
    final user = await _userRepository.login(username, password);
    if (user != null) {
      _currentUser = user;
    }
    return user;
  }

  void logout() {
    _currentUser = null;
  }

  /// Dipanggil AuthNotifier saat me-restore sesi tersimpan (persistent
  /// login) — set current user TANPA verifikasi password ulang, karena
  /// identitas sudah diverifikasi lewat username yang tersimpan +
  /// pengecekan status ACTIVE di database.
  void restoreSession(UserModel user) {
    _currentUser = user;
  }

  /// Guard untuk aksi tulis (tambah/edit/hapus). VIEWER selalu ditolak.
  bool canWrite() => isOwnerAdmin;
}
