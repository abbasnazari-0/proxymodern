import '../models/ad_config.dart';

/// Everything the update screen needs, already resolved.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.forced,
    required this.title,
    required this.description,
    required this.updateUrl,
    required this.currentVersion,
    required this.latestVersion,
  });

  /// `true` = the app cannot be used until the new version is installed.
  final bool forced;
  final String title;
  final String description;

  /// Raw backend URL; may be empty or malformed.
  final String updateUrl;
  final String currentVersion;
  final String latestVersion;
}

/// Pure update decision logic (no Flutter/plugin dependencies).
///
/// Contract: the backend sends `version` (latest build number/versionName) and
/// `should_update` (`"true"`/`"false"` or `1`/`0`). An update is needed when
/// the announced version is newer than the installed one; it is mandatory when
/// [AdConfig.updateRequired] is true.
abstract final class AppUpdatePolicy {
  static AppUpdateInfo? evaluate({
    required AdConfig config,
    required String currentVersionName,
    required String currentBuildNumber,
  }) {
    final latest = config.version.trim();
    if (!_isNewer(
      latest: latest,
      currentVersionName: currentVersionName,
      currentBuildNumber: currentBuildNumber,
    )) {
      return null;
    }

    final forced = config.updateRequired;
    final appName = config.appName.trim().isNotEmpty
        ? config.appName.trim()
        : 'پروکسی مدرن';
    final title = config.updateTitle.isNotEmpty
        ? config.updateTitle
        : (forced ? 'به‌روزرسانی الزامی' : 'به‌روزرسانی جدید');
    final description = config.updateDesc.isNotEmpty
        ? config.updateDesc
        : (forced
            ? 'برای ادامهٔ استفاده از $appName، لطفاً نسخهٔ جدید را نصب کنید.'
            : 'نسخهٔ جدیدی از $appName منتشر شده است. برای استفاده از امکانات جدید، به‌روزرسانی کنید.');

    return AppUpdateInfo(
      forced: forced,
      title: title,
      description: description,
      updateUrl: config.updateUrl,
      currentVersion: _currentVersionLabel(
        currentVersionName,
        currentBuildNumber,
      ),
      latestVersion: latest,
    );
  }

  static bool _isNewer({
    required String latest,
    required String currentVersionName,
    required String currentBuildNumber,
  }) {
    if (latest.isEmpty) return false;

    // Build numbers are the primary contract.
    final latestBuild = int.tryParse(latest);
    final currentBuild = int.tryParse(currentBuildNumber.trim());
    if (latestBuild != null && currentBuild != null) {
      return latestBuild > currentBuild;
    }

    // A panel may publish `1.5.21`; compare numeric segments then.
    final latestParts = _numericParts(latest);
    final currentParts = _numericParts(currentVersionName);
    if (latestParts.isEmpty || currentParts.isEmpty) return false;

    final length = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;
    for (var i = 0; i < length; i++) {
      final left = i < latestParts.length ? latestParts[i] : 0;
      final right = i < currentParts.length ? currentParts[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  static List<int> _numericParts(String value) {
    return RegExp(r'\d+')
        .allMatches(value)
        .map((match) => int.tryParse(match.group(0)!) ?? 0)
        .toList(growable: false);
  }

  static String _currentVersionLabel(String name, String build) {
    final versionName = name.trim();
    final buildNumber = build.trim();
    if (versionName.isEmpty) return buildNumber;
    if (buildNumber.isEmpty) return versionName;
    return '$versionName ($buildNumber)';
  }
}
