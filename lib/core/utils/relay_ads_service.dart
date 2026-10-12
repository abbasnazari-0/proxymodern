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
  // Ads stay off until the backend says ads_display_status == 1 (e.g. the
  // user is inside Iran). Outside Iran the backend sends 0 + empty data, so
  // no ad should be shown at all.
  bool _adsEnabled = false;
  String _appId = RelayTestIds.appId;
  String _interstitialUnitId = RelayTestIds.interstitial;
  List<String> _relayEndpoints = RelayAdsConfig.baxEndpoints;

  // Optional localization overrides passed to loadInterstitial().
  String? _countryCode;
  String? _languageCode;
  List<String>? _languageTags;
  int? _timezoneOffsetMinutes;
  String? _networkOperatorCode;
  int? _prxAa;

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
    debugPrint('RelayAds: start appId=$_appId unit=$_interstitialUnitId');

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

    try {
      final status = await RelayAds.instance.start(RelayAdsConfig(
        appId: _appId,
        relayEndpoints: _relayEndpoints,
      ));
      _started = true;
      debugPrint('RelayAds: start OK -> ${status.state.name}');
    } catch (e) {
      debugPrint('RelayAds: start FAILED -> $e');
    }
  }

  /// Loads one interstitial into the ready slot (does not show it).
  Future<void> preload() async {
    if (!isSupported || !_started || !_adsEnabled) return;
    try {
      final status = await RelayAds.instance.loadInterstitial(
        adUnitId: _interstitialUnitId,
        countryCode: _countryCode,
        languageCode: _languageCode,
        languageTags: _languageTags,
        timezoneOffsetMinutes: _timezoneOffsetMinutes,
        networkOperatorCode: _networkOperatorCode,
        prxAa: _prxAa,
      );
      _loaded = true;
      debugPrint('RelayAds: load OK -> ${status.state.name}');
    } catch (e) {
      _loaded = false;
      debugPrint('RelayAds: load FAILED -> $e');
    }
  }

  /// Shows the previously loaded interstitial, if one is ready.
  Future<void> showLoaded() async {
    if (!isSupported || !_started || !_loaded || !_adsEnabled) return;
    try {
      await RelayAds.instance.showInterstitial();
      debugPrint('RelayAds: show OK');
    } catch (e) {
      debugPrint('RelayAds: show FAILED -> $e');
    } finally {
      _loaded = false;
    }
  }

  /// Loads then shows a single interstitial.
  Future<void> showOneAd() async {
    if (!_loaded) {
      await preload();
    }
    await showLoaded();
  }

  /// Loads a previously cached ad config (saved after the last successful
  /// fetch) so the splash ad can use the real backend values on later launches.
  Future<void> loadCachedConfig() async {
    try {
      final raw = GetStorageData.getData(storageKeyAdConfig);
      if (raw is Map) {
        applyConfig(AdConfig.fromJson(Map<String, dynamic>.from(raw)));
      }
    } catch (_) {
      // No/invalid cache — keep defaults.
    }
  }

  /// Applies ad config fetched from the proxy API. Missing/null fields keep
  /// their current value, so a partial config is perfectly fine.
  void applyConfig(AdConfig? config) {
    if (config == null) return;
    if (config.adsDisplayStatus != null) {
      _adsEnabled = config.adsDisplayStatus == 1;
    }
    _cacheConfig(config);
    if (!_adsEnabled) {
      debugPrint(
          'RelayAds: ads disabled (ads_display_status=${config.adsDisplayStatus})');
      return;
    }
    if (config.appId != null && config.appId!.isNotEmpty) {
      _appId = config.appId!;
    }
    if (config.interstitialUnitId != null &&
        config.interstitialUnitId!.isNotEmpty) {
      _interstitialUnitId = config.interstitialUnitId!;
    }
    if (config.relayEndpoints != null && config.relayEndpoints!.isNotEmpty) {
      _relayEndpoints = config.relayEndpoints!;
    }
    _countryCode = config.countryCode ?? _countryCode;
    _languageCode = config.languageCode ?? _languageCode;
    _languageTags = config.languageTags ?? _languageTags;
    _timezoneOffsetMinutes =
        config.timezoneOffsetMinutes ?? _timezoneOffsetMinutes;
    _networkOperatorCode = config.networkOperatorCode ?? _networkOperatorCode;
    _prxAa = config.prxAa ?? _prxAa;
  }

  void _cacheConfig(AdConfig config) {
    try {
      GetStorageData.writeData(storageKeyAdConfig, config.toJson());
    } catch (_) {
      // ignore
    }
  }
}
