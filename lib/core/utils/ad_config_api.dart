import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/ad_config.dart';
import '../params/ad_backend.dart';

/// Failure while fetching/decrypting the backend config.
class AdBackendException implements Exception {
  const AdBackendException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final suffix = cause == null ? '' : ' ($cause)';
    return 'AdBackendException: $message$suffix';
  }
}

/// A successful `config.php` response plus the mirror that served it.
class AdConfigFetchResult {
  const AdConfigFetchResult({required this.setting, required this.baseUrl});

  final Map<String, dynamic> setting;
  final String baseUrl;
}

/// Canonical string signed for a `config.php` request:
/// `<package>|<platform>|<version>|<ts>|<nonce>|<tz>|<op>`.
///
/// `tz` is the device timezone offset in minutes, east positive (Tehran = 210).
/// `op` is the operator as `MCC|MNC`, or an empty string when unavailable.
String canonicalConfigMessage({
  required String packageName,
  required String platform,
  required String version,
  required String ts,
  required String nonce,
  required String tz,
  required String op,
}) =>
    '$packageName|$platform|$version|$ts|$nonce|$tz|$op';

/// `HMAC-SHA256(apiKey, canonicalConfigMessage(...))`.
String calculateConfigSignature({
  required String apiKey,
  required String packageName,
  required String platform,
  required String version,
  required String ts,
  required String nonce,
  required String tz,
  required String op,
}) {
  final canonical = canonicalConfigMessage(
    packageName: packageName,
    platform: platform,
    version: version,
    ts: ts,
    nonce: nonce,
    tz: tz,
    op: op,
  );
  return crypto.Hmac(
    crypto.sha256,
    utf8.encode(apiKey),
  ).convert(utf8.encode(canonical)).toString();
}

/// Normalises a device timezone offset into the backend range.
int normalizeTimezoneOffset(int value) => value.clamp(-840, 840).toInt();

/// Normalises an operator signal to `MCC|MNC`.
///
/// `MobileAds.deviceSignals()` already returns `432|11`, but some OEM ROMs
/// return `43211`; both must sign the same canonical value.
String normalizeOperatorForSignature(String value) {
  final text = value.trim();
  if (RegExp(r'^[0-9]{3}\|[0-9]{1,3}$').hasMatch(text)) return text;
  if (RegExp(r'^[0-9]{5,6}$').hasMatch(text)) {
    return '${text.substring(0, 3)}|${text.substring(3)}';
  }
  return '';
}

/// HTTP client for the signed/encrypted backend contract.
///
/// The API itself is stateless: the caller supplies the ordered mirror list
/// (see `DomainResolver`) and gets back the mirror that answered. This keeps
/// rotation logic testable with a fake `http.Client`.
class AdConfigApi {
  AdConfigApi({
    http.Client? client,
    this.apiKey = AdBackend.apiKey,
    DateTime Function()? now,
    String Function()? nonceGenerator,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _now = now ?? DateTime.now,
        _nonceGenerator = nonceGenerator ?? _randomNonce;

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final String Function() _nonceGenerator;
  final String apiKey;

  /// Fetches `setting` from the first mirror that answers.
  ///
  /// Every attempt gets a fresh `ts` + `nonce` so the ±10 minute replay window
  /// always holds. A timeout / DNS error / non-200 rotates to the next domain.
  Future<AdConfigFetchResult> fetchSetting({
    required String packageName,
    required String version,
    required List<String> candidates,
    required String tz,
    required String op,
    Duration timeout = AdBackend.requestTimeout,
    String platform = AdBackend.platform,
  }) async {
    final mirrors = candidates.isEmpty
        ? const <String>[AdBackend.defaultBaseUrl]
        : candidates;

    Object? lastError;
    for (final candidate in mirrors) {
      final baseUrl = normalizeBaseUrl(candidate) ?? AdBackend.defaultBaseUrl;
      try {
        final ts = (_now().millisecondsSinceEpoch ~/ 1000).toString();
        final nonce = _nonceGenerator();
        final signature = calculateConfigSignature(
          apiKey: apiKey,
          packageName: packageName,
          platform: platform,
          version: version,
          ts: ts,
          nonce: nonce,
          tz: tz,
          op: op,
        );
        final uri = buildConfigUri(
          baseUrl: baseUrl,
          packageName: packageName,
          platform: platform,
          version: version,
          ts: ts,
          nonce: nonce,
          tz: tz,
          op: op,
          signature: signature,
        );

        final response = await _client.get(uri,
            headers: const {'Accept': 'application/json'}).timeout(timeout);
        if (response.statusCode != 200) {
          throw AdBackendException(
            'config.php returned HTTP ${response.statusCode}',
          );
        }

        final setting = await _parseEnvelope(response.bodyBytes);
        debugPrint('[Ads] config fetched from $baseUrl');
        return AdConfigFetchResult(setting: setting, baseUrl: baseUrl);
      } catch (error) {
        lastError = error;
        debugPrint('[Ads] config fetch failed on $baseUrl -> $error');
      }
    }

    throw AdBackendException(
      'every backend domain failed for config.php',
      cause: lastError,
    );
  }

  /// Signed URL for `config.php` (public for tests/tools).
  static Uri buildConfigUri({
    required String baseUrl,
    required String packageName,
    required String platform,
    required String version,
    required String ts,
    required String nonce,
    required String tz,
    required String op,
    required String signature,
  }) {
    final base = normalizeBaseUrl(baseUrl) ?? AdBackend.defaultBaseUrl;
    return Uri.parse('$base${AdBackend.configPath}').replace(
      queryParameters: <String, String>{
        'package': packageName,
        'platform': platform,
        'version': version,
        'ts': ts,
        'nonce': nonce,
        'tz': tz,
        'op': op,
        'sig': signature,
      },
    );
  }

  /// Requests a backend-verified sticky session from `session.php`.
  ///
  /// Signature: `HMAC-SHA256(apiKey, package|relay|ts|nonce)`.
  /// Returns an empty string when the relay runs in rotation mode or every
  /// mirror failed; the caller then uses the plain proxy username.
  Future<String> fetchVerifiedSession({
    required String packageName,
    required String relayName,
    required List<String> candidates,
    Duration timeout = AdBackend.requestTimeout,
  }) async {
    if (relayName.trim().isEmpty) return '';
    final mirrors = candidates.isEmpty
        ? const <String>[AdBackend.defaultBaseUrl]
        : candidates;

    for (final candidate in mirrors) {
      final baseUrl = normalizeBaseUrl(candidate) ?? AdBackend.defaultBaseUrl;
      try {
        final ts = (_now().millisecondsSinceEpoch ~/ 1000).toString();
        final nonce = _nonceGenerator();
        final canonical = '$packageName|${relayName.trim()}|$ts|$nonce';
        final signature = crypto.Hmac(
          crypto.sha256,
          utf8.encode(apiKey),
        ).convert(utf8.encode(canonical)).toString();

        final uri = Uri.parse('$baseUrl${AdBackend.sessionPath}').replace(
          queryParameters: <String, String>{
            'package': packageName,
            'relay': relayName.trim(),
            'ts': ts,
            'nonce': nonce,
            'sig': signature,
          },
        );

        var response = await _client.get(uri,
            headers: const {'Accept': 'application/json'}).timeout(timeout);
        if (response.statusCode != 200) {
          // The contract allows POST as well; retry once on the same mirror.
          response = await _client.post(uri,
              headers: const {'Accept': 'application/json'}).timeout(timeout);
        }
        if (response.statusCode != 200) {
          throw AdBackendException(
            'session.php returned HTTP ${response.statusCode}',
          );
        }

        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) return '';
        final sessionId = decoded['session_id'];
        if (sessionId is String) return sessionId.trim();
        return '';
      } catch (error) {
        debugPrint('[Ads] session fetch failed on $baseUrl -> $error');
      }
    }
    return '';
  }

  /// Decrypts the AES-256-GCM `data` payload.
  ///
  /// Layout: `nonce(12) || ciphertext || tag(16)`; key = `SHA-256(apiKey)`.
  static Future<Map<String, dynamic>> decryptSettingData(
    String data, {
    String apiKey = AdBackend.apiKey,
  }) async {
    final raw = _decodeBase64(data);
    if (raw.length < 12 + 16) {
      throw const AdBackendException('encrypted payload is shorter than 28B');
    }

    final nonce = raw.sublist(0, 12);
    final cipherText = raw.sublist(12, raw.length - 16);
    final tag = raw.sublist(raw.length - 16);
    final keyBytes = crypto.sha256.convert(utf8.encode(apiKey)).bytes;

    List<int> clear;
    try {
      final algorithm = AesGcm.with256bits();
      clear = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: await algorithm.newSecretKeyFromBytes(keyBytes),
      );
    } catch (error) {
      throw AdBackendException('AES-256-GCM decryption failed', cause: error);
    }

    return _decodeJsonMap(utf8.decode(clear));
  }

  Future<Map<String, dynamic>> _parseEnvelope(List<int> bodyBytes) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes));
    } catch (error) {
      throw AdBackendException('backend response is not JSON', cause: error);
    }
    if (decoded is! Map) {
      throw const AdBackendException('backend response must be an object');
    }
    final map = Map<String, dynamic>.from(decoded);

    final result = map['result'];
    if (result != null && result.toString().toLowerCase() != 'true') {
      throw AdBackendException(
        'backend returned an error: ${map['message'] ?? result}',
      );
    }

    final setting = map['setting'];
    if (setting is Map) return Map<String, dynamic>.from(setting);
    if (setting is String && setting.trim().isNotEmpty) {
      return _decodeJsonMap(setting);
    }

    final data = map['data'];
    if (data is String && data.trim().isNotEmpty) {
      return decryptSettingData(data, apiKey: apiKey);
    }

    throw const AdBackendException(
      'backend response has neither setting nor data',
    );
  }

  /// Frees the owned HTTP client (tests/tools); the singleton never calls it.
  void close() {
    if (_ownsClient) _client.close();
  }
}

Map<String, dynamic> _decodeJsonMap(String source) {
  dynamic value;
  try {
    value = jsonDecode(source);
  } catch (error) {
    throw AdBackendException('setting is not valid JSON', cause: error);
  }
  if (value is String) {
    try {
      value = jsonDecode(value);
    } catch (error) {
      throw AdBackendException('setting is not valid JSON', cause: error);
    }
  }
  if (value is! Map) {
    throw const AdBackendException('setting must be a JSON object');
  }
  return Map<String, dynamic>.from(value);
}

List<int> _decodeBase64(String data) {
  final normalized = data.trim().replaceAll(RegExp(r'\s+'), '');
  try {
    return base64Decode(normalized);
  } on FormatException {
    // Some backends emit base64url without padding.
  }
  try {
    return base64Url.decode(base64Url.normalize(normalized));
  } on FormatException catch (error) {
    throw AdBackendException('invalid base64 payload', cause: error);
  }
}

String _randomNonce() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
