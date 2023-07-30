import 'package:flutter/cupertino.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../models/admob-models.dart';
import '../params/admob-ids-getter.dart';
import 'ad_abstracts.dart';

class AdInitilzer extends MyRewardedAd
    implements MyInterstitialAd, MyBannerAd, MyOpenAd {
  RewardedInterstitialAd? _rewardeInterstitialdAd;
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  AppOpenAd? _appOpenAd;
  bool _isShowingAd = false;

  AdmobData adModel = AdmobDataGetter.getAdmobIds();

  void init() {
    // fill your ad ids
    AdmobData adModel = AdmobDataGetter.getAdmobIds();
    print("adModel is ${adModel.toJson()}");
  }

  @override
  Future<void> disposeRewarded() {
    return _rewardeInterstitialdAd?.dispose() ?? Future.value();
  }

  @override
  Future<void> loadRewarded() async {
    await RewardedInterstitialAd.load(
      adUnitId: "ca-app-pub-3457973144070792/4861584755",
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        // Called when an ad is successfully received.
        onAdLoaded: (ad) {
          debugPrint('$ad loaded.');
          // Keep a reference to the ad so you can show it later.
          _rewardeInterstitialdAd = ad;
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
  Future<void> showRewarded() async {
    if (_rewardeInterstitialdAd == null && _interstitialAd == null) {
      await loadRewarded();
    }
    if (_rewardeInterstitialdAd != null && _interstitialAd == null) {
      await _rewardeInterstitialdAd?.show(
          onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        loadRewarded();
      });
    }
    if (_rewardeInterstitialdAd == null && _interstitialAd != null) {
      await showInterstitial();
    }
    if (_rewardeInterstitialdAd != null && _interstitialAd != null) {
      await _rewardeInterstitialdAd?.show(
          onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        loadRewarded();
      });
    }

    loadRewarded();
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
    _bannerAd = BannerAd(
      adUnitId: "ca-app-pub-3457973144070792/8058007009",
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        // Called when an ad is successfully received.
        onAdLoaded: (ad) {
          debugPrint('$ad loaded.');

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

  @override
  Future<void> loadInterstitial() async {
    await InterstitialAd.load(
        adUnitId: "ca-app-pub-3457973144070792/5853418013",
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          // Called when an ad is successfully received.
          onAdLoaded: (ad) {
            debugPrint('$ad loaded.');
            // Keep a reference to the ad so you can show it later.
            _interstitialAd = ad;
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

  final AdSize adSize = const AdSize(height: 50, width: 300);

  @override
  Widget showBanner() {
    // await _bannerAd?.load();
    if (_bannerAd != null) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: SizedBox(
            width: _bannerAd!.size.width.toDouble(),
            height: _bannerAd!.size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          ),
        ),
      );
    } else {
      return Container();
    }
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
      request: AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          showOpenAd();
        },
        onAdFailedToLoad: (error) {
          print('AppOpenAd failed to load: $error');
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
      print('Tried to show ad before available.');
      loadOpenAd();
      return;
    }
    if (_isShowingAd) {
      print('Tried to show ad while already showing an ad.');
      return;
    }
    // Set the fullScreenContentCallback and show the ad.
    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAd = true;
        print('$ad onAdShowedFullScreenContent');
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        print('$ad onAdFailedToShowFullScreenContent: $error');
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
      },
      onAdDismissedFullScreenContent: (ad) {
        print('$ad onAdDismissedFullScreenContent');
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadOpenAd();
      },
    );
  }
}
