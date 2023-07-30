class AdModel {
  String? result;
  String? message;
  AdmobData? data;

  AdModel({this.result, this.message, this.data});

  AdModel.fromJson(Map<String, dynamic> json) {
    result = json['result'];
    message = json['message'];
    data = json['data'] != null ? AdmobData.fromJson(json['data']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['result'] = result;
    data['message'] = message;
    if (this.data != null) {
      data['data'] = this.data!.toJson();
    }
    return data;
  }
}

class AdmobData {
  String? appName;
  String? appId;
  String? bannerAdId;
  String? fullScreenAdId;
  String? nativeAdId;
  String? rewardedAdId;
  String? openAdId;

  AdmobData(
      {this.appName,
      this.appId,
      this.bannerAdId,
      this.fullScreenAdId,
      this.nativeAdId,
      this.rewardedAdId,
      this.openAdId});

  AdmobData.fromJson(Map<String, dynamic> json) {
    appName = json['app_name'];
    appId = json['app_id'];
    bannerAdId = json['banner_ad_id'];
    fullScreenAdId = json['full_screen_ad_id'];
    nativeAdId = json['native_ad_id'];
    rewardedAdId = json['rewarded_ad_id'];
    openAdId = json['open_ad_id'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['app_name'] = appName;
    data['app_id'] = appId;
    data['banner_ad_id'] = bannerAdId;
    data['full_screen_ad_id'] = fullScreenAdId;
    data['native_ad_id'] = nativeAdId;
    data['rewarded_ad_id'] = rewardedAdId;
    data['open_ad_id'] = openAdId;
    return data;
  }
}
