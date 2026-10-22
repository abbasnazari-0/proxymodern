class ChannelModel {
  String? result;
  String? message;
  List<ChannelModelData>? data;
  Setting? setting;
  AdConfig? ads;

  ChannelModel(
      {this.result, this.message, this.data, this.setting, this.ads});

  ChannelModel.fromJson(Map<String, dynamic> json) {
    result = json['result'];
    message = json['message'];
    setting =
        json['setting'] != null ? Setting.fromJson(json['setting']) : null;
    // The backend currently merges the ad config into "setting"; also support
    // a dedicated "ads" object if it moves there later.
    final adsJson = json['ads'] ?? json['setting'];
    ads = adsJson != null ? AdConfig.fromJson(adsJson) : null;
    if (json['data'] != null) {
      data = <ChannelModelData>[];
      json['data'].forEach((v) {
        data!.add(ChannelModelData.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['result'] = result;
    data['message'] = message;
    if (this.data != null) {
      data['data'] = this.data!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

class Setting {
  String? version;
  String? updateTitle;
  String? updateDesc;
  String? udateUrl;
  bool? shouldUpdate;

  Setting(
      {this.version,
      this.updateTitle,
      this.updateDesc,
      this.udateUrl,
      this.shouldUpdate});

  Setting.fromJson(Map<String, dynamic> json) {
    version = json['version'];
    updateTitle = json['update_title'];
    updateDesc = json['update_desc'];
    udateUrl = json['update_url'];
    shouldUpdate = bool.parse(json['should_update'].toString());
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['version'] = version;
    data['update_title'] = updateTitle;
    data['update_desc'] = updateDesc;
    data['update_url'] = udateUrl;
    data['should_update'] = shouldUpdate;
    return data;
  }
}

class AdConfig {
  String? appId;
  String? interstitialUnitId;
  String? proxyUrl;
  String? proxyUsername;
  String? proxyPassword;
  String? proxyMode;
  int? showSplashAd;
  int? showConnectAd;
  String? connectInterstitialUnitId;
  int? adMinIntervalSeconds;
  int? adMaxPerSession;
  int? adRetryCount;
  int? proxyTtlSeconds;
  int? timezoneOffsetMinutes;
  String? countryCode;
  String? languageCode;
  List<String>? languageTags;
  String? networkOperatorCode;
  int? prxAa;
  int? adsDisplayStatus;

  AdConfig(
      {this.appId,
      this.interstitialUnitId,
      this.proxyUrl,
      this.proxyUsername,
      this.proxyPassword,
      this.proxyMode,
      this.showSplashAd,
      this.showConnectAd,
      this.connectInterstitialUnitId,
      this.adMinIntervalSeconds,
      this.adMaxPerSession,
      this.adRetryCount,
      this.proxyTtlSeconds,
      this.timezoneOffsetMinutes,
      this.countryCode,
      this.languageCode,
      this.languageTags,
      this.networkOperatorCode,
      this.prxAa,
      this.adsDisplayStatus});

  AdConfig.fromJson(Map<String, dynamic> json) {
    appId = json['app_id'];
    interstitialUnitId = json['interstitial_unit_id'];
    proxyUrl = json['proxy_url'];
    proxyUsername = json['proxy_username'];
    proxyPassword = json['proxy_password'];
    proxyMode = json['proxy_mode'];
    showSplashAd = json['show_splash_ad'] != null
        ? int.tryParse(json['show_splash_ad'].toString())
        : null;
    showConnectAd = json['show_connect_ad'] != null
        ? int.tryParse(json['show_connect_ad'].toString())
        : null;
    connectInterstitialUnitId = json['connect_interstitial_unit_id'];
    adMinIntervalSeconds = json['ad_min_interval_seconds'] != null
        ? int.tryParse(json['ad_min_interval_seconds'].toString())
        : null;
    adMaxPerSession = json['ad_max_per_session'] != null
        ? int.tryParse(json['ad_max_per_session'].toString())
        : null;
    adRetryCount = json['ad_retry_count'] != null
        ? int.tryParse(json['ad_retry_count'].toString())
        : null;
    proxyTtlSeconds = json['proxy_ttl_seconds'] != null
        ? int.tryParse(json['proxy_ttl_seconds'].toString())
        : null;
    timezoneOffsetMinutes = json['timezone_offset_minutes'];
    countryCode = json['country_code'];
    languageCode = json['language_code'];
    if (json['language_tags'] != null) {
      languageTags = List<String>.from(json['language_tags']);
    }
    networkOperatorCode = json['network_operator_code'];
    prxAa = json['prx_aa'];
    adsDisplayStatus = json['ads_display_status'] != null
        ? int.tryParse(json['ads_display_status'].toString())
        : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['app_id'] = appId;
    data['interstitial_unit_id'] = interstitialUnitId;
    data['proxy_url'] = proxyUrl;
    data['proxy_username'] = proxyUsername;
    data['proxy_password'] = proxyPassword;
    data['proxy_mode'] = proxyMode;
    data['show_splash_ad'] = showSplashAd;
    data['show_connect_ad'] = showConnectAd;
    data['connect_interstitial_unit_id'] = connectInterstitialUnitId;
    data['ad_min_interval_seconds'] = adMinIntervalSeconds;
    data['ad_max_per_session'] = adMaxPerSession;
    data['ad_retry_count'] = adRetryCount;
    data['proxy_ttl_seconds'] = proxyTtlSeconds;
    data['timezone_offset_minutes'] = timezoneOffsetMinutes;
    data['country_code'] = countryCode;
    data['language_code'] = languageCode;
    data['language_tags'] = languageTags;
    data['network_operator_code'] = networkOperatorCode;
    data['prx_aa'] = prxAa;
    data['ads_display_status'] = adsDisplayStatus;
    return data;
  }
}

class ChannelModelData {
  String? id;
  String? messageId;
  String? channelId;
  String? links;
  String? time;
  String? photoLink;
  String? title;

  ChannelModelData(
      {this.id,
      this.messageId,
      this.channelId,
      this.links,
      this.time,
      this.photoLink,
      this.title});

  ChannelModelData.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    messageId = json['message_id'];
    channelId = json['channel_id'];
    links = json['links'];
    time = json['time'];
    photoLink = json['photo_link'];
    title = json['title'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['message_id'] = messageId;
    data['channel_id'] = channelId;
    data['links'] = links;
    data['time'] = time;
    data['photo_link'] = photoLink;
    data['title'] = title;
    return data;
  }
}
