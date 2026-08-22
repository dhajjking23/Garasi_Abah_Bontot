import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'server_config_service.dart';

/// Auto Discovery — Viewer TIDAK PERNAH input IP manual. Alur:
/// 1. Coba host terakhir yang tersimpan (paling cepat, biasanya berhasil).
/// 2. Jika gagal, scan jaringan WiFi lokal (subnet dari IP device sendiri)
///    mencari server yang membalas /ping dan /status dengan token cocok.
/// Hanya relevan untuk SERVER_MODE = LOCAL. Mode VPS pakai host tetap
/// (domain/IP publik) sehingga tidak perlu discovery jaringan lokal.
class ServerDiscoveryService {
  final ServerConfigService _configService = ServerConfigService();

  /// Return host yang berhasil ditemukan (IP), atau null jika gagal total.
  Future<String?> discover(ServerConfig config, {Duration timeout = const Duration(milliseconds: 800)}) async {
    if (config.mode == ServerMode.vps) {
      // Mode VPS: host tetap, tidak perlu scan jaringan lokal.
      final ok = await _ping(config.host, config.port, timeout: timeout);
      return ok ? config.host : null;
    }

    // 1) Coba host tersimpan dulu
    if (config.host.isNotEmpty && await _ping(config.host, config.port, timeout: timeout)) {
      await _configService.markConnected(config.host);
      return config.host;
    }

    // 2) Scan subnet lokal dari IP device sendiri
    final subnet = await _getLocalSubnetPrefix();
    if (subnet == null) return null;

    final found = await _scanSubnet(subnet, config.port, timeout: timeout);
    if (found != null) {
      await _configService.markConnected(found);
    }
    return found;
  }

  Future<bool> _ping(String host, int port, {required Duration timeout}) async {
    if (host.isEmpty) return false;
    try {
      final uri = Uri.parse('http://$host:$port/ping');
      final res = await http.get(uri).timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Ambil prefix subnet (mis. "192.168.1") dari alamat IPv4 device di
  /// jaringan WiFi/lokal yang sedang aktif.
  Future<String?> _getLocalSubnetPrefix() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          final isPrivate = ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.');
          if (!addr.isLoopback && isPrivate) {
            final parts = ip.split('.');
            if (parts.length == 4) {
              return '${parts[0]}.${parts[1]}.${parts[2]}';
            }
          }
        }
      }
    } catch (_) {
      // Tidak ada izin / interface tidak ditemukan
    }
    return null;
  }

  /// Scan 1-254 di subnet secara paralel terbatas, hentikan begitu ketemu.
  Future<String?> _scanSubnet(String subnetPrefix, int port, {required Duration timeout}) async {
    const concurrency = 32;
    final completer = Completer<String?>();
    var nextHost = 1;
    var finished = false;

    void tryComplete(String? result) {
      if (!finished) {
        finished = true;
        completer.complete(result);
      }
    }

    Future<void> worker() async {
      while (!finished) {
        if (nextHost > 254) {
          break;
        }
        final host = nextHost++;
        final ip = '$subnetPrefix.$host';
        final ok = await _ping(ip, port, timeout: timeout);
        if (ok) {
          tryComplete(ip);
          return;
        }
      }
    }

    final workers = <Future<void>>[];
    for (var i = 0; i < concurrency; i++) {
      workers.add(worker());
    }

    Future.wait(workers).then((_) => tryComplete(null));

    return completer.future;
  }
}
