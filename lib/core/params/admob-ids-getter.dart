import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/admob-models.dart';
import '../utils/get_storage_data.dart';

class AdmobDataGetter {
  static const String sheetUrl =
      "https://amindevelop.ir/admobmanager/api/getData.php?name=proxy_man";

  static void init() async {
    // RequestConfiguration configuration = RequestConfiguration(
    //     testDeviceIds: ["19A8443085122C9CC018039F788100CA"]);
    // MobileAds.instance.updateRequestConfiguration(configuration);

    await loadAdmobIds();
  }

  static getAdmobIds() {
    if (GetStorageData.getData("admob") != null) {
      AdmobData adModel = AdmobData.fromJson(GetStorageData.getData("admob"));
      return adModel;
    } else {
      loadAdmobIds();
      return AdmobData(
        bannerAdId: "ca-app-pub-3940256099942544/6300978111",
        fullScreenAdId: "ca-app-pub-3940256099942544/1033173712",
        nativeAdId: "ca-app-pub-3940256099942544/2247696110",
        rewardedAdId: "ca-app-pub-3940256099942544/5224354917",
      );
    }
  }

  static loadAdmobIds() async {
    final response = await Dio().get(sheetUrl);
    // return AdModel.fromJson(response.data);

    // print(response.data);
    // List lApp = List<Map<String, dynamic>>.from(jsonDecode(response.data));
    AdModel adModels = AdModel.fromJson(response.data);

    if (adModels.message == "success" && adModels.result == "true") {
      GetStorageData.writeData("admob", adModels.data?.toJson());
    } else {
      // GetStorageData.writeData("admob", AdModel().toJson());
    }

    if (kDebugMode) {
      print(GetStorageData.getData("admob"));
    }
  }
}
