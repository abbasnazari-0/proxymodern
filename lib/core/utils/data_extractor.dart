import 'package:flutter/material.dart';

import 'dart:io';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

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

  static Color pingColor(String ping) {
    if (ping == "نامشخص") {
      return Colors.grey.shade500;
    }

    if (int.parse(ping) < 0) {
      // اگر پینگ نامشخص است، رنگ خاکستری را برگردانید.
      return Colors.grey.shade500;
    } else if (int.parse(ping) <= 200) {
      // اگر پینگ زیر 100 میلی‌ثانیه است، رنگ سبز را برگردانید.
      return Colors.green.shade500;
    } else if (int.parse(ping) <= 400) {
      // اگر پینگ بین 100 تا 200 میلی‌ثانیه است، رنگ نارنجی را برگردانید.
      return Colors.orange.shade500;
      // } else if (int.parse(ping) <= 300) {
      //   // اگر پینگ بین 200 تا 300 میلی‌ثانیه است، رنگ زرد را برگردانید.
      //   return Colors.yellow.shade500;
    } else {
      // در غیر این صورت، رنگ قرمز را برگردانید.
      return Colors.red.shade500;
    }
  }

  static Future<int> pingWithPort(String address, String port) async {
    final stopwatch = Stopwatch()..start();

    try {
      await Socket.connect(address, int.parse(port),
          timeout: const Duration(seconds: 1));
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return -1;
    }
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
