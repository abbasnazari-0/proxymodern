import 'dart:math';

import 'get_storage_data.dart';

/// A stable, unique ID for this install/device.
///
/// Generated once (using a cryptographically secure random source) and then
/// persisted in GetStorage so it survives restarts.
class DeviceIdentifier {
  DeviceIdentifier._();

  static const _key = "device_unique_id";

  static String get id {
    final existing = GetStorageData.getData(_key);
    if (existing is String && existing.isNotEmpty) return existing;
    final generated = _generate();
    GetStorageData.writeData(_key, generated);
    return generated;
  }

  static String _generate() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16))
        .join();
  }
}
