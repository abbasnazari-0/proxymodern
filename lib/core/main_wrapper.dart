import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:proxymodern/features/feature_splash/presentation/pages/splash_screen.dart';

class MainWrapper extends StatelessWidget {
  const MainWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    print('ddd');
    return GetMaterialApp(
      title: 'Pro Telegram Proxy',
      theme: ThemeData(),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
