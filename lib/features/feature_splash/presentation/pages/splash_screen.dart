import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:proxymodern/core/utils/relay_ads_service.dart';
import 'package:proxymodern/features/feature_channels/presentation/pages/channel_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _bg = Color(0xFF081016);
  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);

  static const _statusMessages = [
    "برقراری اتصال امن به سرورها…",
    "بهینه‌سازی پروکسی‌ها…",
    "بررسی پایداری سرورها…",
    "رمزنگاری کانال ارتباطی…",
    "انتخاب سریع‌ترین مسیر…",
    "آماده‌سازی تونل امن…",
  ];

  Timer? _statusTimer;
  int _statusIndex = Random().nextInt(_statusMessages.length);

  @override
  void initState() {
    super.initState();
    _startStatusRotation();
    _boot();
  }

  void _startStatusRotation() {
    _statusTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (!mounted) return;
      setState(() {
        _statusIndex = (_statusIndex + 1) % _statusMessages.length;
      });
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final minDelay = Future.delayed(const Duration(seconds: 2));
    final ads = RelayAdsService.instance;

    // Use the cached backend ad config from the last launch (if any).
    await ads.loadCachedConfig();
    await ads.init();
    // Small delay so the Android Activity is fully resumed before the ad.
    await Future.delayed(const Duration(milliseconds: 600));
    await ads.showOneAd();

    await minDelay;
    if (mounted) {
      Get.off(() => const ChannelScreen());
    }
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
                    _statusMessages[_statusIndex],
                    key: ValueKey<int>(_statusIndex),
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
