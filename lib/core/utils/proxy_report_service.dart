import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'device_identifier.dart';

/// Collects failed-proxy reports into a small in-memory queue and sends them
/// to the server in batches (up to [batchSize] per request), plus a final
/// flush when the ping cycle finishes. This keeps request volume low.
class ProxyReportService {
  ProxyReportService._();
  static final ProxyReportService instance = ProxyReportService._();

  static const int batchSize = 5;
  static const String endpoint =
      "https://api.v1.te.cinimo.ir/proxy/report.php";

  final Dio _dio =
      Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  final List<Map<String, dynamic>> _pending = [];
  bool _sending = false;

  /// Queues one failed proxy. Flushes automatically once the batch is full.
  void addFailedProxy({
    required String? proxyId,
    required String? link,
    required int ping,
  }) {
    _pending.add({
      "proxy_id": proxyId ?? "",
      "link": link ?? "",
      "ping": ping,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });
    if (_pending.length >= batchSize) {
      unawaited(flush());
    }
  }

  /// Sends whatever is queued (used at the end of a ping cycle).
  Future<void> flush() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_pending.isNotEmpty) {
        final count =
            _pending.length < batchSize ? _pending.length : batchSize;
        final batch = _pending.sublist(0, count);
        _pending.removeRange(0, count);
        await _send(batch);
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _send(List<Map<String, dynamic>> batch) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final body = <String, dynamic>{
        "device_id": DeviceIdentifier.id,
        "platform": _platform,
        "app_version": info.buildNumber,
        "reports": batch,
      };
      await _dio.post(endpoint, data: body);
    } catch (e) {
      // Best-effort: drop the batch on failure to avoid infinite retries.
      debugPrint('ProxyReport: send failed -> $e');
    }
  }

  String get _platform {
    if (Platform.isAndroid) return "android";
    if (Platform.isIOS) return "ios";
    return "other";
  }
}
