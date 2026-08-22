import 'package:shared_preferences/shared_preferences.dart';

/// Mode server — LOCAL (Termux di HP) atau VPS (nanti). Hanya field
/// konfigurasi yang berubah saat pindah ke VPS; API & database tetap sama.
enum ServerMode { local, vps }

extension ServerModeX on ServerMode {
  String get value => this == ServerMode.vps ? 'VPS' : 'LOCAL';

  static ServerMode fromValue(String? v) {
    return v == 'VPS' ? ServerMode.vps : ServerMode.local;
  }
}

class ServerConfig {
  final String host;
  final int port;
  final String token;
  final ServerMode mode;
  final DateTime? lastConnectedAt;

  const ServerConfig({
    required this.host,
    required this.port,
    required this.token,
    required this.mode,
    this.lastConnectedAt,
  });

  static const defaultToken = 'garasi_abah_bontot';
  static const defaultPort = 8000;

  factory ServerConfig.empty() => const ServerConfig(
        host: '',
        port: defaultPort,
        token: defaultToken,
        mode: ServerMode.local,
      );

  bool get isConfigured => host.isNotEmpty;

  ServerConfig copyWith({
    String? host,
    int? port,
    String? token,
    ServerMode? mode,
    DateTime? lastConnectedAt,
  }) {
    return ServerConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      mode: mode ?? this.mode,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }
}

/// Penyimpanan konfigurasi server PERMANEN di local storage (SharedPreferences).
/// Konfigurasi tetap ada walau app ditutup/di-restart/HP restart — bukan
/// state sementara di memori. Hanya OWNER_ADMIN yang boleh memanggil
/// [save] (dicek di layer UI/provider pemanggil, lihat ServerScreen).
class ServerConfigService {
  static const _kHost = 'server_host';
  static const _kPort = 'server_port';
  static const _kToken = 'server_token';
  static const _kMode = 'server_mode';
  static const _kLastConnected = 'server_last_connected_at';

  Future<ServerConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_kHost) ?? '';
    final port = prefs.getInt(_kPort) ?? ServerConfig.defaultPort;
    final token = prefs.getString(_kToken) ?? ServerConfig.defaultToken;
    final mode = ServerModeX.fromValue(prefs.getString(_kMode));
    final lastStr = prefs.getString(_kLastConnected);
    return ServerConfig(
      host: host,
      port: port,
      token: token,
      mode: mode,
      lastConnectedAt: lastStr != null ? DateTime.tryParse(lastStr) : null,
    );
  }

  Future<void> save(ServerConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, config.host);
    await prefs.setInt(_kPort, config.port);
    await prefs.setString(_kToken, config.token);
    await prefs.setString(_kMode, config.mode.value);
  }

  Future<void> markConnected(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, host);
    await prefs.setString(_kLastConnected, DateTime.now().toIso8601String());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHost);
    await prefs.remove(_kPort);
    await prefs.remove(_kToken);
    await prefs.remove(_kMode);
    await prefs.remove(_kLastConnected);
  }
}
