import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../models/ad_config.dart';
import '../params/ad_backend.dart';
import 'ad_cap_policy.dart';
import 'ad_config_api.dart';
import 'ad_config_store.dart';
import 'ad_report_service.dart';
import 'app_info.dart';
import 'domain_resolver.dart';
import 'relay_selector.dart';

/// Singleton that owns the ad config, relay selection, capping and the
/// Google Mobile Ads (relay) plugin.
///
/// Boot order used by the splash screen:
/// 1. [loadCachedConfig] — last launch's snapshot.
/// 2. [refreshConfigFromBackend] — signed + AES-GCM config with domain
///    failover.
/// 3. [init] — fastest relay (IR) or direct SDK (rest of the world).
/// 4. [showSplashAd] — splash interstitial; the connect unit is preloaded right
///    after the splash ad is dismissed.
class MobileAdsService {
  MobileAdsService._({AdConfigApi? api, RelaySelector? relaySelector})
      : _api = api ?? AdConfigApi(),
        _relaySelector = relaySelector ?? RelaySelector();

  static final MobileAdsService instance = MobileAdsService._();

  @visibleForTesting
  static MobileAdsService createForTests({
    AdConfigApi? api,
    RelaySelector? relaySelector,
  }) =>
      MobileAdsService._(api: api, relaySelector: relaySelector);

  /// Maximum time a single SDK load may take before the retry loop moves on.
  static const Duration loadTimeout = Duration(seconds: 20);

  /// Maximum time `start()` may take (fast relay + SDK initialization).
  static const Duration startTimeout = Duration(seconds: 25);

  final AdConfigApi _api;
  final RelaySelector _relaySelector;

  AdConfig _config = const AdConfig();
  AdStatus? _status;
  bool _initialized = false;
  bool _sdkReady = false;
  bool _showing = false;

  RelayConfig? _selectedRelay;
  List<RelayProbe> _relayProbes = const <RelayProbe>[];
  List<RelayConfig> _rankedRelays = const <RelayConfig>[];
  int _relayIndex = 0;
  String? _activeBaseUrl;

  String? _loadedUnitId;
  String? _loadedUnitKey;

  DateTime? _lastAdShownAt;
  int _adsShownThisSession = 0;

  String _lastError = '';
  String? _blockedReason;

  Future<bool>? _startFuture;
  Future<bool>? _loadFuture;
  Future<bool>? _refreshFuture;
  Timer? _configRetryTimer;

  // ---------------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------------

  AdConfig get config => _config;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  bool get adsEnabled => isSupported && _config.adsEnabled;

  bool get adsStatusOn => _config.adsStatus == 1;

  bool get isIranian => _config.isIranian;

  /// Proxy mode is only used for Iranian visitors with ads switched on.
  bool get usesProxy => adsEnabled && _config.isIranian;

  bool get isInitialized => _initialized;

  bool get isSdkReady => _sdkReady;

  bool get isShowingAd => _showing;

  bool get isAdLoaded => _loadedUnitId != null;

  /// True only when the held interstitial belongs to the connect slot.
  bool get isConnectAdLoaded =>
      _loadedUnitId != null && _loadedUnitKey == AdSlot.connect.key;

  String? get loadedUnitKey => _loadedUnitKey;

  RelayConfig? get selectedRelay => _selectedRelay;

  List<RelayProbe> get relayProbes =>
      List<RelayProbe>.unmodifiable(_relayProbes);

  String? get activeBaseUrl => _activeBaseUrl;

  String get lastError => _lastError;

  String? get blockedReason => _blockedReason;

  int get adsShownThisSession => _adsShownThisSession;

  DateTime? get lastAdShownAt => _lastAdShownAt;

  AdCapPolicy get capPolicy => AdCapPolicy(
        minIntervalSeconds: _config.effectiveMinIntervalSeconds,
        maxPerSession: _config.effectiveMaxPerSession,
        shownCount: _adsShownThisSession,
        lastShownAt: _lastAdShownAt,
      );

  bool get canShowNow => adsEnabled && !_showing && capPolicy.canRequest;

  bool get hasConnectUnit => unitIdFor(AdSlot.connect) != null;

  String? unitIdFor(AdSlot slot) => _config.unitIdFor(slot);

  String? get debugCountrySignal => _signalCountry;

  int? get debugTimezoneSignal => _signalTimezoneOffset;

  String? get debugOperatorSignal => _signalOperator;

  // ---------------------------------------------------------------------------
  // Config lifecycle
  // ---------------------------------------------------------------------------

  /// Reads the snapshot saved by the previous run. Never touches the network.
  Future<void> loadCachedConfig() async {
    await AppInfo.ensureLoaded();
    Map<String, dynamic>? raw;
    try {
      raw = readAdConfig();
    } catch (error) {
      debugPrint('[Ads] reading cached config failed -> $error');
      return;
    }
    if (raw == null || raw.isEmpty) {
      debugPrint('[Ads] no cached config');
      return;
    }

    final cachedPackage = (raw['package_name'] ?? '').toString().trim();
    if (cachedPackage.isNotEmpty && cachedPackage != AppInfo.packageName) {
      debugPrint('[Ads] ignoring cache for package "$cachedPackage"');
      return;
    }

    try {
      applyConfig(AdConfig.fromJson(raw), persist: false);
      _restoreLastShown();
      debugPrint(
          '[Ads] cached config loaded (ads_status=${_config.adsStatus})');
    } catch (error) {
      _lastError = error.toString();
      debugPrint('[Ads] cached config is invalid -> $error');
    }
  }

  /// Fetches a fresh `config.php`, decrypts it, applies and caches it.
  ///
  /// Always runs on launch. When every mirror fails, the cached config remains
  /// active and a retry is scheduled after [AdBackend.domainRetryDelay].
  Future<bool> refreshConfigFromBackend() {
    final inflight = _refreshFuture;
    if (inflight != null) return inflight;

    final future = _refreshConfigFromBackend();
    _refreshFuture = future;
    future.then<void>(
      (_) {
        if (identical(_refreshFuture, future)) _refreshFuture = null;
      },
      onError: (Object _) {
        if (identical(_refreshFuture, future)) _refreshFuture = null;
      },
    );
    return future;
  }

  Future<bool> _refreshConfigFromBackend() async {
    _configRetryTimer?.cancel();
    _configRetryTimer = null;
    await AppInfo.ensureLoaded();

    final signals = await _readDeviceSignals();
    final candidates = DomainResolver.instance.order(_config.domains);

    try {
      final result = await _api.fetchSetting(
        packageName: AppInfo.packageName,
        version: AppInfo.buildNumber,
        candidates: candidates,
        tz: signals.tz,
        op: signals.op,
      );

      final fresh = AdConfig.fromJson(result.setting);
      if (result.setting.isEmpty) {
        throw const AdBackendException('config.php returned an empty setting');
      }

      _activeBaseUrl = result.baseUrl;
      applyConfig(fresh);

      final published =
          fresh.domains.isNotEmpty ? fresh.domains : <String>[result.baseUrl];
      DomainResolver.instance.save(published, result.baseUrl);

      debugPrint(
        '[Ads] config applied: is_ir=${fresh.isIr} ads_status=${fresh.adsStatus} '
        'units=${fresh.adUnits.length} relays=${fresh.relays.length} '
        'domains=${published.length}',
      );

      // A retry that arrives after the splash has already given up should still
      // bring ads up (for example a first launch with a blocked network).
      if (_initialized && fresh.adsEnabled && !_sdkReady) {
        unawaited(init());
      }
      return true;
    } catch (error) {
      _lastError = error.toString();
      debugPrint('[Ads] config refresh failed -> $error');
      for (final candidate in candidates) {
        DomainResolver.instance.markBad(candidate);
      }
      _scheduleConfigRetry();
      return false;
    }
  }

  void _scheduleConfigRetry() {
    _configRetryTimer?.cancel();
    _configRetryTimer = Timer(AdBackend.domainRetryDelay, () {
      _configRetryTimer = null;
      unawaited(refreshConfigFromBackend());
    });
    debugPrint(
      '[Ads] every backend domain failed; retrying in '
      '${AdBackend.domainRetryDelay.inSeconds}s',
    );
  }

  /// Applies a parsed config in memory and (by default) persists it.
  void applyConfig(AdConfig config, {bool persist = true}) {
    _config = config;
    debugPrint(
      '[Ads] units: '
      '${config.adUnits.map((unit) => '${unit.key}(enabled=${unit.enabled}, id=${_shortUnitId(unit.value)})').join(' | ')}',
    );
    debugPrint(
      '[Ads] resolved splash=${_shortUnitId(config.unitIdFor(AdSlot.splash))} '
      'connect=${_shortUnitId(config.unitIdFor(AdSlot.connect))}',
    );

    final testUnits = config.adUnits
        .where((unit) => unit.value.contains('3940256099942544'))
        .map((unit) => unit.key)
        .toList(growable: false);
    if (testUnits.isNotEmpty) {
      debugPrint(
        '[Ads] WARNING: backend is serving Google TEST ad units for: '
        '${testUnits.join(', ')}',
      );
    }
    final declaredSplash = config.findUnit(AdSlot.splash.key);
    if (declaredSplash != null && !declaredSplash.enabled) {
      debugPrint('[Ads] splash unit is disabled by backend (enabled=0)');
    }
    _configureReporter();
    _restoreLastShown();

    if (persist) {
      try {
        saveAdConfig(config.toJson());
      } catch (error) {
        debugPrint('[Ads] saving config failed -> $error');
      }
    }

    if (!config.adsEnabled && _sdkReady) {
      unawaited(stop());
    }
  }

  void _configureReporter() {
    final base = _activeBaseUrl ??
        DomainResolver.instance.lastGood ??
        AdBackend.defaultBaseUrl;
    AdReportService.instance.configure(
      apiKey: AdBackend.apiKey,
      package: AppInfo.packageName,
      reportUrl: '$base${AdBackend.reportPath}',
    );
  }

  void _restoreLastShown() {
    if (_lastAdShownAt != null) return;
    try {
      final millis = readAdLastShownAt();
      if (millis != null && millis > 0) {
        _lastAdShownAt = DateTime.fromMillisecondsSinceEpoch(millis);
      }
    } catch (error) {
      debugPrint('[Ads] restoring last-shown time failed -> $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Device signals + SDK start
  // ---------------------------------------------------------------------------

  /// `tz` (east positive) and `op` (`MCC|MNC`) signed with every request.
  Future<({String tz, String op})> _readDeviceSignals() async {
    var tz = DateTime.now().timeZoneOffset.inMinutes;
    var operator = '';

    if (isSupported) {
      try {
        final signals = await MobileAds.instance.deviceSignals();
        final rawTz = signals['tzOffset'];
        // The plugin returns 0 both for UTC and when the platform call fails;
        // keep the DateTime-derived value in the latter case.
        if (rawTz is num && rawTz != 0) tz = rawTz.toInt();
        final rawOperator = signals['operator'];
        if (rawOperator is String) operator = rawOperator;
      } catch (error) {
        debugPrint('[Ads] deviceSignals failed -> $error');
      }
    }

    return (
      tz: normalizeTimezoneOffset(tz).toString(),
      op: normalizeOperatorForSignature(operator),
    );
  }

  /// Starts the SDK (and the relay for Iranian visitors). Safe to call again.
  Future<bool> init() {
    _initialized = true;
    _restoreLastShown();

    if (!adsEnabled) {
      _blockedReason =
          _config.adsStatus != 1 ? 'ads_status_off' : 'unsupported_platform';
      debugPrint('[Ads] init skipped ($_blockedReason)');
      return Future<bool>.value(false);
    }

    final inflight = _startFuture;
    if (inflight != null) return inflight;

    final future = _startInternal();
    _startFuture = future;
    future.then<void>(
      (_) {
        if (identical(_startFuture, future)) _startFuture = null;
      },
      onError: (Object _) {
        if (identical(_startFuture, future)) _startFuture = null;
      },
    );
    return future;
  }

  Future<bool> _startInternal() async {
    if (!adsEnabled) return false;

    if (_config.isIranian) {
      final relays = _config.usableRelays;
      if (relays.isEmpty) {
        _blockedReason = 'no_relays';
        debugPrint('[Ads] is_ir=1 but the backend sent no usable relay');
        return false;
      }

      final probes = await _relaySelector.rank(relays);
      _relayProbes = probes;
      if (probes.isEmpty) {
        _blockedReason = 'relays_unreachable';
        debugPrint('[Ads] no relay passed the TLS probe to Google');
        return false;
      }

      final ranked = probes.map((probe) => probe.relay).toList(growable: false);
      _rankedRelays = ranked;
      for (var index = 0; index < ranked.length; index++) {
        final relay = ranked[index];
        debugPrint(
          '[Ads] relay '
          '${relay.name.isEmpty ? relay.url : relay.name} '
          '-> ${probes[index].latency!.inMilliseconds}ms',
        );
        if (await _tryStart(relay)) {
          _selectedRelay = relay;
          _relayIndex = index;
          _blockedReason = null;
          return true;
        }
      }

      _blockedReason = 'proxy_start_failed';
      return false;
    }

    _rankedRelays = const <RelayConfig>[];
    _relayIndex = 0;
    _selectedRelay = null;
    final started = await _tryStart(null);
    _blockedReason = started ? null : 'sdk_start_failed';
    return started;
  }

  String get _effectiveAppId => AdConfig.isValidAppId(_config.appId)
      ? _config.appId
      : AdBackend.adMobAppId;

  Future<bool> _tryStart(RelayConfig? relay) async {
    final expectedEndpoint = relay?.proxyUrl ?? '';
    if (await _adoptRunningSession(expectedEndpoint)) {
      if (relay != null) _selectedRelay = relay;
      return true;
    }

    try {
      var username = relay?.proxyUsername ?? '';
      if (relay != null && relay.isSticky) {
        final sessionId = await _api.fetchVerifiedSession(
          packageName: AppInfo.packageName,
          relayName: relay.name,
          candidates: DomainResolver.instance.order(_config.domains),
        );
        if (sessionId.isNotEmpty) {
          username = relay.usernameWithSession(sessionId);
        }
        debugPrint(
          '[Ads] sticky session for ${relay.name}: '
          '${sessionId.isEmpty ? "fallback to plain username" : "verified"}',
        );
      }

      final withCredentials = relay != null &&
          username.isNotEmpty &&
          relay.proxyPassword.isNotEmpty;
      final adsConfig = MobileAdsConfig(
        appId: _effectiveAppId,
        // `is_ir` is the plugin's proxy switch: true routes the SDK through
        // `proxyUrl`; false keeps the plain SDK with device signals.
        is_ir: relay != null,
        endpoints: const <String>[],
        writeTimeout: const Duration(seconds: 60),
        proxyUrl: relay?.proxyUrl,
        proxyUsername: withCredentials ? username : null,
        proxyPassword: withCredentials ? relay.proxyPassword : null,
      );

      AdStatus value;
      try {
        value = await MobileAds.instance.start(adsConfig).timeout(startTimeout);
      } catch (error) {
        // A previous native session may still be open after a hot restart.
        if (!_isSessionAlreadyRunningError(error.toString())) rethrow;
        debugPrint('[Ads] session already open; stopping and retrying start');
        await _stopQuietly();
        value = await MobileAds.instance.start(adsConfig).timeout(startTimeout);
      }

      _status = value;
      _sdkReady = value.state == AdState.ready || value.state == AdState.loaded;
      if (!_sdkReady) {
        _lastError = 'start state=${value.state.name} ${value.lastError}';
      }
      debugPrint(
        '[Ads] start status: state=${value.state.name} '
        'endpoint=${value.endpoint} lastError=${value.lastError}',
      );
      debugPrint(
        '[Ads] start ${relay == null ? "direct" : "proxy ${relay.proxyUrl}"} '
        '-> ${value.state.name}',
      );
      return _sdkReady;
    } catch (error) {
      _sdkReady = false;
      _lastError = error.toString();
      debugPrint('[Ads] start failed -> $error');
      return false;
    }
  }

  /// Reuses a native session that is already running (hot restart / retry).
  Future<bool> _adoptRunningSession(String expectedEndpoint) async {
    final status = await _freshStatus();
    if (status == null) return false;

    final running = status.state == AdState.ready ||
        status.state == AdState.loaded ||
        status.state == AdState.showing;
    if (!running) return false;

    final expected = normalizeBaseUrl(expectedEndpoint);
    final actual = normalizeBaseUrl(status.endpoint);
    if (expectedEndpoint.isEmpty) {
      // Direct mode must not silently adopt a proxied session.
      if (actual != null && actual.isNotEmpty) {
        debugPrint('[Ads] running session is proxied; restarting direct');
        return false;
      }
    } else if (expected == null || actual == null || expected != actual) {
      debugPrint(
        '[Ads] running session endpoint $actual != expected $expected; '
        'restarting',
      );
      return false;
    }

    _status = status;
    _sdkReady = true;
    _lastError = '';
    debugPrint('[Ads] reusing running SDK session (${status.state.name})');
    return true;
  }

  static bool _isSessionAlreadyRunningError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('stop the current session') ||
        lower.contains('already started') ||
        lower.contains('already running');
  }

  Future<AdStatus?> _freshStatus() async {
    if (!isSupported) return null;
    try {
      return await MobileAds.instance.getStatus();
    } catch (error) {
      debugPrint('[Ads] getStatus failed -> $error');
      return null;
    }
  }

  Future<AdStatus?> _safeStatus() async {
    try {
      return await MobileAds.instance.getStatus();
    } catch (_) {
      return _status;
    }
  }

  Future<void> _stopQuietly() async {
    try {
      _status = await MobileAds.instance.stop();
    } catch (error) {
      debugPrint('[Ads] stop failed -> $error');
    } finally {
      _sdkReady = false;
      _clearLoadedUnit();
    }
  }

  /// Releases the proxy route and the cached ad. [init] can run again after.
  Future<void> stop() async {
    _clearLoadedUnit();
    if (!isSupported) {
      _sdkReady = false;
      _selectedRelay = null;
      return;
    }
    if (_sdkReady) {
      await _stopQuietly();
    }
    _selectedRelay = null;
  }

  // ---------------------------------------------------------------------------
  // Signals passed to the SDK (IR proxy mode only)
  // ---------------------------------------------------------------------------

  /// Applies the exact sanitized signals for the next load.
  ///
  /// The plugin merges non-null values with previous metadata, so direct mode
  /// explicitly clears everything to avoid leaking Iranian signals after a
  /// region change.
  void _applySignals() {
    if (!_config.isIranian) {
      MobileAds.instance.setAppMetadata(AdMetadata());
      return;
    }
    MobileAds.instance.setAppMetadata(
      AdMetadata(
        countryCode: _signalCountry,
        languageCode: _signalLanguage,
        languageTags: _signalLanguageTags,
        timezoneOffsetMinutes: _signalTimezoneOffset,
        networkOperatorCode: _signalOperator,
      ),
    );
  }

  String? get _signalCountry {
    if (!_config.isIranian) return null;
    final value = _config.countryCode.trim();
    return RegExp(r'^[A-Za-z]{2}$').hasMatch(value)
        ? value.toUpperCase()
        : null;
  }

  String? get _signalLanguage {
    if (!_config.isIranian) return null;
    final value = _config.languageCode.trim();
    return RegExp(r'^[A-Za-z]{2,3}$').hasMatch(value)
        ? value.toLowerCase()
        : null;
  }

  List<String>? get _signalLanguageTags {
    if (!_config.isIranian) return null;
    final tags = _config.languageTags
        .map((tag) => tag.trim())
        .where(
          (tag) => RegExp(
            r'^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$',
          ).hasMatch(tag),
        )
        .toList(growable: false);
    return tags.isEmpty ? null : tags;
  }

  /// The backend sends minutes **east positive** (Tehran = 210), while the
  /// plugin's `AdMetadata.timezoneOffsetMinutes` uses the JavaScript
  /// `Date.getTimezoneOffset` convention (west positive), so the sign flips.
  int? get _signalTimezoneOffset {
    if (!_config.isIranian) return null;
    final eastPositive = _config.timezoneOffsetMinutes;
    if (eastPositive == null) return null;
    if (eastPositive < -840 || eastPositive > 840) return null;
    return -eastPositive;
  }

  String? get _signalOperator {
    if (!_config.isIranian) return null;
    final digits = _config.networkOperatorCode.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return digits.length == 5 || digits.length == 6 ? digits : null;
  }

  // ---------------------------------------------------------------------------
  // Public ad entry points
  // ---------------------------------------------------------------------------

  /// Splash interstitial.
  ///
  /// The plugin holds one interstitial at a time, so the connect unit is
  /// preloaded immediately after the splash ad is dismissed. From the user's
  /// point of view both units are prepared during the splash flow; the connect
  /// one is simply not requested while the splash ad still occupies the slot.
  Future<void> showSplashAd() async {
    if (!adsEnabled) return;

    final unitId = unitIdFor(AdSlot.splash);
    if (unitId == null) {
      debugPrint('[Ads] no enabled splash unit; skipping');
      unawaited(preloadConnectAd());
      return;
    }
    if (!canShowNow) {
      debugPrint('[Ads] splash ad skipped by capping');
      unawaited(preloadConnectAd());
      return;
    }

    try {
      final loaded = await _ensureLoaded(AdSlot.splash, unitId);
      if (loaded) await _present(AdSlot.splash);
    } catch (error) {
      _lastError = error.toString();
      debugPrint('[Ads] splash ad failed -> $error');
    } finally {
      // Start the connect unit during the splash flow, as requested. The
      // plugin holds one interstitial at a time, so this can only start after
      // the splash ad has been consumed. A bounded wait keeps a slow load from
      // blocking app entry; the channel screen waits for the rest if needed.
      try {
        await preloadConnectAd().timeout(const Duration(seconds: 8));
      } catch (error) {
        debugPrint('[Ads] connect preload during splash failed -> $error');
      }
    }
  }

  /// Loads the connect interstitial in advance (no show).
  ///
  /// Loading is only limited by the per-session cap; the time interval is
  /// enforced at show time, so an early preload can wait for its turn.
  Future<bool> preloadConnectAd() async {
    if (!adsEnabled) return false;
    if (!capPolicy.hasSessionCapacity) return false;

    final unitId = unitIdFor(AdSlot.connect);
    if (unitId == null) return false;
    if (_loadedUnitId == unitId && _loadedUnitKey == AdSlot.connect.key) {
      return true;
    }
    if (_loadedUnitId != null) {
      // One ad is already held (splash is showing or about to show). Never
      // overwrite it; the connect unit is requested right after it is consumed.
      return false;
    }
    return _ensureLoaded(AdSlot.connect, unitId);
  }

  /// Shows the connect interstitial (loads it first if needed).
  Future<bool> showConnectAd() async {
    if (!canShowNow) {
      debugPrint('[Ads] connect ad skipped by capping');
      return false;
    }

    final unitId = unitIdFor(AdSlot.connect);
    if (unitId == null) return false;

    final loaded = await _ensureLoaded(AdSlot.connect, unitId);
    if (!loaded) return false;

    final shown = await _present(AdSlot.connect);
    if (shown) unawaited(preloadConnectAd());
    return shown;
  }

  // ---------------------------------------------------------------------------
  // Load / show internals
  // ---------------------------------------------------------------------------

  Future<bool> _ensureLoaded(AdSlot slot, String unitId) async {
    if (_loadedUnitId == unitId && _loadedUnitKey == slot.key) return true;
    if (_loadedUnitId != null && _loadedUnitId != unitId) return false;

    // The native SDK may already hold an ad (hot restart, or a timed-out load
    // that finished late). Adopt it instead of sending a duplicate request.
    if (await _adoptLoadedAd(slot, unitId)) return true;

    final inflight = _loadFuture;
    if (inflight != null) {
      await inflight;
      return _loadedUnitId == unitId && _loadedUnitKey == slot.key;
    }

    final future = _loadWithRetry(slot, unitId);
    _loadFuture = future;
    future.then<void>(
      (_) {
        if (identical(_loadFuture, future)) _loadFuture = null;
      },
      onError: (Object _) {
        if (identical(_loadFuture, future)) _loadFuture = null;
      },
    );
    return future;
  }

  Future<bool> _loadWithRetry(AdSlot slot, String unitId) async {
    if (!adsEnabled) return false;
    if (!capPolicy.hasSessionCapacity) {
      debugPrint('[Ads] load ${slot.key} skipped (session cap reached)');
      return false;
    }

    // `ad_retry_count` is retries, so total attempts = retry + 1 (max 5).
    final attempts = _config.maxLoadAttempts;
    var attempt = 1;
    var relaySwitches = 0;
    // Switching relays is independent of ad_retry_count: a relay that passes
    // CONNECT but cannot carry TLS would otherwise waste every retry.
    final maxRelaySwitches =
        isIranian && _rankedRelays.length > 1 ? _rankedRelays.length - 1 : 0;

    while (attempt <= attempts) {
      if (!capPolicy.hasSessionCapacity) return false;
      if (!_sdkReady && !await init()) return false;

      final stopwatch = Stopwatch()..start();
      try {
        _applySignals();
        debugPrint('[Ads] load ${slot.key} (attempt $attempt/$attempts)');
        final value = await MobileAds.instance
            .loadInterstitial(
              adUnitId: unitId,
              countryCode: _config.isIranian ? _signalCountry : null,
              languageCode: _config.isIranian ? _signalLanguage : null,
              languageTags: _config.isIranian ? _signalLanguageTags : null,
              timezoneOffsetMinutes:
                  _config.isIranian ? _signalTimezoneOffset : null,
              networkOperatorCode: _config.isIranian ? _signalOperator : null,
            )
            .timeout(loadTimeout);
        stopwatch.stop();
        _status = value;

        if (value.adReady) {
          _loadedUnitId = unitId;
          _loadedUnitKey = slot.key;
          _lastError = '';
          _report(
            event: 'load_success',
            slot: slot,
            latencyMs: stopwatch.elapsedMilliseconds,
            attempt: attempt,
            maxAttempts: attempts,
          );
          return true;
        }

        _lastError =
            value.lastError.isNotEmpty ? value.lastError : 'AD_NOT_READY';
        _report(
          event: 'load_fail',
          slot: slot,
          error: AdReportService.classifyError(_lastError),
          message: _lastError,
          latencyMs: stopwatch.elapsedMilliseconds,
          attempt: attempt,
          maxAttempts: attempts,
        );

        if (_isNetworkAdError(_lastError) &&
            relaySwitches < maxRelaySwitches &&
            await _switchToNextRelay()) {
          relaySwitches++;
          continue;
        }
      } catch (error) {
        stopwatch.stop();
        _lastError = error.toString();

        if (_isAlreadyLoadedError(_lastError)) {
          if (await _adoptLoadedAd(
            slot,
            unitId,
            attempt: attempt,
            maxAttempts: attempts,
          )) {
            return true;
          }
          break;
        }

        _report(
          event: 'load_fail',
          slot: slot,
          error: AdReportService.classifyError(_lastError),
          message: _lastError,
          latencyMs: stopwatch.elapsedMilliseconds,
          attempt: attempt,
          maxAttempts: attempts,
        );
        debugPrint('[Ads] load ${slot.key} attempt $attempt failed -> $error');

        if (_isNetworkAdError(_lastError) &&
            relaySwitches < maxRelaySwitches &&
            await _switchToNextRelay()) {
          relaySwitches++;
          // Same attempt number, fresh relay: do not consume a retry.
          continue;
        }
      }

      if (attempt < attempts) {
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
      attempt++;
    }

    _clearLoadedUnit();
    return false;
  }

  /// `true` when the plugin rejected a load because an ad is already cached.
  static bool _isAlreadyLoadedError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('already available') ||
        lower.contains('already loaded');
  }

  /// Network/TLS failures that can be fixed by trying another relay.
  static bool _isNetworkAdError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('network_error') ||
        lower.contains('err_connection_closed') ||
        lower.contains('internalerrorcode=-100') ||
        lower.contains('ssl') ||
        lower.contains('handshake') ||
        lower.contains('timeout') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('net_error');
  }

  /// Stops the current proxy session and starts the next TLS-valid relay.
  ///
  /// Returns `true` only when a new relay reached the ready state. A failed
  /// switch leaves `_sdkReady` false and the caller can still report the
  /// original load failure.
  Future<bool> _switchToNextRelay() async {
    if (!isIranian || _rankedRelays.length < 2) return false;

    for (var step = 1; step < _rankedRelays.length; step++) {
      final nextIndex = (_relayIndex + step) % _rankedRelays.length;
      final relay = _rankedRelays[nextIndex];
      debugPrint(
        '[Ads] network error through '
        '${_selectedRelay?.name ?? '-'}; switching relay -> '
        '${relay.name.isEmpty ? relay.url : relay.name}',
      );
      await _stopQuietly();
      if (await _tryStart(relay)) {
        _selectedRelay = relay;
        _relayIndex = nextIndex;
        _blockedReason = null;
        return true;
      }
    }
    return false;
  }

  /// Takes over the ad the native slot already holds (single-slot plugin).
  Future<bool> _adoptLoadedAd(
    AdSlot slot,
    String unitId, {
    int attempt = 1,
    int maxAttempts = 1,
  }) async {
    final status = await _freshStatus();
    if (status == null || !status.adReady) return false;

    _status = status;
    _loadedUnitId = unitId;
    _loadedUnitKey = slot.key;
    _lastError = '';
    debugPrint(
      '[Ads] native slot already holds an ad; reusing it for ${slot.key}',
    );
    _report(
      event: 'load_success',
      slot: slot,
      latencyMs: 0,
      attempt: attempt,
      maxAttempts: maxAttempts,
    );
    return true;
  }

  bool get _appIsResumed {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  Future<bool> _present(AdSlot slot) async {
    if (_showing) return false;
    if (!capPolicy.canRequest) {
      debugPrint('[Ads] show ${slot.key} skipped by capping');
      return false;
    }
    if (_status != null && !_status!.adReady) {
      _clearLoadedUnit();
      return false;
    }
    if (!_appIsResumed) {
      // Keep the loaded ad for the next attempt instead of reporting a failure.
      debugPrint('[Ads] show ${slot.key} deferred: app is not resumed');
      return false;
    }

    _showing = true;
    final stopwatch = Stopwatch()..start();
    try {
      await MobileAds.instance.showInterstitial();
      stopwatch.stop();

      // Counters move only after a successful show.
      _recordAdShown();
      _clearLoadedUnit();
      _status = await _safeStatus();
      _report(
        event: 'show_success',
        slot: slot,
        latencyMs: stopwatch.elapsedMilliseconds,
        attempt: 1,
        maxAttempts: 1,
      );
      debugPrint('[Ads] ${slot.key} shown (#$_adsShownThisSession)');
      return true;
    } catch (error) {
      stopwatch.stop();
      _lastError = error.toString();
      _report(
        event: 'show_fail',
        slot: slot,
        error: AdReportService.classifyError(_lastError),
        message: _lastError,
        latencyMs: stopwatch.elapsedMilliseconds,
        attempt: 1,
        maxAttempts: 1,
      );
      // `invalid_state` (Activity not resumed yet) leaves the native ad ready
      // for a retry; every other failure consumed it.
      if (!_lastError.contains('invalid_state')) _clearLoadedUnit();
      _status = await _safeStatus();
      debugPrint('[Ads] show ${slot.key} failed -> $error');
      return false;
    } finally {
      _showing = false;
    }
  }

  void _recordAdShown() {
    _lastAdShownAt = DateTime.now();
    _adsShownThisSession++;
    try {
      saveAdLastShownAt(_lastAdShownAt!.millisecondsSinceEpoch);
    } catch (error) {
      debugPrint('[Ads] saving last-shown time failed -> $error');
    }
  }

  void _clearLoadedUnit() {
    _loadedUnitId = null;
    _loadedUnitKey = null;
  }

  void _report({
    required String event,
    required AdSlot slot,
    String error = '',
    String message = '',
    int latencyMs = 0,
    int attempt = 0,
    int maxAttempts = 0,
  }) {
    AdReportService.instance.addEvent(
      event: event,
      unitKey: slot.key,
      error: error,
      message: message,
      isIr: _config.isIranian,
      relayUrl: _selectedRelay?.proxyUrl ?? '',
      countryCode: _config.countryCode.isNotEmpty
          ? _config.countryCode
          : _config.visitorCountry,
      latencyMs: latencyMs,
      attempt: attempt,
      maxAttempts: maxAttempts,
    );
  }
}

String _shortUnitId(String? id) {
  final value = (id ?? '').trim();
  if (value.isEmpty) return '-';
  return value.length <= 10 ? value : value.substring(value.length - 10);
}
