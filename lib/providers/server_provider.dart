import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/server_config_service.dart';
import '../services/server_discovery_service.dart';
import '../services/server_status_service.dart';

final serverConfigServiceProvider = Provider<ServerConfigService>((ref) => ServerConfigService());
final serverDiscoveryServiceProvider = Provider<ServerDiscoveryService>((ref) => ServerDiscoveryService());
final serverStatusServiceProvider = Provider<ServerStatusService>((ref) => ServerStatusService());

/// Konfigurasi server tersimpan (host/port/token/mode). Dibaca semua role,
/// tapi HANYA OWNER_ADMIN yang boleh menulis lewat ServerScreen (dicek di
/// layer UI screen tsb, sesuai instruksi "role-based access" V4.2).
final serverConfigProvider = FutureProvider.autoDispose<ServerConfig>((ref) async {
  final service = ref.watch(serverConfigServiceProvider);
  return service.load();
});
