import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:proxymodern/features/feature_splash/presentation/pages/splash_screen.dart';

import 'utils/firebase_service.dart';
import 'utils/notification_service.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🔔 راه‌اندازی FCM: توکن دریافت و به بک‌اند ارسال می‌شود؛ لمس
    // نوتیفیکیشن هم با همین navigatorKey دیپ‌لینک می‌شود.
    NotificationService.instance.onTokenChanged = (token) {
      return FirebaseService.instance.registerDeviceToken(token);
    };
    unawaited(
      NotificationService.instance.init(navigatorKey: _navigatorKey),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // 🔔 تضمین عضویت در تاپیک عمومی «all» تا اعلان‌های گروهی همیشه برسند.
    unawaited(NotificationService.instance.ensureAllTopicSubscription());
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Pro Telegram Proxy',
      theme: ThemeData(),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
