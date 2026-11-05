/// Models for the encrypted `config.php` response.
///
/// JSON keys stay exactly as the backend sends them so the payload can be
/// cached in GetStorage and parsed back without a translation layer.
library;

import 'dart:convert';

/// Where an ad unit is shown. [key] is the logical key used by the app; the
/// backend may spell it differently (`Interstitial_splash`,
/// `on_connect_Interstitial`, ...), which [AdConfig.findUnit] normalises.
enum AdSlot {
  splash('splash'),
  connect('connect'),
  banner('banner'),
  native('native'),
  rewarded('rewarded'),
  appOpen('open');

  const AdSlot(this.key);

  final String key;
}

/// One item of the backend `ad_units` array.
class AdUnitConfig {
  const AdUnitConfig({
    required this.key,
    required this.value,
    required this.enabled,
    this.comment = '',
  });

  factory AdUnitConfig.fromJson(Map<String, dynamic> json) {
    return AdUnitConfig(
      key: _asString(json['key']).trim(),
      value: _asString(json['value']).trim(),
      enabled: _asBool(json['enabled'], fallback: true),
      comment: _asString(json['comment']).trim(),
    );
  }

  /// Backend key for the slot (for example `Interstitialـsplash`).
  final String key;

  /// AdMob unit id (`ca-app-pub-.../...`).
  final String value;

  /// `enabled: 0` means the unit must never be shown, even if it is present.
  final bool enabled;

  /// Persian explanation from the panel (display/debug only).
  final String comment;

  bool get hasValidId => AdConfig.isValidAdUnitId(value);

  bool get isUsable => enabled && hasValidId;

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'enabled': enabled ? 1 : 0,
        'comment': comment,
      };
}

/// One relay (proxy) from the backend `relays` array.
class RelayConfig {
  const RelayConfig({
    required this.name,
    required this.url,
    this.proxyUsername = '',
    this.proxyPassword = '',
    this.proxyMode = '',
    this.proxyTtlSeconds = 0,
  });

  factory RelayConfig.fromJson(Map<String, dynamic> json) {
    return RelayConfig(
      name: _asString(json['name']).trim(),
      url: _asString(json['url']).trim(),
      proxyUsername: _asString(json['proxy_username']).trim(),
      proxyPassword: _asString(json['proxy_password']).trim(),
      proxyMode: _asString(json['proxy_mode']).trim(),
      proxyTtlSeconds: _asInt(json['proxy_ttl_seconds']),
    );
  }

  final String name;
  final String url;
  final String proxyUsername;
  final String proxyPassword;

  /// `sticky` (fixed exit IP, needs a verified session) or `rotation`.
  final String proxyMode;

  /// Lifetime requested from the proxy provider for a sticky session.
  final int proxyTtlSeconds;

  Uri? get uri => Uri.tryParse(url);

  bool get isSticky => proxyMode.trim().toLowerCase() == 'sticky';

  bool get hasCredentials =>
      proxyUsername.isNotEmpty && proxyPassword.isNotEmpty;

  /// The plugin accepts either both credentials or none.
  bool get hasValidCredentialsShape =>
      (proxyUsername.isEmpty && proxyPassword.isEmpty) || hasCredentials;

  /// Normalised URL for `MobileAdsConfig.proxyUrl`.
  ///
  /// The plugin requires a bare `http(s)://host:port`: the port must be
  /// explicit and path/query/fragment/user-info are not allowed. A relay URL
  /// that omits the port therefore gets the scheme default (443/80) instead of
  /// being silently dropped.
  String? get proxyUrl {
    final parsed = uri;
    if (parsed == null || parsed.host.isEmpty) return null;
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (parsed.userInfo.isNotEmpty) return null;
    final port = parsed.hasPort ? parsed.port : (scheme == 'https' ? 443 : 80);
    if (port < 1 || port > 65535) return null;
    final host = parsed.host.contains(':') ? '[${parsed.host}]' : parsed.host;
    return '$scheme://$host:$port';
  }

  bool get isValid => proxyUrl != null && hasValidCredentialsShape;

  /// `proxy_username` plus the sticky session suffix expected by the relay:
  /// `user-sid-<id>-ttl-<seconds>`. Rotation mode uses the plain username.
  String usernameWithSession(String? sessionId) {
    final session = (sessionId ?? '').trim();
    if (!isSticky || session.isEmpty) return proxyUsername;
    return '$proxyUsername-sid-$session-ttl-$proxyTtlSeconds';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'proxy_username': proxyUsername,
        'proxy_password': proxyPassword,
        'proxy_mode': proxyMode,
        'proxy_ttl_seconds': proxyTtlSeconds,
      };
}

/// The decoded `setting` object returned by `config.php`.
class AdConfig {
  const AdConfig({
    this.packageName = '',
    this.appName = '',
    this.appId = '',
    this.adMinIntervalSeconds = 0,
    this.adMaxPerSession = 0,
    this.adRetryCount = 0,
    this.adsStatus = 0,
    this.countryCode = '',
    this.languageCode = '',
    this.languageTags = const <String>[],
    this.networkOperatorCode = '',
    this.timezoneOffsetMinutes,
    this.version = '',
    this.updateTitle = '',
    this.updateDesc = '',
    this.updateUrl = '',
    this.shouldUpdate = false,
    this.forceUpdate,
    this.adUnits = const <AdUnitConfig>[],
    this.isIr = 0,
    this.visitorCountry = '',
    this.relays = const <RelayConfig>[],
    this.domains = const <String>[],
    this.legacyUnitIds = const <String, String>{},
  });

  factory AdConfig.fromJson(Map<String, dynamic> json) {
    final legacy = <String, String>{
      AdSlot.splash.key: _firstNonEmpty(<Object?>[
        json['interstitial_unit_id'],
        json['full_screen_ad_id'],
      ]),
      AdSlot.connect.key: _firstNonEmpty(<Object?>[
        json['connect_interstitial_unit_id'],
      ]),
      AdSlot.banner.key: _firstNonEmpty(<Object?>[json['banner_ad_id']]),
      AdSlot.native.key: _firstNonEmpty(<Object?>[json['native_ad_id']]),
      AdSlot.rewarded.key: _firstNonEmpty(<Object?>[json['rewarded_ad_id']]),
      AdSlot.appOpen.key: _firstNonEmpty(<Object?>[json['open_ad_id']]),
    }..removeWhere((_, value) => value.isEmpty);

    return AdConfig(
      packageName: _asString(json['package_name']).trim(),
      appName: _asString(json['app_name']).trim(),
      appId: _asString(json['app_id']).trim(),
      adMinIntervalSeconds: _asInt(json['ad_min_interval_seconds']),
      adMaxPerSession: _asInt(json['ad_max_per_session']),
      adRetryCount: _asInt(json['ad_retry_count']),
      adsStatus: _asInt(json['ads_status']),
      countryCode: _asString(json['country_code']).trim(),
      languageCode: _asString(json['language_code']).trim(),
      languageTags: _asStringList(json['language_tags']),
      networkOperatorCode: _asString(json['network_operator_code']).trim(),
      timezoneOffsetMinutes: _asOptionalInt(json['timezone_offset_minutes']),
      version: _asString(json['version']).trim(),
      updateTitle: _asString(json['update_title']).trim(),
      updateDesc: _asString(json['update_desc']).trim(),
      updateUrl: _asString(json['update_url']).trim(),
      shouldUpdate: _asBool(json['should_update']),
      forceUpdate:
          json['force_update'] == null ? null : _asBool(json['force_update']),
      adUnits: _adUnits(json['ad_units']),
      isIr: _asInt(json['is_ir']),
      visitorCountry: _asString(json['visitor_country']).trim(),
      relays: _relays(json['relays']),
      domains: normalizeBaseUrls(json['domains']),
      legacyUnitIds: Map<String, String>.unmodifiable(legacy),
    );
  }

  final String packageName;
  final String appName;
  final String appId;

  /// Minimum seconds between two *successful* impressions. `0` = no limit.
  final int adMinIntervalSeconds;

  /// Maximum impressions per app run. `0` = unlimited.
  final int adMaxPerSession;

  /// Retries after a failed load. `0` = exactly one attempt.
  final int adRetryCount;

  /// `0` turns every ad off, `1` turns them on.
  final int adsStatus;

  /// Country signal (only populated when [isIr] is 1).
  final String countryCode;

  /// Language signal (only populated when [isIr] is 1).
  final String languageCode;

  /// Ordered language tags (only populated when [isIr] is 1).
  final List<String> languageTags;

  /// `MCCMNC` / `MCC|MNC` operator signal (only when [isIr] is 1).
  final String networkOperatorCode;

  /// Timezone offset in minutes, **east positive** (Tehran = 210).
  final int? timezoneOffsetMinutes;

  /// Latest app version announced by the panel (build number or versionName).
  final String version;

  final String updateTitle;
  final String updateDesc;
  final String updateUrl;

  /// Backend flag: the update is mandatory when a newer version exists.
  final bool shouldUpdate;

  /// Optional explicit override used by newer panels.
  final bool? forceUpdate;

  final List<AdUnitConfig> adUnits;

  /// 1 = Iranian visitor (proxy on), 0 = rest of the world (direct SDK).
  final int isIr;

  /// Country the backend detected (reporting only).
  final String visitorCountry;

  /// Relay list; empty for non-Iranian visitors.
  final List<RelayConfig> relays;

  /// Backend mirrors, first item is the primary. May be empty.
  final List<String> domains;

  /// Older flat unit fields kept for backwards compatibility with plaintext
  /// responses. `ad_units` always wins when it contains the slot key.
  final Map<String, String> legacyUnitIds;

  bool get adsEnabled => adsStatus == 1;

  bool get isIranian => isIr == 1;

  bool get updateRequired => forceUpdate ?? shouldUpdate;

  List<RelayConfig> get usableRelays =>
      relays.where((relay) => relay.isValid).toList(growable: false);

  int get effectiveMinIntervalSeconds =>
      adMinIntervalSeconds < 0 ? 0 : adMinIntervalSeconds;

  int get effectiveMaxPerSession => adMaxPerSession < 0 ? 0 : adMaxPerSession;

  /// Total load attempts allowed by `ad_retry_count`, capped at 5.
  int get maxLoadAttempts => (adRetryCount + 1).clamp(1, 5).toInt();

  /// Finds the declared unit for [slotKey], tolerating spelling variants.
  AdUnitConfig? findUnit(String slotKey) {
    final normalized = normalizeAdUnitKey(slotKey);
    final aliases = _slotAliases[normalized] ?? <String>[normalized];
    for (final unit in adUnits) {
      if (aliases.contains(normalizeAdUnitKey(unit.key))) return unit;
    }

    // Second chance for panels whose key has an unexpected character: the
    // Persian comment is usually "اینترستیشیال اسپلش" / "اینترستیشیال اتصال".
    for (final unit in adUnits) {
      final hint = unit.comment.toLowerCase();
      if (normalized == 'splash' &&
          (hint.contains('splash') ||
              unit.comment.contains('اسپلش') ||
              unit.comment.contains('اسپلاش'))) {
        return unit;
      }
      if (normalized == 'connect' &&
          (hint.contains('connect') || unit.comment.contains('اتصال'))) {
        return unit;
      }
    }
    return null;
  }

  /// Usable unit id for [slot].
  ///
  /// A declared unit always decides: an `enabled: 0` unit is *not* replaced by
  /// a legacy/positional id. When the slot is absent from `ad_units`, the older
  /// flat backend field is used. As a final compatibility fallback for this
  /// two-unit app, an unrecognised two-item array is read in the documented
  /// order: splash first, connect second.
  String? unitIdFor(AdSlot slot) {
    final declared = findUnit(slot.key);
    if (declared != null) return declared.isUsable ? declared.value : null;

    final legacy = (legacyUnitIds[slot.key] ?? '').trim();
    if (isValidAdUnitId(legacy)) return legacy;

    if (adUnits.length == 2) {
      final index = slot == AdSlot.splash
          ? 0
          : slot == AdSlot.connect
              ? 1
              : -1;
      if (index >= 0) {
        final fallback = adUnits[index];
        if (fallback.isUsable) return fallback.value;
      }
    }
    return null;
  }

  static bool isValidAdUnitId(String value) =>
      _adUnitPattern.hasMatch(value.trim());

  static bool isValidAppId(String value) =>
      _appIdPattern.hasMatch(value.trim());

  Map<String, dynamic> toJson() {
    return {
      'package_name': packageName,
      'app_name': appName,
      'app_id': appId,
      'ad_min_interval_seconds': adMinIntervalSeconds,
      'ad_max_per_session': adMaxPerSession,
      'ad_retry_count': adRetryCount,
      'ads_status': adsStatus,
      'country_code': countryCode,
      'language_code': languageCode,
      'language_tags': languageTags,
      'network_operator_code': networkOperatorCode,
      'timezone_offset_minutes': timezoneOffsetMinutes,
      'version': version,
      'update_title': updateTitle,
      'update_desc': updateDesc,
      'update_url': updateUrl,
      'should_update': shouldUpdate,
      if (forceUpdate != null) 'force_update': forceUpdate,
      'ad_units': adUnits.map((unit) => unit.toJson()).toList(growable: false),
      'is_ir': isIr,
      'visitor_country': visitorCountry,
      'relays': relays.map((relay) => relay.toJson()).toList(growable: false),
      'domains': domains,
      if (legacyUnitIds[AdSlot.splash.key] != null)
        'interstitial_unit_id': legacyUnitIds[AdSlot.splash.key],
      if (legacyUnitIds[AdSlot.connect.key] != null)
        'connect_interstitial_unit_id': legacyUnitIds[AdSlot.connect.key],
    };
  }
}

/// Normalises an ad-unit key: removes the Arabic tatweel (`ـ`), lowercases and
/// strips separators. `Interstitialـsplash` and `on_connect_Interstitial`
/// therefore become `interstitialsplash` and `onconnectinterstitial`.
String normalizeAdUnitKey(String value) {
  return value
      .replaceAll('\u0640', '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

const Map<String, List<String>> _slotAliases = <String, List<String>>{
  'splash': <String>[
    'splash',
    'interstitialsplash',
    'splashinterstitial',
    'fullscreen',
    'fullscreeninterstitial',
  ],
  'connect': <String>[
    'connect',
    'onconnect',
    'connectinterstitial',
    'onconnectinterstitial',
  ],
  'banner': <String>['banner', 'bannerad'],
  'native': <String>['native', 'nativead'],
  'rewarded': <String>['rewarded', 'rewardedvideo', 'rewardedad'],
  'open': <String>['open', 'appopen', 'openad', 'appopenad'],
};

final RegExp _appIdPattern = RegExp(r'^ca-app-pub-\d{16}~\d{10}$');
final RegExp _adUnitPattern = RegExp(r'^ca-app-pub-\d{16}/\d{10}$');

/// `scheme://host[:port][/path]`, or `null` when [value] is not an http(s) URL.
String? normalizeBaseUrl(Object? value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  final host = uri.host.toLowerCase();
  if (!host.contains('.') && host != 'localhost') return null;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return '$scheme://$host$port$path';
}

/// Accepts a list, a JSON list string, or a comma-separated string. Invalid
/// entries are dropped, duplicates collapsed and the result capped at [max].
List<String> normalizeBaseUrls(Object? raw, {int max = 10}) {
  final result = <String>[];
  void add(Object? value) {
    final url = normalizeBaseUrl(value);
    if (url == null) return;
    if (result.any((existing) => existing.toLowerCase() == url.toLowerCase())) {
      return;
    }
    if (result.length >= max) return;
    result.add(url);
  }

  if (raw is List) {
    for (final entry in raw) {
      add(entry);
    }
  } else if (raw is String) {
    final text = raw.trim();
    if (text.startsWith('[')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          for (final entry in decoded) {
            add(entry);
          }
        }
      } catch (_) {
        // Malformed JSON: nothing usable.
      }
    } else {
      for (final part in text.split(',')) {
        add(part);
      }
    }
  }
  return List<String>.unmodifiable(result);
}

List<AdUnitConfig> _adUnits(Object? raw) {
  if (raw is! List) return const <AdUnitConfig>[];
  final result = <AdUnitConfig>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final unit = AdUnitConfig.fromJson(Map<String, dynamic>.from(entry));
    if (unit.key.isEmpty || unit.value.isEmpty) continue;
    result.add(unit);
  }
  return List<AdUnitConfig>.unmodifiable(result);
}

List<RelayConfig> _relays(Object? raw) {
  if (raw is! List) return const <RelayConfig>[];
  final result = <RelayConfig>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final relay = RelayConfig.fromJson(Map<String, dynamic>.from(entry));
    if (relay.url.isEmpty) continue;
    result.add(relay);
  }
  return List<RelayConfig>.unmodifiable(result);
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  if (value == null) return 0;
  return int.tryParse(value.toString().trim()) ?? 0;
}

int? _asOptionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

bool _asBool(Object? value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return fallback;
}

String _asString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

List<String> _asStringList(Object? value) {
  if (value is List) {
    return List<String>.unmodifiable(
      value
          .map((entry) => _asString(entry).trim())
          .where((entry) => entry.isNotEmpty),
    );
  }
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return const <String>[];
    if (text.startsWith('[')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) return _asStringList(decoded);
      } catch (_) {
        // Fall through to comma splitting.
      }
    }
    return List<String>.unmodifiable(
      text.split(',').map((entry) => entry.trim()).where((e) => e.isNotEmpty),
    );
  }
  return const <String>[];
}

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = _asString(value).trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}
