import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:proxymodern/core/models/admob-models.dart';

import '../params/admob-ids-getter.dart';
import 'ad_abstracts.dart';

class AdInitilzer extends MyRewardedAd
    implements MyInterstitialAd, MyBannerAd, MyOpenAd, MyNativeAd {
  final String rewardedAd = "ca-app-pub-3940256099942544/5354046379";
  final String bannerAd = "ca-app-pub-3940256099942544/6300978111";
  final String interstialAd = "ca-app-pub-3940256099942544/1033173712";
  final String nativeAd = "ca-app-pub-3940256099942544/2247696110";

  RewardedInterstitialAd? _rewardeInterstitialdAd;
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  AppOpenAd? _appOpenAd;
  bool _isShowingAd = false;
  bool hasFullScreenAd = false;

  AdmobData adModel = AdmobDataGetter.getAdmobIds();

  Function(bool loaded)? onBannerLoaded;
  void init(Function(bool loaded) onBannerLoaded) {
    this.onBannerLoaded = onBannerLoaded;
    // fill your ad ids
    adModel = AdmobDataGetter.getAdmobIds();
    debugPrint("adModel is ${adModel.toJson()}");
    loadAdBannerSize();
  }

  AnchoredAdaptiveBannerAdSize? bannerSize;
  loadAdBannerSize() async {
    bannerSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
        MediaQuery.of(Get.context!).size.width.truncate());
  }

  @override
  Future<void> disposeRewarded() {
    return _rewardeInterstitialdAd?.dispose() ?? Future.value();
  }

  @override
  Future<void> loadRewarded() async {
    hasFullScreenAd = false;
    await RewardedInterstitialAd.load(
      adUnitId: adModel.rewardedAdId ?? rewardedAd,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        // Called when an ad is successfully received.
        onAdLoaded: (ad) {
          debugPrint('$ad loaded.');
          // Keep a reference to the ad so you can show it later.
          _rewardeInterstitialdAd = ad;
          hasFullScreenAd = true;
        },

        // Called when an ad request failed.
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('RewardedInterstitialAd failed to load: $error');
          if (_rewardeInterstitialdAd != null) {
            _rewardeInterstitialdAd?.dispose();
          }
          loadInterstitial();
        },
      ),
    );
  }

  @override
  Future<int> showRewarded() async {
    int isRewarded = 0;
    if (_rewardeInterstitialdAd == null && _interstitialAd == null) {
      isRewarded = 0;
      await loadRewarded();
    }
    if (_rewardeInterstitialdAd != null && _interstitialAd == null) {
      await _rewardeInterstitialdAd?.show(
          onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
        isRewarded = 1;
        await loadRewarded();
      });
    }
    if (_rewardeInterstitialdAd == null && _interstitialAd != null) {
      await showInterstitial();
      isRewarded = 1;
    }
    if (_rewardeInterstitialdAd != null && _interstitialAd != null) {
      await _rewardeInterstitialdAd?.show(
          onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
        await loadRewarded();
        isRewarded = 1;
      });
    }

    await loadRewarded();

    return isRewarded;
  }

  @override
  Future<void> disposeBanner() async {
    await _bannerAd?.dispose();
  }

  @override
  Future<void> disposeInterstitial() async {
    await _interstitialAd?.dispose();
  }

  @override
  Future<void> loadBanner() async {
    if (bannerSize != null) {
      _bannerAd = BannerAd(
        adUnitId: adModel.bannerAdId ?? bannerAd,
        request: const AdRequest(),
        size: bannerSize!,
        listener: BannerAdListener(
          // Called when an ad is successfully received.
          onAdLoaded: (ad) {
            debugPrint('$ad loaded.');
            _isBannerLoaded = true;

            onBannerLoaded!(true);

            // setState(() {
            //   _isLoaded = true;
            // });
          },
          // Called when an ad request failed.
          onAdFailedToLoad: (ad, err) {
            debugPrint('BannerAd failed to load: $err');
            // Dispose the ad here to free resources.
            ad.dispose();
          },
        ),
      )..load();
    }
  }

  @override
  Future<void> loadInterstitial() async {
    await InterstitialAd.load(
        adUnitId: adModel.fullScreenAdId ?? interstialAd,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          // Called when an ad is successfully received.
          onAdLoaded: (ad) {
            debugPrint('$ad loaded.');
            // Keep a reference to the ad so you can show it later.
            _interstitialAd = ad;
            hasFullScreenAd = true;
            // ad.show();
          },
          // Called when an ad request failed.
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint('InterstitialAd failed to load: $error');
            if (_interstitialAd != null) {
              _interstitialAd?.dispose();
            }
          },
        ));
  }

  bool _isBannerLoaded = false;
  @override
  Widget showBanner() {
    if (_bannerAd == null) loadBanner();
    if (_isBannerLoaded) {
      return SizedBox(
        width: bannerSize?.width.toDouble(),
        height: bannerSize?.height.toDouble(),
        child: AdWidget(
          ad: _bannerAd!,
        ),
      );
    }
    return Container();
  }

  @override
  Future<void> showInterstitial() async {
    await _interstitialAd?.show();
  }

  @override
  Future<void> disposeOpenAd() async {
    _appOpenAd?.dispose();
  }

  @override
  Future<void> loadOpenAd() async {
    await AppOpenAd.load(
      adUnitId: "ca-app-pub-3940256099942544/3419835294",
      orientation: AppOpenAd.orientationPortrait,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          showOpenAd();
        },
        onAdFailedToLoad: (error) {
          debugPrint('AppOpenAd failed to load: $error');
          // Handle the error.
        },
      ),
    );
  }

  /// Whether an ad is available to be shown.
  bool get isAdAvailable {
    return _appOpenAd != null;
  }

  @override
  showOpenAd() {
    if (!isAdAvailable) {
      debugPrint('Tried to show ad before available.');
      loadOpenAd();
      return;
    }
    if (_isShowingAd) {
      debugPrint('Tried to show ad while already showing an ad.');
      return;
    }
    // Set the fullScreenContentCallback and show the ad.
    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAd = true;
        debugPrint('$ad onAdShowedFullScreenContent');
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('$ad onAdFailedToShowFullScreenContent: $error');
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('$ad onAdDismissedFullScreenContent');
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadOpenAd();
      },
    );
  }

  @override
  disposeNativeAd() {
    if (_nativeAdIsLoaded && _nativeAd != null) {
      _nativeAd?.dispose();
      _nativeAdIsLoaded = false;
      _nativeAd = null;
    }
  }

  NativeAd? _nativeAd;
  bool _nativeAdIsLoaded = false;

  @override
  Future<void> loadNativeAd() async {
    _nativeAd = NativeAd(
        adUnitId: adModel.nativeAdId ?? nativeAd,
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            debugPrint('$NativeAd loaded.');

            _nativeAdIsLoaded = true;
            onBannerLoaded!(true);
          },
          onAdFailedToLoad: (ad, error) {
            // Dispose the ad here to free resources.
            debugPrint('$NativeAd failed to load: $error');
            ad.dispose();
          },
        ),
        request: const AdRequest(keywords: ['story']),
        // Styling
        factoryId: 'adFactoryExample')
      ..load();
  }

  @override
  Widget showNativeAd(BuildContext context) {
    if (_nativeAd == null) loadNativeAd();
    if (_nativeAdIsLoaded && _nativeAd != null) {
      return SizedBox(
          height: 300,
          width: MediaQuery.of(context).size.width,
          child: new AdWidget(ad: _nativeAd!));
    } else {
      return Container();
    }
  }
}
