import 'package:package_info_plus/package_info_plus.dart';

import '../params/ad_backend.dart';

/// Small cache around [PackageInfo] so the version check, the config request
/// and the ad reports all read the same values without repeated platform calls.
abstract final class AppInfo {
  static PackageInfo? _info;

  static Future<void> ensureLoaded() async {
    if (_info != null) return;
    try {
      _info = await PackageInfo.fromPlatform();
    } catch (_) {
      // Platform channel unavailable (tests/CI): fall back to constants.
    }
  }

  static String get packageName {
    final value = _info?.packageName.trim() ?? '';
    return value.isEmpty ? AdBackend.packageName : value;
  }

  static String get buildNumber {
    final value = _info?.buildNumber.trim() ?? '';
    return value.isEmpty ? '0' : value;
  }

  static String get versionName => _info?.version.trim() ?? '';
}
