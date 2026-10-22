import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:relay_ads_flutter/relay_ads_flutter.dart';

import '../../features/feature_channels/data/model/channel_model.dart';
import 'constans.dart';
import 'get_storage_data.dart';

/// Thin, Android-only wrapper around the [RelayAds] singleton.
///
/// It resolves the AdMob IDs (real ones when available, Google test IDs
/// otherwise), guards every call with a platform check and swallows failures
/// so the app never crashes or stalls because of ads.
class RelayAdsService {
  RelayAdsService._();
  static final RelayAdsService instance = RelayAdsService._();

  bool _started = false;
  bool _loaded = false;
  // Ads default to ON. The fresh backend config is the authority that turns
  // them off (ads_display_status == 0). We default to ON so a stale cached
  // "0" can never lock a device out of ads before the fresh config arrives.
  bool _adsEnabled = true;
  String _appId = RelayTestIds.appId;
  String _interstitialUnitId = RelayTestIds.interstitial;

  // Optional localization overrides passed to loadInterstitial().
  String? _countryCode;
  String? _languageCode;
  List<String>? _languageTags;
  int? _timezoneOffsetMinutes;
  String? _networkOperatorCode;
  int? _prxAa;

  // Optional direct forward-proxy (e.g. Shifter) that replaces the Bax relay.
  String? _proxyUrl;
  List<String> _proxyCandidates = const [];
  bool _selectingRelay = false;
  String? _proxyUsername;
  String? _proxyPassword;
  String _proxyMode = 'rotation'; // 'rotation' (fresh IP per request) or 'sticky' (fixed IP per app launch)
  String? _sessionId;

  // Backend ad display controls.
  bool _showSplashAd = true;
  bool _showConnectAd = true;
  String? _connectInterstitialUnitId;
  int _adMinIntervalSeconds = 0;
  int _adMaxPerSession = 0;
  int _adRetryCount = 2;
  int _proxyTtlSeconds = 3600;

  // Frequency capping state.
  DateTime? _lastAdShownAt;
  int _adsShownThisSession = 0;

  /// Builds the effective Shifter username. In 'sticky' mode a unique per-launch
  /// session id is appended so all requests in this app run share one exit IP.
  String? _effectiveUsername() {
    final user = _proxyUsername;
    if (user == null || user.isEmpty) return user;
    if (_proxyMode == 'sticky') {
      _sessionId ??= 'stk${DateTime.now().microsecondsSinceEpoch}';
      return '$user-sid-$_sessionId-ttl-$_proxyTtlSeconds';
    }
    return user;
  }

  /// The plugin only supports Android.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Starts the relay + SDK and resolves the ad IDs. Safe to call repeatedly.
  Future<void> init() async {
    if (!isSupported) {
      debugPrint('RelayAds: init skipped (Android only)');
      return;
    }
    if (_started) return;
    if (!_adsEnabled) {
      debugPrint('RelayAds: ads disabled — skipping start');
      return;
    }
    if (_proxyUrl == null || _proxyUrl!.isEmpty) {
      debugPrint('RelayAds: no proxy configured — skipping start');
      return;
    }
    debugPrint('RelayAds: start appId=$_appId unit=$_interstitialUnitId mode=$_proxyMode user=${_effectiveUsername()}');

    // Reuse an already-running session (e.g. after a Flutter hot restart the
    // native relay keeps its state while the Dart side restarts).
    try {
      final current = await RelayAds.instance.getStatus();
      final state = current.state;
      if (state == RelayState.ready ||
          state == RelayState.loaded ||
          state == RelayState.starting ||
          state == RelayState.loading ||
          state == RelayState.showing) {
        _started = true;
        _loaded = current.adReady;
        debugPrint('RelayAds: reuse active session -> ${state.name}');
        return;
      }
    } catch (_) {
      // getStatus may fail on a cold start before the native side is ready;
      // fall through to a normal start().
    }

    await _startRelay();
  }

  /// Starts the native relay + SDK with the current proxy config.
  /// Returns true when the relay reached a ready state.
  Future<bool> _startRelay() async {
    if (!isSupported || !_adsEnabled) return false;
    if (_proxyUrl == null || _proxyUrl!.isEmpty) return false;
    try {
      final status = await RelayAds.instance.start(RelayAdsConfig(
        appId: _appId,
        // The Bax relay is no longer used; egress is only via the configured proxy.
        relayEndpoints: const [],
        writeTimeout: const Duration(seconds: 60),
        proxyUrl: _proxyUrl,
        proxyUsername: _effectiveUsername(),
        proxyPassword: _proxyPassword,
      ));
      _started = true;
      debugPrint('RelayAds: start OK -> ${status.state.name}');
      return true;
    } catch (e) {
      debugPrint('RelayAds: start FAILED -> $e');
      return false;
    }
  }

  Future<bool> preloadUnit(String adUnitId) async {
    if (!isSupported || !_started || !_adsEnabled) return false;
    if (adUnitId.isEmpty) return false;

    final maxAttempts = (_adRetryCount + 1).clamp(1, 5).toInt();
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final status = await RelayAds.instance.loadInterstitial(
          adUnitId: adUnitId,
          countryCode: _countryCode,
          languageCode: _languageCode,
          languageTags: _languageTags,
          timezoneOffsetMinutes: _timezoneOffsetMinutes,
          networkOperatorCode: _networkOperatorCode,
          prxAa: _prxAa,
        );
        _loaded = true;
        debugPrint(
            'RelayAds: load OK (attempt $attempt) -> ${status.state.name}');
        return true;
      } catch (e) {
        debugPrint(
            'RelayAds: load FAILED (attempt $attempt/$maxAttempts) -> $e');
        final message = e.toString();
        // Permanent errors (no fill / account not approved / invalid request)
        // won't succeed on retry, so stop immediately instead of rotating.
        final retryable = !(message.contains('NO_FILL') ||
            message.contains('Account not approved') ||
            message.contains('INVALID_REQUEST'));
        if (!retryable || attempt >= maxAttempts) {
          _loaded = false;
          return false;
        }
        await _rotateAndRestart();
      }
    }
    return false;
  }

  /// Gives the next attempt a fresh Shifter exit IP. In rotation mode each
  /// request already gets a new IP, so this only backs off briefly. In sticky
  /// mode it regenerates the session id and restarts the relay for a new IP.
  Future<void> _rotateAndRestart() async {
    if (_proxyMode != 'sticky') {
      await Future.delayed(const Duration(milliseconds: 400));
      return;
    }
    _sessionId = 'stk${DateTime.now().microsecondsSinceEpoch}';
    debugPrint('RelayAds: rotating sticky session -> $_sessionId');
    await _restartRelay();
  }

  /// Stops and starts the relay with the current config (used when the proxy
  /// changes while it is already running, or to rotate a sticky session).
  Future<void> _restartRelay() async {
    try {
      await RelayAds.instance.stop();
    } catch (_) {
      // ignore — best effort.
    }
    _started = false;
    _loaded = false;
    // The native stop() releases the loopback port asynchronously; give it a
    // moment and retry if the port is still held (transient EADDRINUSE).
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (await _startRelay()) return;
    }
    debugPrint('RelayAds: restart FAILED after retries');
  }

  /// Measures the TCP connect latency (ms) to a relay URL, or null when it is
  /// unreachable. Every relay forwards to the same Shifter endpoint, so the
  /// only variable is the user→relay round-trip time — a plain connect is the
  /// right "ping" here.
  Future<int?> _pingRelay(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(uri.host, port,
          timeout: const Duration(seconds: 3));
      stopwatch.stop();
      socket.destroy();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// Pings every configured relay in parallel and returns the fastest reachable
  /// one (lowest TCP connect latency). Falls back to the current proxy if every
  /// relay is down.
  Future<String?> _selectFastestRelay() async {
    final candidates = _proxyCandidates
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();
    if (candidates.isEmpty) return _proxyUrl;
    if (candidates.length == 1) return candidates.first;

    final probes = await Future.wait(candidates.map((url) async {
      final latencyMs = await _pingRelay(url);
      return (url, latencyMs);
    }));

    final best = pickFastestRelay(probes);
    if (best != null) {
      debugPrint('RelayAds: fastest relay -> $best');
    } else {
      debugPrint('RelayAds: all relays unreachable; keeping $_proxyUrl');
    }
    return best ?? _proxyUrl;
  }

  /// Runs the parallel ping, adopts the fastest relay, and (re)starts the SDK.
  Future<void> _selectRelayAndStart() async {
    if (_selectingRelay) return;
    _selectingRelay = true;
    try {
      final chosen = await _selectFastestRelay();
      if (chosen == null || chosen.isEmpty) {
        if (!_started) await init();
        return;
      }
      final changed = chosen != _proxyUrl;
      _proxyUrl = chosen;
      _cacheMergedConfig();
      if (!_started) {
        await init();
      } else if (changed) {
        await _restartRelay();
      }
    } finally {
      _selectingRelay = false;
    }
  }

  /// Shows the previously loaded interstitial, if one is ready.
  Future<bool> showLoaded() async {
    if (!isSupported || !_started || !_loaded || !_adsEnabled) return false;
    try {
      await RelayAds.instance.showInterstitial();
      debugPrint('RelayAds: show OK');
      return true;
    } catch (e) {
      debugPrint('RelayAds: show FAILED -> $e');
      return false;
    } finally {
      _loaded = false;
    }
  }

  bool get _canShowAd {
    if (_adMaxPerSession > 0 && _adsShownThisSession >= _adMaxPerSession) {
      debugPrint('RelayAds: ad skipped (max-per-session cap reached)');
      return false;
    }
    final last = _lastAdShownAt;
    if (_adMinIntervalSeconds > 0 && last != null) {
      final elapsed = DateTime.now().difference(last).inSeconds;
      if (elapsed < _adMinIntervalSeconds) {
        debugPrint('RelayAds: ad skipped (min-interval not reached)');
        return false;
      }
    }
    return true;
  }

  void _recordAdShown() {
    _lastAdShownAt = DateTime.now();
    _adsShownThisSession++;
  }

  Future<void> _showAd(String adUnitId) async {
    if (!_canShowAd) return;
    if (!await preloadUnit(adUnitId)) return;
    if (await showLoaded()) {
      _recordAdShown();
    }
  }

  /// Interstitial for the splash screen (uses the main interstitial unit id).
  Future<void> showSplashAd() async {
    if (!isSupported || !_started || !_adsEnabled) return;
    if (!_showSplashAd) {
      debugPrint('RelayAds: splash ad disabled by backend');
      return;
    }
    await _showAd(_interstitialUnitId);
  }

  /// Interstitial shown after a proxy is found (uses a separate unit id).
  Future<void> showConnectAd() async {
    if (!isSupported || !_started || !_adsEnabled) return;
    if (!_showConnectAd) {
      debugPrint('RelayAds: connect ad disabled by backend');
      return;
    }
    final unit = _connectInterstitialUnitId;
    if (unit == null || unit.isEmpty) {
      debugPrint('RelayAds: no connect interstitial unit id configured');
      return;
    }
    await _showAd(unit);
  }

  Future<void> loadCachedConfig() async {
    try {
      final raw = GetStorageData.getData(storageKeyAdConfig);
      if (raw is Map) {
        final cached = AdConfig.fromJson(Map<String, dynamic>.from(raw));
        // Use the cached proxy/unit ids for the splash ad, but ignore a stale
        // ads_display_status == 0 so it can't lock ads off before the fresh
        // config arrives (a valid "1" is still honored).
        if (cached.adsDisplayStatus == 0) {
          cached.adsDisplayStatus = null;
        }
        applyConfig(cached);
      }
    } catch (_) {
      // No/invalid cache — keep defaults.
    }
  }

  /// Applies ad config fetched from the proxy API. Missing/null fields keep
  /// their current value, so a partial config is perfectly fine.
  ///
  /// When [startIfReady] is true (backend fetch), the proxy/SDK is started
  /// immediately if it was not already running — so a fresh install shows the
  /// ad on the first launch instead of waiting for the next one.
  void applyConfig(AdConfig? config, {bool startIfReady = false}) {
    if (config == null) return;
    if (config.adsDisplayStatus != null) {
      _adsEnabled = config.adsDisplayStatus == 1;
    }
    if (config.appId != null && config.appId!.isNotEmpty) {
      _appId = config.appId!;
    }
    if (config.interstitialUnitId != null &&
        config.interstitialUnitId!.isNotEmpty) {
      _interstitialUnitId = config.interstitialUnitId!;
    }
    _countryCode = config.countryCode ?? _countryCode;
    _languageCode = config.languageCode ?? _languageCode;
    _languageTags = config.languageTags ?? _languageTags;
    _timezoneOffsetMinutes =
        config.timezoneOffsetMinutes ?? _timezoneOffsetMinutes;
    _networkOperatorCode = config.networkOperatorCode ?? _networkOperatorCode;
    _prxAa = config.prxAa ?? _prxAa;
    _proxyUsername = config.proxyUsername ?? _proxyUsername;
    _proxyPassword = config.proxyPassword ?? _proxyPassword;
    _proxyMode = config.proxyMode ?? _proxyMode;
    // Use the backend-verified sticky session id (no client-side pre-warm).
    if (config.proxySessionId != null && config.proxySessionId!.isNotEmpty) {
      _sessionId = config.proxySessionId;
    }

    // Backend may return 1–3 relay URLs. Keep the full list so we can ping all
    // of them in parallel and pick the fastest one.
    final incoming = config.proxyCandidates;
    if (incoming.isNotEmpty) {
      _proxyCandidates = incoming;
    }
    // Fresh install (no cache) has no proxy yet; seed it with the first
    // candidate so init()/splash has something to use before selection runs.
    if (_proxyUrl == null || _proxyUrl!.isEmpty) {
      _proxyUrl = _proxyCandidates.isNotEmpty ? _proxyCandidates.first : null;
    }
    _showSplashAd =
        config.showSplashAd != null ? config.showSplashAd == 1 : _showSplashAd;
    _showConnectAd =
        config.showConnectAd != null ? config.showConnectAd == 1 : _showConnectAd;
    _connectInterstitialUnitId =
        config.connectInterstitialUnitId ?? _connectInterstitialUnitId;
    _adMinIntervalSeconds =
        config.adMinIntervalSeconds ?? _adMinIntervalSeconds;
    _adMaxPerSession = config.adMaxPerSession ?? _adMaxPerSession;
    _adRetryCount = config.adRetryCount ?? _adRetryCount;
    _proxyTtlSeconds = config.proxyTtlSeconds ?? _proxyTtlSeconds;
    // Cache the merged state (preserving any locally-set proxy), not the raw
    // backend config, so the proxy doesn't get wiped back to relay mode.
    _cacheMergedConfig();
    if (!_adsEnabled) {
      debugPrint(
          'RelayAds: ads disabled (ads_display_status=${config.adsDisplayStatus})');
      return;
    }
    if (startIfReady) {
      // Ping every relay in parallel, adopt the fastest, then start/restart.
      unawaited(_selectRelayAndStart());
    }
  }

  void _cacheMergedConfig() {
    try {
      final others = _proxyCandidates
          .where((url) => url != _proxyUrl)
          .toList(growable: false);
      final merged = AdConfig(
        appId: _appId,
        interstitialUnitId: _interstitialUnitId,
        proxyUrl: _proxyUrl,
        proxyUrl2: others.isNotEmpty ? others[0] : null,
        proxyUrl3: others.length > 1 ? others[1] : null,
        proxyUsername: _proxyUsername,
        proxyPassword: _proxyPassword,
        proxyMode: _proxyMode,
        proxySessionId: _sessionId,
        showSplashAd: _showSplashAd ? 1 : 0,
        showConnectAd: _showConnectAd ? 1 : 0,
        connectInterstitialUnitId: _connectInterstitialUnitId,
        adMinIntervalSeconds: _adMinIntervalSeconds,
        adMaxPerSession: _adMaxPerSession,
        adRetryCount: _adRetryCount,
        proxyTtlSeconds: _proxyTtlSeconds,
        timezoneOffsetMinutes: _timezoneOffsetMinutes,
        countryCode: _countryCode,
        languageCode: _languageCode,
        languageTags: _languageTags,
        networkOperatorCode: _networkOperatorCode,
        prxAa: _prxAa,
        adsDisplayStatus: _adsEnabled ? 1 : 0,
      );
      GetStorageData.writeData(storageKeyAdConfig, merged.toJson());
    } catch (_) {
      // ignore
    }
  }
}

/// Picks the relay URL with the lowest non-null latency (ms), or null if every
/// relay timed out. Exposed for unit testing.
String? pickFastestRelay(List<(String, int?)> probes) {
  String? best;
  int? bestMs;
  for (final (url, ms) in probes) {
    if (ms == null) continue;
    if (bestMs == null || ms < bestMs) {
      bestMs = ms;
      best = url;
    }
  }
  return best;
}
