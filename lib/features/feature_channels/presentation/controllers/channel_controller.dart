import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:proxymodern/core/utils/page_status.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

import '../../../../core/utils/constans.dart';
import '../../../../core/utils/data_extractor.dart';
import '../../../feature_update/presentation/screens/feature_update.dart';
import '../../data/model/channel_model.dart';

class ChannelController extends GetxController {
  String? url;
  ChannelModel? channelModel;
  PageStatus channelStatus = PageStatus.loading;
  List<String> pingList = [];
  RefreshController refreshController =
      RefreshController(initialRefresh: false);

  int itemCount = 0;

  @override
  Future<void> onInit() async {
    // await domainResolvation();
    super.onInit();

    getChannel(false);
  }

  @override
  void onReady() {
    // TODO: implement onReady
    super.onReady();
    // print("onReady");

    getUpdateAvailable();
  }

  getChannel(bool withload) async {
    if (!withload) {
      itemCount = 0;
      pingList = [];
      channelStatus = PageStatus.loading;
      update();
    }

    if (itemCount == 0) {
      itemCount = 20;
    } else {
      if (withload) itemCount += 20;
    }
    url ??= await domainResolvation();
    url ??= "https://host.proplayer.space/proxy/";

    Dio dio = Dio();

    var res =
        await dio.get("${url}index.php?limit_count=$itemCount&channel=all");
    channelModel = ChannelModel.fromJson((res.data));

    if (res.statusCode != 200) {
      channelStatus = PageStatus.error;
      update();
      return;
    }

    if (!withload) {
      channelStatus = PageStatus.success;
    }
    update();

    startPingList();
  }

  Future<String> domainResolvation() async {
    Dio dio = Dio();

    var res = await dio.get(
        "https://raw.githubusercontent.com/mosbahsofttechnology/proxy-modern/main/url.txt"); //

    if (res.statusCode != 200) {
      return "https://host.proplayer.space/proxy/";
    }
    Map urlMap = jsonDecode(res.data);

    url = urlMap["url"];
    return urlMap["url"];
  }

  updateScreen() {
    update();
  }

  getCountryFlagByIP(String ip) async {
    Dio dio = Dio();

    var res = await dio.get("https://ipapi.co/$ip/country/");
    if (res.statusCode != 200) {
      return "https://host.proplayer.space/proxy/";
    }
    return res.data;
  }

  startPingList() async {
    // pingList = [];

    // ignore: unused_local_variable
    for (var item in channelModel!.data!) {
      pingList.add("0");
    }
    update();

    for (var i = 0; i < channelModel!.data!.length; i++) {
      var item = channelModel!.data![i];

      // ignore: unnecessary_null_comparison
      if (pingList[i] != null && pingList[i] != "0") {
        continue;
      }
      var ping = await DataExtractor.pingWithPort(
          DataExtractor.extractFromLink(item.links!, "host"),
          DataExtractor.extractFromLink(item.links!, "port"));

      // if (ping == -1) {
      // pingList[i] = "نامشخص";
      //   update();
      //   continue;
      // }
      pingList[i] = ping.toString();
      update();
    }
  }

  getCountryFlag(String ip) async {
    // https://ip-api.io/api/json/50.7.85.222

    Dio dio = Dio();

    var res = await dio.get(
      "https://ip-api.io/api/json/$ip",
    );

    if (res.statusCode == 200) {
      return res.data["flagUrl"];
    }
  }

  getUpdateAvailable() async {
    // get vesion code
    bool updateAvailable = false;
    Dio dio = Dio();
    var res = await dio.post('https://arianaad.online/updates/proxymodern.php',
        queryParameters: {
          "type": "get",
          "version": versionApplication,
        });

    if (res.statusCode == 200) {
      if (Platform.isAndroid || Platform.isIOS) {
        Map data = json.decode(res.data);

        if (data["data"].toString().contains("no update available!")) {
          updateAvailable = false;
        } else if (data["data"].toString().contains("update available!")) {
          updateAvailable = true;
        } else {
          updateAvailable = true;
        }
        if (updateAvailable) {
          Get.offAll(() => UpdateScreen(
                url: data["link"],
              ));
        }
      } else {
        // print(res.);
      }
    }
  }
}
