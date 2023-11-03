import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:proxymodern/core/utils/page_status.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

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

    Dio dio = Dio();
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    String buildNumber = packageInfo.buildNumber;

    var res = await dio.get(
        "https://raw.githubusercontent.com/mosbahsofttechnology/proxy-modern/main/update");

    if (res.statusCode == 200) {
      if (Platform.isAndroid || Platform.isIOS) {
        Map data = json.decode(res.data);

        if (int.parse(data["version"]) > int.parse(buildNumber)) {
          Get.offAll(() => UpdateScreen(url: data["link"]));
        }
      } else {
        // print(res.);
      }
    }
  }
}
