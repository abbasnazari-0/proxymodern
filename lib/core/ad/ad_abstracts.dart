import 'package:flutter/material.dart';

abstract class MyRewardedAd {
  Future<void> loadRewarded();
  Future<void> showRewarded();
  Future<void> disposeRewarded();
}

abstract class MyBannerAd {
  Future<void> loadBanner();
  Widget showBanner();
  Future<void> disposeBanner();
}

abstract class MyInterstitialAd {
  Future<void> loadInterstitial();
  Future<void> showInterstitial();
  Future<void> disposeInterstitial();
}

abstract class MyOpenAd {
  Future<void> loadOpenAd();
  showOpenAd();
  Future<void> disposeOpenAd();
}

abstract class MyNativeAd {
  Future<void> loadNativeAd();
  Widget showNativeAd(BuildContext context);
  disposeNativeAd();
}
