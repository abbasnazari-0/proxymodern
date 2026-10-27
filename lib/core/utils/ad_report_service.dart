import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Collects ad events (load/show success/fail) into an in-memory queue and
/// reports them to the goshimi backend in HMAC-signed batches.
///
/// Fire-and-forget: a failed send drops the batch (never blocks the ad flow),
/// and without a configured api key the service is a no-op.
class AdReportService {
  AdReportService._();
  static final AdReportService instance = AdReportService._();

  static const int _batchSize = 10;
  static const Duration _flushInterval = Duration(seconds: 20);

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: {'Content-Type': 'application/json'},
  ));

  final List<Map<String, dynamic>> _pending = [];
  Timer? _flushTimer;
  bool _sending = false;

  String _reportUrl = 'https://apps.goshimi.ir/report.php';
  String _apiKey = '';
  String _package = 'default';

  bool get _ready => _apiKey.isNotEmpty;

  /// Configures the service (call once the app's api key / package are known).
  void configure({required String apiKey, String? reportUrl, String? package}) {
    _apiKey = apiKey.trim();
    if (reportUrl != null && reportUrl.isNotEmpty) _reportUrl = reportUrl;
    if (package != null && package.isNotEmpty) _package = package;
  }

  /// Queues one ad event. Auto-flushes when the batch is full.
  void addEvent({
    required String event,
    String unitKey = '',
    String error = '',
    String message = '',
    bool isIr = true,
    String relayUrl = '',
    String countryCode = '',
    int latencyMs = 0,
    int attempt = 0,
    int maxAttempts = 0,
  }) {
    if (!_ready) return;
    _pending.add({
      'event': event,
      'unit_key': unitKey,
      'error': error,
      'message': message,
      'is_ir': isIr ? 1 : 0,
      'relay_url': relayUrl,
      'country_code': countryCode,
      'latency_ms': latencyMs,
      'attempt': attempt,
      'max_attempts': maxAttempts,
    });
    _flushTimer ??= Timer(_flushInterval, () => unawaited(flush()));
    if (_pending.length >= _batchSize) {
      unawaited(flush());
    }
  }

  /// Sends whatever is queued. Best-effort; drops on failure.
  Future<void> flush() async {
    if (_sending || _pending.isEmpty || !_ready) return;
    _sending = true;
    try {
      while (_pending.isNotEmpty) {
        final count =
            _pending.length < _batchSize ? _pending.length : _batchSize;
        final batch = _pending.sublist(0, count);
        _pending.removeRange(0, count);
        await _send(batch);
      }
      _flushTimer?.cancel();
      _flushTimer = null;
    } finally {
      _sending = false;
    }
  }

  Future<void> _send(List<Map<String, dynamic>> batch) async {
    try {
      final body = jsonEncode({'events': batch});
      final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final nonce = DateTime.now().microsecondsSinceEpoch.toString();
      final bodyHash = crypto.sha256.convert(utf8.encode(body)).toString();
      final canonical = '$_package|$ts|$nonce|$bodyHash';
      final sig = crypto.Hmac(crypto.sha256, utf8.encode(_apiKey))
          .convert(utf8.encode(canonical))
          .toString();

      final uri = Uri.parse(_reportUrl).replace(queryParameters: {
        'package': _package,
        'ts': ts,
        'nonce': nonce,
        'sig': sig,
      });
      await _dio.post(uri.toString(), data: body);
    } catch (e) {
      // Best-effort: drop the batch on failure to avoid infinite retries.
      debugPrint('AdReport: send failed -> $e');
    }
  }

  /// Maps a raw SDK error string to a short, stable code for analytics.
  static String classifyError(String message) {
    if (message.contains('NO_FILL')) return 'NO_FILL';
    if (message.contains('INVALID_REQUEST')) return 'INVALID_REQUEST';
    if (message.contains('Account not approved')) return 'Account not approved';
    if (message.contains('Internal error')) return 'Internal error';
    if (message.contains('invalid_state')) return 'invalid_state';
    if (message.contains('timeout') || message.contains('Timeout')) {
      return 'timeout';
    }
    final trimmed = message.trim();
    return trimmed.length > 48 ? trimmed.substring(0, 48) : trimmed;
  }
}
