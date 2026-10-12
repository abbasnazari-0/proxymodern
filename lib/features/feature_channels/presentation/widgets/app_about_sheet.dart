import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../data/model/channel_model.dart';

class AppAboutSheet {
  static const _card = Color(0xFF101820);
  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);
  static const _storeUrl =
      "https://play.google.com/store/apps/details?id=af.arianadeveloper.proxymodern";

  static Future<void> show({Setting? setting}) async {
    final info = await PackageInfo.fromPlatform();
    return Get.bottomSheet(
      _AppAboutSheetBody(
        setting: setting,
        versionLabel: "${info.version} (${info.buildNumber})",
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
    );
  }

  static TextStyle _text({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color color = Colors.white,
    double? height,
  }) {
    return TextStyle(
      fontFamily: "vazir",
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  static void _shareApp() {
    const message =
        "سوپر پروکسی\nاتصال سریع به تلگرام با یک کلیک\n\n$_storeUrl";
    if (Platform.isAndroid || Platform.isIOS) {
      Share.share(message);
    }
  }
}

class _AppAboutSheetBody extends StatelessWidget {
  const _AppAboutSheetBody({
    required this.versionLabel,
    this.setting,
  });

  final String versionLabel;
  final Setting? setting;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: AppAboutSheet._card,
          borderRadius: BorderRadius.circular(22),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "درباره سوپر پروکسی",
                        textAlign: TextAlign.center,
                        style: AppAboutSheet._text(
                          size: 18,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "نسخه $versionLabel",
                        textAlign: TextAlign.center,
                        style: AppAboutSheet._text(
                          size: 12,
                          color: AppAboutSheet._muted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _section(
                        icon: Icons.route_rounded,
                        title: "چطور وصل می‌شوی؟",
                        body:
                            "۱. دکمه «پیدا کن» را بزن تا یک پروکسی سالم انتخاب شود.\n"
                            "۲. در شیت پایین «تلگرام» را بزن.\n"
                            "۳. داخل تلگرام روی اتصال تأیید کن.\n"
                            "۴. اگر خواستی سرور خاصی داشته باشی، حالت «لیست» را فعال کن.",
                      ),
                      const SizedBox(height: 12),
                      _section(
                        icon: Icons.info_outline_rounded,
                        title: "نکته مهم",
                        body:
                            "این اپ VPN نیست و ترافیک همه برنامه‌ها را عوض نمی‌کند. "
                            "فقط برای اتصال داخل تلگرام طراحی شده است.",
                      ),
                      const SizedBox(height: 12),
                      _section(
                        icon: Icons.groups_rounded,
                        title: "ما کیستیم؟",
                        body:
                            "سوپر پروکسی با هدف ساده‌کردن اتصال به تلگرام ساخته شده است. "
                            "تیم ما روی تجربه سریع، شفاف و بدون پیچیدگی برای کاربران فارسی‌زبان کار می‌کند.",
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 46,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppAboutSheet._accent,
                            foregroundColor: const Color(0xFF062018),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: AppAboutSheet._shareApp,
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: Text(
                            "اشتراک‌گذاری برنامه",
                            style: AppAboutSheet._text(
                              size: 14,
                              weight: FontWeight.w800,
                              color: const Color(0xFF062018),
                            ),
                          ),
                        ),
                      ),
                      if (setting?.shouldUpdate == true) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF243140)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              launchUrlString(
                                setting?.udateUrl ?? AppAboutSheet._storeUrl,
                              );
                            },
                            icon: const Icon(Icons.system_update_rounded, size: 18),
                            label: Text(
                              setting?.updateTitle ?? "به‌روزرسانی",
                              style: AppAboutSheet._text(
                                size: 14,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C141C),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppAboutSheet._accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppAboutSheet._accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppAboutSheet._text(
                    size: 14,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: AppAboutSheet._text(
                    size: 12,
                    color: AppAboutSheet._muted,
                    height: 1.65,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
