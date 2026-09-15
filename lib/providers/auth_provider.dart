import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository());
final sessionServiceProvider = Provider<SessionService>((ref) => SessionService());

/// State gabungan: user yang login (null = belum login) + flag restoring
/// (true selagi mengecek sesi tersimpan saat app baru dibuka).
class AuthState {
  final UserModel? user;
  final bool restoring;
  const AuthState({this.user, this.restoring = false});

  AuthState copyWith({UserModel? user, bool clearUser = false, bool? restoring}) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      restoring: restoring ?? this.restoring,
    );
  }
}

/// PERSISTENT LOGIN: begitu user login, username disimpan lokal. Saat app
/// dibuka lagi (restart app / restart HP), [_restoreSession] otomatis
/// membaca users terbaru dari database — bukan cache statis — sehingga
/// jika OWNER_ADMIN menonaktifkan akun tsb selagi offline, sesi otomatis
/// ditolak saat direstore.
class AuthNotifier extends StateNotifier<AuthState> {
  final UserRepository _userRepository;
  final SessionService _sessionService;

  AuthNotifier(this._userRepository, this._sessionService)
      : super(const AuthState(restoring: true)) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final username = await _sessionService.restoreSession();
      if (username != null) {
        final user = await _userRepository.getByUsername(username);
        if (user != null && user.isActive) {
          AuthService.instance.restoreSession(user);
          state = AuthState(user: user, restoring: false);
          return;
        }
        // Akun dihapus/dinonaktifkan OWNER_ADMIN selagi offline -> logout paksa.
        await _sessionService.clearSession();
      }
    } catch (_) {
      // Database belum siap / error baca sesi -> anggap belum login.
    }
    state = const AuthState(restoring: false);
  }

  Future<bool> login(String username, String password) async {
    final user = await AuthService.instance.login(username, password);
    if (user != null) {
      await _sessionService.saveSession(user.username);
    }
    state = AuthState(user: user, restoring: false);
    return user != null;
  }

  void logout() {
    AuthService.instance.logout();
    _sessionService.clearSession();
    state = const AuthState(restoring: false);
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(userRepositoryProvider), ref.watch(sessionServiceProvider));
});

/// Provider kompatibel dengan kode lama: user yang sedang login (null jika
/// belum login / masih restoring).
final authProvider = Provider<UserModel?>((ref) {
  return ref.watch(authStateProvider).user;
});

final authRestoringProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).restoring;
});

/// Notifier accessor lama (dipakai untuk .login()/.logout() dari UI).
final authNotifierProvider = Provider<AuthNotifier>((ref) {
  return ref.watch(authStateProvider.notifier);
});

final isOwnerAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(authProvider);
  return user?.isOwnerAdmin ?? false;
});

final daftarUserProvider = FutureProvider.autoDispose<List<UserModel>>((ref) async {
  final repo = ref.watch(userRepositoryProvider);
  return repo.getAll();
});
