import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/data_extractor.dart';

class ProxyFoundSheet {
  static const _card = Color(0xFF101820);
  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);
  static const _telegram = Color(0xFF2AABEE);

  static Future<void> show({
    required String link,
    String headline = "پیدا شد",
    String? caption,
  }) {
    if (link.isEmpty) return Future.value();

    return Get.bottomSheet(
      _ProxyFoundSheetBody(
        link: link,
        headline: headline,
        caption: caption,
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

  static Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    Get.snackbar(
      "",
      "",
      backgroundColor: _card,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
      titleText: Text(
        "لینک کپی شد",
        textAlign: TextAlign.center,
        style: _text(size: 14, weight: FontWeight.w700),
      ),
      messageText: const SizedBox.shrink(),
    );
  }

  static Future<void> _connect(String link) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final ok = await DataExtractor.launchUrl(link);
    if (ok) {
      Get.back();
      return;
    }
    Get.snackbar(
      "",
      "",
      backgroundColor: _card,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
      titleText: Text(
        "تلگرام باز نشد",
        textAlign: TextAlign.center,
        style: _text(size: 14, weight: FontWeight.w700),
      ),
      messageText: Text(
        "دکمه کپی را بزن و لینک را در Saved Messages بفرست.",
        textAlign: TextAlign.center,
        style: _text(size: 12, color: _muted, height: 1.4),
      ),
    );
  }
}

class _ProxyFoundSheetBody extends StatelessWidget {
  const _ProxyFoundSheetBody({
    required this.link,
    required this.headline,
    this.caption,
  });

  final String link;
  final String headline;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: ProxyFoundSheet._card,
          borderRadius: BorderRadius.circular(22),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: ProxyFoundSheet._accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: ProxyFoundSheet._accent,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  headline,
                  style: ProxyFoundSheet._text(
                    size: 18,
                    weight: FontWeight.w800,
                  ),
                ),
                if (caption != null && caption!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    caption!,
                    textAlign: TextAlign.center,
                    style: ProxyFoundSheet._text(
                      size: 13,
                      color: ProxyFoundSheet._muted,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ProxyFoundSheet._telegram,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => ProxyFoundSheet._connect(link),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "تلگرام",
                          style: ProxyFoundSheet._text(
                            size: 15,
                            weight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
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
                      if (Platform.isAndroid || Platform.isIOS) {
                        Share.share(link);
                      }
                    },
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(
                      "اشتراک‌گذاری",
                      style: ProxyFoundSheet._text(
                        size: 14,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Material(
                  color: const Color(0xFF0C141C),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => ProxyFoundSheet._copyLink(link),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.copy_rounded,
                            size: 16,
                            color: ProxyFoundSheet._accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "کپی لینک",
                            style: ProxyFoundSheet._text(
                              size: 12,
                              weight: FontWeight.w700,
                              color: ProxyFoundSheet._accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
