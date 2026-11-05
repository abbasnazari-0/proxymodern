import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:proxymodern/core/models/ad_config.dart';
import 'package:proxymodern/core/models/app_update.dart';
import 'package:proxymodern/core/utils/app_info.dart';
import 'package:proxymodern/core/utils/firebase_service.dart';
import 'package:proxymodern/core/utils/mobile_ads_service.dart';
import 'package:proxymodern/features/feature_channels/presentation/pages/channel_screen.dart';
import 'package:proxymodern/features/feature_update/presentation/screens/feature_update.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _bg = Color(0xFF081016);
  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);

  String _status = 'در حال آماده‌سازی…';
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  void _setStatus(String value) {
    if (!mounted || _status == value) return;
    setState(() => _status = value);
  }

  Future<void> _boot() async {
    final startedAt = DateTime.now();
    final ads = MobileAdsService.instance;
    final bootTrace = await FirebaseService.instance.startTrace('splash_boot');

    unawaited(FirebaseService.instance.logScreenView('splash'));

    try {
      await AppInfo.ensureLoaded();

      // ۱) Last launch's decoded config (used immediately if the network is
      // blocked or every mirror is filtered).
      _setStatus('در حال خواندن تنظیمات…');
      try {
        await ads.loadCachedConfig();
      } catch (error) {
        debugPrint('Splash.loadCachedConfig failed -> $error');
      }

      // ۲) Fresh config.php: signed request + AES-256-GCM + domain failover.
      _setStatus('در حال دریافت تنظیمات از سرور…');
      try {
        await ads.refreshConfigFromBackend();
      } catch (error) {
        debugPrint('Splash.refreshConfigFromBackend failed -> $error');
      }
      if (!mounted) return;

      // ۳) Mandatory/optional update must be decided before any app UI.
      final update = AppUpdatePolicy.evaluate(
        config: ads.config,
        currentBuildNumber: AppInfo.buildNumber,
        currentVersionName: AppInfo.versionName,
      );
      if (update != null) {
        _navigated = true;
        Get.offAll(
          () => UpdateScreen(
            title: update.title,
            description: update.description,
            url: update.updateUrl,
            forced: update.forced,
            onLater: _continueToApp,
          ),
        );
        return;
      }

      // ۴) Relay selection (is_ir=1) or direct SDK (is_ir=0) + SDK start.
      _setStatus('در حال آماده‌سازی سرویس…');
      try {
        await ads
            .init()
            .timeout(const Duration(seconds: 20), onTimeout: () => false);
      } catch (error) {
        debugPrint('Splash ads.init failed -> $error');
      }

      // ۵) Splash interstitial. showSplashAd also preloads the connect unit as
      // soon as the splash ad is dismissed (the SDK holds one ad at a time).
      if (ads.adsEnabled && ads.unitIdFor(AdSlot.splash) != null) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        _setStatus('در حال آماده‌سازی سرویس ها…');
        try {
          await ads.showSplashAd();
        } catch (error) {
          debugPrint('Splash.showSplashAd failed -> $error');
        }
      } else {
        // No splash unit: still prepare the connect ad during the splash phase
        // (bounded so a slow load cannot hold the app hostage).
        debugPrint(
          'Splash: splash unit is missing/disabled '
          '(adsEnabled=${ads.adsEnabled}); preloading connect only',
        );
        try {
          await ads.preloadConnectAd().timeout(const Duration(seconds: 8));
        } catch (error) {
          debugPrint('Splash connect preload failed -> $error');
        }
      }
    } catch (error) {
      // Ads/config failures never block the app.
      debugPrint('Splash boot failed -> $error');
      unawaited(
        FirebaseService.instance.logEvent(
          'splash_boot_failed',
          <String, Object>{'error': '$error'},
        ),
      );
    } finally {
      // Performance Monitoring: how long the ad/config bootstrap took, split by
      // whether ads are active for this install.
      unawaited(
        FirebaseService.instance.finishTrace(bootTrace, <String, String>{
          'ads_enabled': ads.adsEnabled.toString(),
        }),
      );
    }

    const minimumDisplay = Duration(seconds: 2);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minimumDisplay) {
      await Future<void>.delayed(minimumDisplay - elapsed);
    }
    _openHome();
  }

  /// Normal boot path: replace the splash route with the home screen.
  void _openHome() {
    if (!mounted || _navigated) return;
    _navigated = true;
    Get.off(() => const ChannelScreen());
  }

  /// Used by the optional update screen's "بعداً" button. The splash route was
  /// already replaced, so this must always navigate.
  void _continueToApp() {
    Get.offAll(() => const ChannelScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  "assets/images/icon.png",
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "سوپر پروکسی",
                style: TextStyle(
                  fontFamily: "vazir",
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "اتصال سریع و امن به تلگرام",
                style: TextStyle(
                  fontFamily: "vazir",
                  fontSize: 13,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _accent,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 20,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _status,
                    key: ValueKey<String>(_status),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: "vazir",
                      fontSize: 12,
                      color: _muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
