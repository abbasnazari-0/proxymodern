import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/main_wrapper.dart';
import 'core/params/admob-ids-getter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  AdmobDataGetter.init();
  await GetStorage.init();

  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(
      tagForChildDirectedTreatment: TagForChildDirectedTreatment.unspecified,
      testDeviceIds: <String>["EF64FD02DDDE11749AD3EBB8EC473C4E"],
    ),
  );

  runApp(const MainWrapper());
  // running somthing
}
