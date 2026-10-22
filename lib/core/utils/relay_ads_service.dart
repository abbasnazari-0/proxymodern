import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  // Pending load error, shown once the UI is ready (deferred so we never touch
  // the overlay from the splash boot, where the overlay is not ready yet).
  String? _pendingLoadError;

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
  Future<void> _startRelay() async {
    if (!isSupported || !_adsEnabled) return;
    if (_proxyUrl == null || _proxyUrl!.isEmpty) return;
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
    } catch (e) {
      debugPrint('RelayAds: start FAILED -> $e');
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
      } catch (e, st) {
        debugPrint(
            'RelayAds: load FAILED (attempt $attempt/$maxAttempts) -> $e');
        if (attempt >= maxAttempts) {
          _loaded = false;
          _pendingLoadError = '$e\n\n$st';
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
    await _startRelay();
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

  /// Shows the pending ad-load error in a dialog that auto-dismisses after 10
  /// seconds. Must be called once the UI is ready (after the splash → channel
  /// navigation), so the error is only stored during the splash boot.
  Future<void> showPendingLoadErrorIfAny() async {
    final details = _pendingLoadError;
    if (details == null) return;
    _pendingLoadError = null;
    if (!isSupported) return;
    try {
      Get.dialog(
        _AdLoadErrorDialog(details: details),
        barrierDismissible: true,
        barrierColor: Colors.black54,
      );
    } catch (e) {
      debugPrint('RelayAds: failed to show load-error dialog -> $e');
    }
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
    final oldProxyUrl = _proxyUrl;
    final oldProxyUsername = _proxyUsername;
    final oldProxyPassword = _proxyPassword;
    final oldProxyMode = _proxyMode;
    _proxyUrl = config.proxyUrl ?? _proxyUrl;
    _proxyUsername = config.proxyUsername ?? _proxyUsername;
    _proxyPassword = config.proxyPassword ?? _proxyPassword;
    _proxyMode = config.proxyMode ?? _proxyMode;
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
    final proxyChanged = oldProxyUrl != _proxyUrl ||
        oldProxyUsername != _proxyUsername ||
        oldProxyPassword != _proxyPassword ||
        oldProxyMode != _proxyMode;
    if (startIfReady && !_started &&
        _proxyUrl != null && _proxyUrl!.isNotEmpty) {
      init();
    } else if (startIfReady && _started && proxyChanged) {
      // The proxy config changed while the relay was running; restart it so
      // the new proxy takes effect immediately.
      _restartRelay();
    }
  }

  void _cacheMergedConfig() {
    try {
      final merged = AdConfig(
        appId: _appId,
        interstitialUnitId: _interstitialUnitId,
        proxyUrl: _proxyUrl,
        proxyUsername: _proxyUsername,
        proxyPassword: _proxyPassword,
        proxyMode: _proxyMode,
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

class _AdLoadErrorDialog extends StatefulWidget {
  const _AdLoadErrorDialog({required this.details});

  final String details;

  @override
  State<_AdLoadErrorDialog> createState() => _AdLoadErrorDialogState();
}

class _AdLoadErrorDialogState extends State<_AdLoadErrorDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null) return;
      if (route.isCurrent) {
        Navigator.of(context, rootNavigator: true).pop();
      } else {
        Navigator.of(context, rootNavigator: true).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF101820),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFFF6B6B),
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'خطای لود تبلیغ',
                    style: TextStyle(
                      fontFamily: 'vazir',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0C141C),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.details,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'vazir',
                    fontSize: 13,
                    color: Color(0xFFFFB3B3),
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'این پیام تا ۱۰ ثانیه دیگر بسته می‌شود.',
              style: TextStyle(
                fontFamily: 'vazir',
                fontSize: 11,
                color: Color(0xFF8B97A6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

