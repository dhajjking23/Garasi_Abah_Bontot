import 'package:shared_preferences/shared_preferences.dart';

/// Persistent login session. Menyimpan USERNAME (bukan password) yang
/// sedang login secara lokal, sehingga sesi tetap aktif walau aplikasi
/// ditutup, HP di-restart, atau server offline. Logout hanya terjadi
/// jika: (1) user logout sendiri, atau (2) OWNER_ADMIN menonaktifkan
/// akun tsb (dicek ulang saat sesi direstore — lihat AuthNotifier).
class SessionService {
  static const _kSessionUsername = 'session_username';

  Future<void> saveSession(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionUsername, username);
  }

  Future<String?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSessionUsername);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionUsername);
  }
}
