import 'package:get_storage/get_storage.dart';

import 'constans.dart';

/// Persists the decoded `config.php` settings under a single stable key so
/// every screen (splash, home, reports) reads the same snapshot.
void saveAdConfig(Map<String, dynamic> config) {
  GetStorage().write(storageKeyAdConfig, config);
}

Map<String, dynamic>? readAdConfig() {
  final raw = GetStorage().read(storageKeyAdConfig);
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

/// Timestamp (ms) of the last successful impression, persisted so
/// `ad_min_interval_seconds` also holds across app restarts.
int? readAdLastShownAt() {
  final raw = GetStorage().read(storageKeyAdLastShownAt);
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

void saveAdLastShownAt(int millisecondsSinceEpoch) {
  GetStorage().write(storageKeyAdLastShownAt, millisecondsSinceEpoch);
}
