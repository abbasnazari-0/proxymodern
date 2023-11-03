import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:proxymodern/features/feature_splash/presentation/pages/splash_screen.dart';

class MainWrapper extends StatelessWidget {
  const MainWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Pro Telegram Proxy',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Color.fromARGB(255, 10, 29, 44),
        // app bar color
        appBarTheme: const AppBarTheme(backgroundColor: Colors.deepPurple),
      ),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
