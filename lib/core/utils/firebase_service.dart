import 'dart:async';
import 'dart:convert';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../params/ad_backend.dart';

/// Single entry point for Firebase Core, Analytics and Performance.
///
/// The app is a proxy client that is often launched while the network is
/// filtered, so every call here is best-effort: failures are logged and never
/// rethrown. [isReady] is the guard the rest of the app should use; when it is
/// `false` all helpers below are silent no-ops.
///
/// Native configuration comes from `android/app/google-services.json` and
/// `ios/Runner/GoogleService-Info.plist`.
class FirebaseService {
  FirebaseService._();

  static final FirebaseService instance = FirebaseService._();

  /// `Firebase.initializeApp` normally finishes in a few hundred ms; the
  /// timeout only protects the splash if the platform channel gets stuck.
  static const Duration initTimeout = Duration(seconds: 12);

  bool _ready = false;

  /// Firebase is only configured for Android/iOS in this repository. Desktop
  /// and web builds keep working with analytics/push disabled.
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get isReady => _ready;

  /// Boots Firebase and turns collection on for Analytics and Performance.
  ///
  /// Safe to call more than once. Returns `true` when Firebase is usable.
  Future<bool> initialize() async {
    if (_ready) return true;
    if (!isSupportedPlatform) {
      debugPrint('[Firebase] skipped on target platform');
      return false;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp().timeout(initTimeout);
      }
      _ready = true;
    } catch (error) {
      debugPrint('[Firebase] initializeApp failed -> $error');
      return false;
    }

    // Collection defaults to on, but the flags are set explicitly so an old
    // opt-out / restored backup cannot silence a fresh install.
    await _setCollectionEnabled(true);
    return true;
  }

  /// Turns data collection on or off (e.g. from a future "privacy" switch).
  Future<void> setCollectionEnabled(bool enabled) async {
    if (!_ready) return;
    await _setCollectionEnabled(enabled);
  }

  Future<void> _setCollectionEnabled(bool enabled) async {
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
    } catch (error) {
      debugPrint('[Firebase] analytics collection failed -> $error');
    }
    try {
      await FirebasePerformance.instance
          .setPerformanceCollectionEnabled(enabled);
    } catch (error) {
      debugPrint('[Firebase] performance collection failed -> $error');
    }
  }

  /// [FirebaseAnalytics] instance, or `null` while Firebase is not ready.
  FirebaseAnalytics? get analytics =>
      _ready ? FirebaseAnalytics.instance : null;

  /// Logs a custom Analytics event. Parameter values must be `String`/`num`.
  Future<void> logEvent(
    String name, [
    Map<String, Object>? parameters,
  ]) async {
    final analyticsInstance = analytics;
    if (analyticsInstance == null) return;
    try {
      await analyticsInstance.logEvent(name: name, parameters: parameters);
    } catch (error) {
      debugPrint('[Firebase] logEvent($name) failed -> $error');
    }
  }

  /// Reports a named screen.
  ///
  /// GetX routes in this app are anonymous closures, so the automatic
  /// `FirebaseAnalyticsObserver` cannot name them; screens call this instead.
  Future<void> logScreenView(String screenName) async {
    final analyticsInstance = analytics;
    if (analyticsInstance == null) return;
    try {
      await analyticsInstance.logScreenView(screenName: screenName);
    } catch (error) {
      debugPrint('[Firebase] logScreenView($screenName) failed -> $error');
    }
  }

  /// Sends the `app_open` event explicitly (the automatic one can be missed
  /// when Analytics is initialized late).
  Future<void> logAppOpen() async {
    final analyticsInstance = analytics;
    if (analyticsInstance == null) return;
    try {
      await analyticsInstance.logAppOpen();
    } catch (error) {
      debugPrint('[Firebase] logAppOpen failed -> $error');
    }
  }

  /// Sets a user-scoped Analytics property (name <= 24 chars, value <= 36).
  Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    final analyticsInstance = analytics;
    if (analyticsInstance == null) return;
    try {
      await analyticsInstance.setUserProperty(name: name, value: value);
    } catch (error) {
      debugPrint('[Firebase] setUserProperty($name) failed -> $error');
    }
  }

  /// Starts a custom Performance trace.
  ///
  /// Returns `null` when Firebase is not ready, so callers can pass the result
  /// straight back to [finishTrace] without null checks.
  Future<Trace?> startTrace(String name) async {
    if (!_ready) return null;
    try {
      final trace = FirebasePerformance.instance.newTrace(name);
      await trace.start();
      return trace;
    } catch (error) {
      debugPrint('[Firebase] startTrace($name) failed -> $error');
      return null;
    }
  }

  /// Stops [trace] and attaches up to five [attributes] (Performance limit).
  Future<void> finishTrace(
    Trace? trace, [
    Map<String, String> attributes = const <String, String>{},
  ]) async {
    if (trace == null) return;
    try {
      attributes.forEach(trace.putAttribute);
      await trace.stop();
    } catch (error) {
      debugPrint('[Firebase] finishTrace failed -> $error');
    }
  }

  /// Starts an [HttpMetric] for a request made through `Dio`.
  ///
  /// Dart's HTTP stack bypasses OkHttp, so Performance Monitoring cannot see
  /// these calls automatically. The query string is dropped before reporting
  /// because it may contain signatures/nonces.
  Future<HttpMetric?> startHttpMetric(String url, String method) async {
    if (!_ready || url.isEmpty) return null;
    try {
      final safeUrl = Uri.tryParse(url)?.replace(query: '').toString() ?? url;
      final metric = FirebasePerformance.instance.newHttpMetric(
        safeUrl,
        httpMethodFromString(method),
      );
      await metric.start();
      return metric;
    } catch (error) {
      debugPrint('[Firebase] startHttpMetric failed -> $error');
      return null;
    }
  }

  /// Completes [metric]. Values are applied before `stop()` flushes the row.
  Future<void> finishHttpMetric(
    HttpMetric? metric, {
    int? statusCode,
    int? responsePayloadSize,
    int? requestPayloadSize,
    String? responseContentType,
  }) async {
    if (metric == null) return;
    try {
      if (statusCode != null && statusCode > 0) {
        metric.httpResponseCode = statusCode;
      }
      if (responsePayloadSize != null && responsePayloadSize >= 0) {
        metric.responsePayloadSize = responsePayloadSize;
      }
      if (requestPayloadSize != null && requestPayloadSize >= 0) {
        metric.requestPayloadSize = requestPayloadSize;
      }
      if (responseContentType != null && responseContentType.isNotEmpty) {
        metric.responseContentType = responseContentType;
      }
      await metric.stop();
    } catch (error) {
      debugPrint('[Firebase] finishHttpMetric failed -> $error');
    }
  }

  /// Maps an HTTP verb to the Performance Monitoring enum.
  @visibleForTesting
  static HttpMethod httpMethodFromString(String method) {
    switch (method.toUpperCase()) {
      case 'POST':
        return HttpMethod.Post;
      case 'PUT':
        return HttpMethod.Put;
      case 'DELETE':
        return HttpMethod.Delete;
      case 'PATCH':
        return HttpMethod.Patch;
      case 'HEAD':
        return HttpMethod.Head;
      case 'OPTIONS':
        return HttpMethod.Options;
      case 'CONNECT':
        return HttpMethod.Connect;
      case 'TRACE':
        return HttpMethod.Trace;
      default:
        return HttpMethod.Get;
    }
  }

  /// Clears the ready flag between unit tests.
  @visibleForTesting
  void resetForTests() {
    _ready = false;
  }

  /// تحویل توکن FCM به بک‌اند (برای ارسال مستقیم از پنل به این دستگاه).
  Future<void> registerDeviceToken(String token) async {
    try {
      await http
          .post(
            Uri.parse('${AdBackend.defaultBaseUrl}/register-device-token'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'token': token, 'platform': 'android'}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('registerDeviceToken failed: $error');
    }
  }
}
