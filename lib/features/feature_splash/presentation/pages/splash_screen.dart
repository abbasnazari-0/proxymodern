import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:proxymodern/core/ad/ad_controller.dart';

import 'package:proxymodern/features/feature_channels/presentation/pages/channel_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final adController = Get.put(AdController());

  @override
  void initState() {
    super.initState();
    // adController.adInitilzer?.loadOpenAd();
    // adController.adInitilzer?.showOpenAd();

    Future.delayed(const Duration(seconds: 1), () {
      Get.off(() => const ChannelScreen());
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold();
  }
}
