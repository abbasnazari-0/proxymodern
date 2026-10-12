import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'ping_service.dart';

class DataExtractor {
  static String extractFromLink(String link, String key) {
    Uri uri = Uri.parse(link);
    if (key == "host") {
      return uri.queryParameters["server"]!;
    }
    if (key == "port") {
      return uri.queryParameters["port"]!;
    }
    if (key == "secret") {
      return uri.queryParameters["secret"]!;
    }
    return "";
  }

  static String? queryParam(String link, String key) {
    return Uri.tryParse(link.trim())?.queryParameters[key];
  }

  static String protocolLabel(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return "MTProto";
    final blob = "${uri.host} ${uri.path}".toLowerCase();
    if (blob.contains("socks")) return "SOCKS5";
    return "MTProto";
  }

  static Color pingColor(String ping) {
    final value = int.tryParse(ping);
    if (value == null || value < 0) {
      return Colors.grey.shade500;
    }
    if (value <= 90) {
      return const Color(0xFF2EE6A8); // عالی
    }
    if (value <= 180) {
      return Colors.green.shade500; // خوب
    }
    if (value <= 300) {
      return Colors.amber.shade600; // متوسط
    }
    if (value <= 450) {
      return Colors.orange.shade500; // ضعیف
    }
    return Colors.red.shade500; // بد
  }

  static Future<int> pingWithPort(String address, String port) async {
    final parsedPort = int.tryParse(port);
    if (parsedPort == null) return -1;
    final result = await PingService().pingHost(address, parsedPort);
    return result.latency;
  }

  // convert utc time to mobile timezone
  static String formatDateTime(String dateTimeString,
      {String format = "HH:mm"}) {
    // return dateTimeString;
    DateTime dateTime = DateTime.parse(dateTimeString);

    // add 4.30 hours to convert utc to tehran timezone
    return DateFormat(format).format(dateTime);
  }

  static String transformTelegramLink(String link) {
    link = link.replaceAll(RegExp('(http|https)://telegram.me/'), 'tg://');
    return link.replaceAll(RegExp('(http|https)://t.me/'), 'tg://');
  }

  static Future<bool> launchUrl(String url) async {
    url = transformTelegramLink(url);
    print(url);
    try {
      if (!await launchUrlString(
        url,
        mode: LaunchMode.externalApplication,
        // webOnlyWindowName: 'webOnlyWindowName',

        // forceSafariVC: false,
        // universalLinksOnly: true,
      )) {
        throw Exception('Could not launch $url');
      }
      return true;
    } catch (e) {
      // show error message
      return false;
    }
  }
}
