import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../features/feature_channels/presentation/pages/channel_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Timer.periodic(const Duration(seconds: 3), (timer) {
      Get.to(ChannelScreen());
      timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
