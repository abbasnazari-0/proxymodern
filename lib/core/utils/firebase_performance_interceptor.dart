import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

import 'firebase_service.dart';

/// Reports `Dio` requests to Firebase Performance.
///
/// Dart's HTTP stack does not go through OkHttp, so Performance Monitoring
/// cannot instrument these calls automatically; one [HttpMetric] per request
/// makes them visible in the Firebase console (latency, status code, payload).
///
/// The interceptor is a pass-through when Firebase is unavailable and never
/// throws: networking must never depend on analytics.
class FirebasePerformanceInterceptor extends Interceptor {
  static const String _metricKey = 'firebase_performance_metric';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    unawaited(_attachMetric(options));
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    unawaited(
      _finishMetric(
        response.requestOptions,
        statusCode: response.statusCode,
        contentLength: _contentLength(response.headers),
        contentType: response.headers.value(Headers.contentTypeHeader),
      ),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    unawaited(
      _finishMetric(
        err.requestOptions,
        statusCode: response?.statusCode,
        contentLength:
            response == null ? null : _contentLength(response.headers),
        contentType: response?.headers.value(Headers.contentTypeHeader),
      ),
    );
    handler.next(err);
  }

  /// `Headers.contentLength` was removed in Dio 5; read the raw header.
  static int? _contentLength(Headers headers) {
    final raw = headers.value(Headers.contentLengthHeader);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  Future<void> _attachMetric(RequestOptions options) async {
    try {
      final metric = await FirebaseService.instance.startHttpMetric(
        options.uri.toString(),
        options.method,
      );
      if (metric != null) options.extra[_metricKey] = metric;
    } catch (error) {
      debugPrint('[Perf] metric start failed -> $error');
    }
  }

  Future<void> _finishMetric(
    RequestOptions options, {
    int? statusCode,
    int? contentLength,
    String? contentType,
  }) async {
    try {
      final metric = options.extra.remove(_metricKey);
      if (metric is! HttpMetric) return;
      await FirebaseService.instance.finishHttpMetric(
        metric,
        statusCode: statusCode,
        responsePayloadSize: contentLength,
        responseContentType: contentType,
      );
    } catch (error) {
      debugPrint('[Perf] metric finish failed -> $error');
    }
  }
}
