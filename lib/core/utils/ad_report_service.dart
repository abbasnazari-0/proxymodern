import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../params/ad_backend.dart';
import 'firebase_performance_interceptor.dart';

/// Fire-and-forget reporting of ad load/show events to `report.php`.
///
/// Rules:
/// - Without an API key every call is a no-op.
/// - Events are queued and flushed every 20s or once [batchSize] is reached.
/// - Sending never blocks an ad show; a network failure drops that batch.
/// - The advertising id (AAID/IDFA) is never part of an event.
class AdReportService {
  AdReportService._();

  static final AdReportService instance = AdReportService._();

  /// Hard contract limit per request.
  static const int maxEventsPerRequest = 100;

  /// Batch size used by the app (well below the contract ceiling).
  static const int batchSize = 10;

  static const Duration flushInterval = Duration(seconds: 20);

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {'Content-Type': 'application/json'},
    ),
  )..interceptors.add(FirebasePerformanceInterceptor());

  final List<Map<String, dynamic>> _pending = <Map<String, dynamic>>[];
  Timer? _flushTimer;
  bool _sending = false;

  String _reportUrl = '${AdBackend.defaultBaseUrl}${AdBackend.reportPath}';
  String _apiKey = '';
  String _package = AdBackend.packageName;

  int get pendingCount => _pending.length;

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Called once after a config is applied. Without [apiKey] the service stays
  /// silent. [reportUrl] follows the mirror that served `config.php`.
  void configure({
    required String apiKey,
    String? package,
    String? reportUrl,
  }) {
    _apiKey = apiKey.trim();
    if (package != null && package.trim().isNotEmpty) {
      _package = package.trim();
    }
    if (reportUrl != null && reportUrl.trim().isNotEmpty) {
      _reportUrl = reportUrl.trim();
    }
  }

  /// Queues one event. Never awaits and never throws.
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
    if (_apiKey.isEmpty) return;

    _pending.add(<String, dynamic>{
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

    _ensureFlushTimer();
    if (_pending.length >= batchSize) unawaited(flush());
  }

  void _ensureFlushTimer() {
    if (_flushTimer != null) return;
    _flushTimer = Timer(flushInterval, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  /// Sends the queue in batches. Errors drop the current batch.
  Future<void> flush() async {
    if (_sending || _pending.isEmpty || _apiKey.isEmpty) return;
    _sending = true;
    try {
      while (_pending.isNotEmpty) {
        final take = _pending.length < batchSize ? _pending.length : batchSize;
        final batch = _pending.sublist(0, take);
        _pending.removeRange(0, batch.length);
        await _send(batch);
      }
    } finally {
      _sending = false;
      if (_pending.isNotEmpty) _ensureFlushTimer();
    }
  }

  Future<void> _send(List<Map<String, dynamic>> batch) async {
    try {
      final body = jsonEncode({'events': batch});
      final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final nonce = DateTime.now().microsecondsSinceEpoch.toString();
      final signature = calculateReportSignature(
        apiKey: _apiKey,
        packageName: _package,
        ts: ts,
        nonce: nonce,
        body: body,
      );
      final uri = Uri.parse(_reportUrl).replace(
        queryParameters: <String, String>{
          'package': _package,
          'ts': ts,
          'nonce': nonce,
          'sig': signature,
        },
      );
      await _dio.post(uri.toString(), data: body);
    } catch (error) {
      // Drop this batch: analytics must never affect the ad flow.
      debugPrint('[Ads] report batch dropped -> $error');
    }
  }

  /// `HMAC-SHA256(apiKey, package|ts|nonce|sha256(body))`.
  static String calculateReportSignature({
    required String apiKey,
    required String packageName,
    required String ts,
    required String nonce,
    required String body,
  }) {
    final bodyHash = crypto.sha256.convert(utf8.encode(body)).toString();
    final canonical = '$packageName|$ts|$nonce|$bodyHash';
    return crypto.Hmac(
      crypto.sha256,
      utf8.encode(apiKey),
    ).convert(utf8.encode(canonical)).toString();
  }

  /// Maps an SDK error to the short code used by the panel.
  static String classifyError(String message) {
    final text = message.trim();
    final upper = text.toUpperCase();

    if (upper.contains('NO_FILL') || upper.contains('NO FILL')) {
      return 'NO_FILL';
    }
    if (upper.contains('INVALID_REQUEST')) return 'INVALID_REQUEST';
    if (text.contains('Internal error') || upper.contains('INTERNAL_ERROR')) {
      return 'Internal error';
    }
    if (text.contains('Account not approved')) return 'Account not approved';
    if (upper.contains('TIMEOUT') || upper.contains('TIME OUT')) {
      return 'timeout';
    }
    return text.length > 48 ? text.substring(0, 48) : text;
  }

  /// Clears queue/config between unit tests.
  @visibleForTesting
  void resetForTests() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    _sending = false;
    _apiKey = '';
    _package = AdBackend.packageName;
    _reportUrl = '${AdBackend.defaultBaseUrl}${AdBackend.reportPath}';
  }
}
