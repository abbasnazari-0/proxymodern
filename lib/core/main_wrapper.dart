import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../features/feature_channels/presentation/pages/channel_screen.dart';

class MainWrapper extends StatelessWidget {
  const MainWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Pro Telegram Proxy',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Color(0xFF082032),
        // app bar color
        appBarTheme: const AppBarTheme(backgroundColor: Colors.deepPurple),
      ),
      debugShowCheckedModeBanner: false,
      home: ChannelScreen(),
    );
  }
}
