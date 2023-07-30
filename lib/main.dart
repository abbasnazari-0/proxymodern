import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/main_wrapper.dart';
import 'core/params/admob-ids-getter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  AdmobDataGetter.init();

  runApp(const MainWrapper());
}
