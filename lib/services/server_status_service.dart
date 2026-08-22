import 'dart:convert';
import 'package:http/http.dart' as http;

class ServerStatus {
  final bool online;
  final String? ip;
  final int? port;
  final String mode; // MANUAL | TMUX | AUTOBOOT
  final bool dbConnected;
  final int connectedDevices;

  const ServerStatus({
    required this.online,
    this.ip,
    this.port,
    this.mode = '-',
    this.dbConnected = false,
    this.connectedDevices = 0,
  });

  factory ServerStatus.offline() => const ServerStatus(online: false);

  factory ServerStatus.fromJson(Map<String, dynamic> json, {int? port}) {
    return ServerStatus(
      online: true,
      ip: json['ip'] as String?,
      port: json['port'] as int? ?? port,
      mode: json['mode'] as String? ?? '-',
      dbConnected: json['database'] == 'CONNECTED',
      connectedDevices: json['connected_devices'] as int? ?? 0,
    );
  }

  /// Label mode yang ramah ditampilkan di UI.
  String get modeLabel {
    switch (mode) {
      case 'TMUX':
        return 'Background (tmux)';
      case 'AUTOBOOT':
        return 'Auto Start (Termux:Boot)';
      case 'MANUAL':
        return 'Manual';
      default:
        return mode;
    }
  }
}

/// Client HTTP untuk cek status Termux Server (FastAPI) di jaringan lokal.
/// Wajib kirim header X-API-Token — server menolak request tanpa token
/// yang cocok (lihat garasi_server/server.py).
class ServerStatusService {
  Future<ServerStatus> checkStatus(String host, {int port = 8000, required String apiToken}) async {
    try {
      final uri = Uri.parse('http://$host:$port/status');
      final res = await http
          .get(uri, headers: {'X-API-Token': apiToken})
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        return ServerStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>, port: port);
      }
      return ServerStatus.offline();
    } catch (_) {
      return ServerStatus.offline();
    }
  }
}
