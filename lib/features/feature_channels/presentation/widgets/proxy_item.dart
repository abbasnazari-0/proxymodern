import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/utils/data_extractor.dart';
import '../../../../core/utils/ping_service.dart';
import '../controllers/channel_controller.dart';
import 'proxy_info_sheet.dart';

class ProxyItemWidget extends StatelessWidget {
  const ProxyItemWidget({
    super.key,
    required this.size,
    required this.ping,
    required this.index,
    this.clickable = true,
  });

  final Size size;
  final String ping;
  final int index;
  final bool clickable;

  static const _card = Color(0xFF101820);
  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);

  ChannelController get _controller => Get.find<ChannelController>();

  String get _link => _controller.channelModel?.data?[index].links ?? "";

  String get _title =>
      _controller.channelModel?.data?[index].title?.trim() ?? "سرور";

  String get _endpoint {
    final host = DataExtractor.queryParam(_link, "server");
    final port = DataExtractor.queryParam(_link, "port");
    if (host == null || port == null || host.isEmpty || port.isEmpty) {
      return "—";
    }
    return "$host:$port";
  }

  String get _time {
    final raw = _controller.channelModel?.data?[index].time ?? "";
    if (raw.isEmpty) return "—";
    return DataExtractor.formatDateTime(raw, format: "HH:mm");
  }

  String? get _photo =>
      _controller.channelModel?.data?[index].photoLink?.trim();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: clickable ? () => _openActions(context) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              _avatar(),
              const SizedBox(width: 12),
              Expanded(child: _info()),
              const SizedBox(width: 8),
              _pingBadge(),
              if (clickable) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_left_rounded, color: Colors.white24, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    final photo = _photo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 48,
        color: const Color(0xFF0C141C),
        child: photo != null && photo.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photo,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(
                  Icons.dns_rounded,
                  color: _accent,
                  size: 22,
                ),
              )
            : const Icon(Icons.dns_rounded, color: _accent, size: 22),
      ),
    );
  }

  Widget _info() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: "vazir",
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            _endpoint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: "vazir",
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "بروزرسانی $_time",
          style: const TextStyle(
            fontFamily: "vazir",
            fontSize: 11,
            color: _muted,
          ),
        ),
      ],
    );
  }

  Widget _pingBadge() {
    final loading = ping == "0";
    final pingValue = int.tryParse(ping);
    final success = !loading && pingValue != null && pingValue > 0;
    final color = loading
        ? _muted
        : success
            ? DataExtractor.pingColor(ping)
            : const Color(0xFFFF6B6B);

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C141C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: loading
          ? const Text(
              "…",
              style: TextStyle(
                fontFamily: "vazir",
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _muted,
              ),
            )
          : Column(
              children: [
                Text(
                  success ? "$pingValue" : "-1",
                  style: TextStyle(
                    fontFamily: "vazir",
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  "ms",
                  style: TextStyle(
                    fontFamily: "vazir",
                    fontSize: 10,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
    );

    return Tooltip(
      message: _detailText(_controller.pingResults[index]),
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: loading ? null : () => _controller.pingOne(index),
        child: badge,
      ),
    );
  }

  String _detailText(PingResult? result) {
    if (result == null) {
      return "برای اندازه‌گیری دوباره ضربه بزن";
    }
    if (!result.isAlive) {
      return "پاسخ نداد (پینگ -1)\nبرای اندازه‌گیری دوباره ضربه بزن";
    }
    return [
      "پینگ: ${result.latency} ms",
      "کمینه: ${result.min} ms",
      "بیشینه: ${result.max} ms",
      "میانگین: ${result.avg} ms",
      "نوسان: ${result.jitter} ms",
      "اتلاف: ${result.loss.toStringAsFixed(0)}%",
    ].join("\n");
  }

  void _openActions(BuildContext context) {
    ProxyInfoSheet.show(
      link: _link,
      title: _title,
      server: DataExtractor.queryParam(_link, "server") ?? "",
      port: DataExtractor.queryParam(_link, "port") ?? "",
      ping: ping,
    );
  }
}
