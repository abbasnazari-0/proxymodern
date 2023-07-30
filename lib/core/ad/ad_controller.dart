import 'package:get/state_manager.dart';

import 'ad_initlizer.dart';

class AdController extends GetxController {
  AdInitilzer? adInitilzer = AdInitilzer();

  @override
  void onInit() {
    super.onInit();
    adInitilzer?.init();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    adInitilzer?.disposeBanner();
    adInitilzer?.disposeInterstitial();
    adInitilzer?.disposeRewarded();
  }
}
