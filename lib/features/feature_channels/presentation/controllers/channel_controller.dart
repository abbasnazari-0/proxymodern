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

enum FindPhase { idle, searching, found, failed }

class ChannelController extends GetxController {
  static const Duration _minInitialLoad = Duration(milliseconds: 550);
  static const Duration _minFindDuration = Duration(milliseconds: 900);
  static const Duration _requestTimeout = Duration(seconds: 14);
  static const Duration _pingStagger = Duration(milliseconds: 40);

  String? url;
  ChannelModel? channelModel;
  PageStatus channelStatus = PageStatus.loading;
  List<String> pingList = [];
  RefreshController refreshController =
      RefreshController(initialRefresh: false);

  int itemCount = 0;
  int? selectedIndex;
  Future<void>? _channelFuture;
  int listRevealToken = 0;

  String errorTitle = "لیست دریافت نشد";
  String errorMessage = "اتصال را بررسی کن و دوباره تلاش کن.";
  FindPhase findPhase = FindPhase.idle;

  @override
  Future<void> onInit() async {
    // await domainResolvation();
    super.onInit();

    _channelFuture = getChannel(false);
  }

  @override
  void onReady() {
    super.onReady();
    // print("onReady");

    getUpdateAvailable();
  }

  Future<bool> getChannel(bool withload) async {
    final startedAt = DateTime.now();
    final hadData = channelModel?.data?.isNotEmpty ?? false;

    try {
      if (!withload) {
        itemCount = 0;
        pingList = [];
        channelStatus = PageStatus.loading;
        errorTitle = "لیست دریافت نشد";
        errorMessage = "اتصال را بررسی کن و دوباره تلاش کن.";
        update();
      }

      if (itemCount == 0) {
        itemCount = 20;
      } else if (withload) {
        itemCount += 20;
      }

      url ??= await domainResolvation();
      url ??= "https://api.v1.te.cinimo.ir/proxy/";

      final dio = Dio(
        BaseOptions(
          connectTimeout: _requestTimeout,
          receiveTimeout: _requestTimeout,
          sendTimeout: _requestTimeout,
        ),
      );

      String platform = '';
      if (Platform.isAndroid) {
        platform = 'android';
      } else if (Platform.isIOS) {
        platform = 'ios';
      } else if (Platform.isWindows) {
        platform = 'windows';
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final buildNumber = packageInfo.buildNumber;

      final res = await dio.get(
        "${url}index.php?limit_count=$itemCount&channel=all&platform=$platform&version=$buildNumber",
      );

      if (res.statusCode != 200) {
        _failLoad(
          withload: withload,
          hadData: hadData,
          title: "خطای سرور",
          message: "سرور پاسخ درستی نداد (کد ${res.statusCode}).",
        );
        return false;
      }

      final parsed = ChannelModel.fromJson(res.data);
      final items = parsed.data ?? <ChannelModelData>[];

      if (items.isEmpty) {
        if (!withload) {
          channelModel = parsed;
          channelStatus = PageStatus.empty;
          errorTitle = "لیست خالی است";
          errorMessage = "الان پروکسی فعالی برای نمایش وجود ندارد.";
          update();
          return false;
        }
        _failLoad(
          withload: withload,
          hadData: hadData,
          title: "مورد جدیدی نیست",
          message: "همه سرورها قبلاً بارگذاری شده‌اند.",
        );
        return false;
      }

      channelModel = parsed;
      listRevealToken++;

      if (!withload) {
        final elapsed = DateTime.now().difference(startedAt);
        if (elapsed < _minInitialLoad) {
          await Future.delayed(_minInitialLoad - elapsed);
        }
        channelStatus = PageStatus.success;
      }
      update();
      return true;
    } on DioException catch (e) {
      _failLoad(
        withload: withload,
        hadData: hadData,
        title: _dioErrorTitle(e),
        message: _dioErrorMessage(e),
      );
      return false;
    } on FormatException {
      _failLoad(
        withload: withload,
        hadData: hadData,
        title: "خطای داده",
        message: "پاسخ سرور قابل خواندن نبود.",
      );
      return false;
    } catch (_) {
      _failLoad(
        withload: withload,
        hadData: hadData,
        title: "خطای ناشناخته",
        message: "یک مشکل غیرمنتظره رخ داد. دوباره تلاش کن.",
      );
      return false;
    }
  }

  void _failLoad({
    required bool withload,
    required bool hadData,
    required String title,
    required String message,
  }) {
    errorTitle = title;
    errorMessage = message;

    if (withload && hadData) {
      channelStatus = PageStatus.success;
      update();
      return;
    }

    channelStatus = PageStatus.error;
    update();
  }

  String _dioErrorTitle(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return "اتصال کند شد";
      case DioExceptionType.connectionError:
        return "اینترنت قطع است";
      case DioExceptionType.badResponse:
        return "پاسخ نامعتبر";
      case DioExceptionType.cancel:
        return "درخواست لغو شد";
      default:
        return "خطا در دریافت لیست";
    }
  }

  String _dioErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return "زمان درخواست تمام شد. دوباره امتحان کن.";
      case DioExceptionType.connectionError:
        return "به شبکه وصل نیستی یا سرور در دسترس نیست.";
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code != null) {
          return "سرور خطای $code برگرداند.";
        }
        return "سرور پاسخ درستی نداد.";
      case DioExceptionType.cancel:
        return "درخواست قبل از اتمام متوقف شد.";
      default:
        return "مشکلی در ارتباط با سرور پیش آمد.";
    }
  }

  Future<void> waitForInitialLoad() async {
    if (channelStatus == PageStatus.loading && _channelFuture != null) {
      await _channelFuture;
    }
  }

  Future<bool> ensureChannels() async {
    final items = channelModel?.data;
    if (items != null && items.isNotEmpty) {
      if (channelStatus != PageStatus.success) {
        channelStatus = PageStatus.success;
        update();
      }
      return true;
    }
    if (channelStatus == PageStatus.loading && _channelFuture != null) {
      await _channelFuture;
    } else {
      _channelFuture = getChannel(false);
      await _channelFuture;
    }
    return channelStatus == PageStatus.success &&
        (channelModel?.data?.isNotEmpty ?? false);
  }

  int? _bestPingIndex(List<int> indexes) {
    int? best;
    var bestPing = 1 << 30;
    for (final i in indexes) {
      final ping = int.tryParse(pingList[i]) ?? -1;
      if (ping > 0 && ping < bestPing) {
        best = i;
        bestPing = ping;
      }
    }
    return best;
  }

  int? _fallbackIndex(List<int> indexes, List<ChannelModelData> data) {
    for (final i in indexes) {
      final link = data[i].links ?? "";
      final host = DataExtractor.queryParam(link, "server");
      final port = DataExtractor.queryParam(link, "port");
      if (host != null &&
          host.isNotEmpty &&
          port != null &&
          port.isNotEmpty &&
          link.isNotEmpty) {
        return i;
      }
    }
    return indexes.isEmpty ? null : indexes.first;
  }

  /// Pings the loaded list and returns the fastest responding proxy.
  Future<int?> findWorkingProxy({int? excludeIndex}) async {
    final startedAt = DateTime.now();
    findPhase = FindPhase.searching;
    update();

    final ready = await ensureChannels();
    if (!ready) {
      findPhase = FindPhase.failed;
      if (channelStatus == PageStatus.empty) {
        errorTitle = "لیست خالی است";
        errorMessage = "الان پروکسی فعالی برای اتصال وجود ندارد.";
      }
      update();
      return null;
    }

    final data = channelModel!.data!;
    if (pingList.length != data.length) {
      pingList = List<String>.filled(data.length, "0");
    }

    final indexes = <int>[
      for (var i = 0; i < data.length; i++)
        if (i != excludeIndex) i,
    ];

    if (indexes.isEmpty) {
      findPhase = FindPhase.failed;
      errorTitle = "سرور دیگری نیست";
      errorMessage = "همه سرورهای موجود بررسی شدند.";
      update();
      return null;
    }

    final needsPing = indexes.where((i) {
      final ping = int.tryParse(pingList[i]) ?? 0;
      return ping <= 0;
    }).toList();

    if (needsPing.isNotEmpty) {
      await Future.wait(needsPing.map((i) => _pingAt(i, data[i])));
    }

    var best = _bestPingIndex(indexes);
    best ??= _fallbackIndex(indexes, data);

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < _minFindDuration) {
      await Future.delayed(_minFindDuration - elapsed);
    }

    if (best != null) {
      selectedIndex = best;
      findPhase = FindPhase.found;
      update();
      return best;
    }

    findPhase = FindPhase.failed;
    errorTitle = "پروکسی سالم پیدا نشد";
    errorMessage =
        "سرورها پاسخ ندادند. چند لحظه بعد دوباره دکمه را بزن.";
    update();
    return null;
  }

  Future<void> _pingAt(int index, ChannelModelData item) async {
    final link = item.links ?? "";
    final host = DataExtractor.queryParam(link, "server");
    final port = DataExtractor.queryParam(link, "port");
    if (host == null || host.isEmpty || port == null || port.isEmpty) {
      pingList[index] = "-1";
      return;
    }
    final ping = await DataExtractor.pingWithPort(host, port);
    pingList[index] = ping.toString();
  }

  Future<String> domainResolvation() async {
    Dio dio = Dio();

    var res = await dio.get(
        "https://raw.githubusercontent.com/mosbahsofttechnology/proxy-modern/main/url.txt"); //

    if (res.statusCode != 200) {
      return "https://api.v1.te.cinimo.ir/proxy/";
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
      return "https://api.v1.te.cinimo.ir/proxy/";
    }
    return res.data;
  }

  Future<void> startPingList() async {
    final data = channelModel?.data;
    if (data == null || data.isEmpty) return;

    pingList = List<String>.filled(data.length, "0");
    update();

    for (var i = 0; i < data.length; i++) {
      if (pingList.length != data.length) break;
      if (pingList[i] != "0") continue;

      await _pingAt(i, data[i]);
      update();
      await Future.delayed(_pingStagger);
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
