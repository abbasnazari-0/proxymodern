import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/data_extractor.dart';
import '../../../../core/utils/mobile_ads_service.dart';

/// A detail bottom sheet shown when the user taps a proxy in the list.
///
/// Unlike the "found" celebration sheet, this one focuses on the server's
/// technical info: ping, server address + port, and the connect/share actions.
class ProxyInfoSheet {
  static const _card = Color(0xFF101820);
  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);
  static const _telegram = Color(0xFF2AABEE);
  static const _field = Color(0xFF0C141C);
  static const _border = Color(0xFF243140);

  static Future<void> show({
    required String link,
    required String title,
    required String server,
    required String port,
    required String ping,
  }) {
    if (link.isEmpty) return Future.value();

    return Get.bottomSheet(
      _ProxyInfoSheetBody(
        link: link,
        title: title,
        server: server,
        port: port,
        ping: ping,
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

  static Future<void> _copyLink(BuildContext context, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    _showSnack(context, "لینک کپی شد", null);
  }

  static Future<void> _connect(BuildContext context, String link) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    // Show the preloaded connect ad (if ready) before opening Telegram.
    await MobileAdsService.instance.showConnectAdIfReady();
    final ok = await DataExtractor.launchUrl(link);
    if (ok) {
      Get.back();
      return;
    }
    if (!context.mounted) return;
    _showSnack(
      context,
      "تلگرام باز نشد",
      "دکمه کپی را بزن و لینک را در Saved Messages بفرست.",
    );
  }

  /// Shows a bottom snackbar using the sheet's own context. GetX's snackbar
  /// looks up its overlay through the global navigator context, which becomes
  /// unusable right after an app-launch intent (e.g. trying to open Telegram)
  /// and throws "Null check operator used on a null value". Using
  /// ScaffoldMessenger avoids that crash.
  static void _showSnack(BuildContext context, String title, String? message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _card,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: Duration(seconds: message == null ? 2 : 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: _text(size: 14, weight: FontWeight.w700),
              ),
              if (message != null) ...[
                const SizedBox(height: 4),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: _text(size: 12, color: _muted, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      );
      return;
    }
    // Last resort: GetX snackbar, guarded so it can never crash the app.
    try {
      Get.snackbar(
        title,
        message ?? "",
        backgroundColor: _card,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: message == null ? 2 : 3),
      );
    } catch (_) {
      // Swallow — the action (copy / launch) already happened.
    }
  }
}
class _ProxyInfoSheetBody extends StatelessWidget {
  const _ProxyInfoSheetBody({
    required this.link,
    required this.title,
    required this.server,
    required this.port,
    required this.ping,
  });

  final String link;
  final String title;
  final String server;
  final String port;
  final String ping;

  int get _pingValue => int.tryParse(ping) ?? -1;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: ProxyInfoSheet._card,
          borderRadius: BorderRadius.circular(22),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ProxyInfoSheet._text(
                    size: 16,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                _endpointBox(),
                const SizedBox(height: 10),
                _pingRow(),
                const SizedBox(height: 18),
                _connectButton(context),
                const SizedBox(height: 8),
                _shareButton(),
                const SizedBox(height: 8),
                Center(child: _copyButton(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _endpointBox() {
    final endpoint =
        (server.isNotEmpty && port.isNotEmpty) ? "$server:$port" : "—";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: ProxyInfoSheet._field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ProxyInfoSheet._border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.dns_rounded,
            size: 20,
            color: ProxyInfoSheet._accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                endpoint,
                textAlign: TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ProxyInfoSheet._text(
                  size: 15,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pingRow() {
    final value = _pingValue;
    final loading = value == 0;
    final success = value > 0;
    final color = loading
        ? ProxyInfoSheet._muted
        : success
            ? DataExtractor.pingColor(ping)
            : const Color(0xFFFF6B6B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ProxyInfoSheet._field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            "پینگ",
            style: ProxyInfoSheet._text(
              size: 13,
              color: ProxyInfoSheet._muted,
            ),
          ),
          const Spacer(),
          Text(
            loading ? "…" : (success ? "$value ms" : "-1 ms"),
            style: ProxyInfoSheet._text(
              size: 14,
              weight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  Widget _connectButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: ProxyInfoSheet._telegram,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: () => ProxyInfoSheet._connect(context, link),
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
              "اتصال",
              style: ProxyInfoSheet._text(
                size: 15,
                weight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareButton() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: ProxyInfoSheet._border),
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
          style: ProxyInfoSheet._text(
            size: 14,
            weight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _copyButton(BuildContext context) {
    return Material(
      color: ProxyInfoSheet._field,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ProxyInfoSheet._copyLink(context, link),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.copy_rounded,
                size: 16,
                color: ProxyInfoSheet._accent,
              ),
              const SizedBox(width: 6),
              Text(
                "کپی لینک",
                style: ProxyInfoSheet._text(
                  size: 12,
                  weight: FontWeight.w700,
                  color: ProxyInfoSheet._accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
