import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxymodern/core/params/ad_backend.dart';
import 'package:proxymodern/core/utils/ad_config_api.dart';

const String _package = 'af.arianadeveloper.proxymodern';
const String _nonce = 'nonce123';
final DateTime _now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

Future<String> _encryptSetting(Map<String, dynamic> setting) async {
  final algorithm = AesGcm.with256bits();
  final keyBytes = crypto.sha256.convert(utf8.encode(AdBackend.apiKey)).bytes;
  final secretKey = await algorithm.newSecretKeyFromBytes(keyBytes);
  final nonce = List<int>.generate(12, (index) => index);
  final box = await algorithm.encrypt(
    utf8.encode(jsonEncode(setting)),
    secretKey: secretKey,
    nonce: nonce,
  );
  return base64Encode(<int>[...box.nonce, ...box.cipherText, ...box.mac.bytes]);
}

AdConfigApi _api(http.Client client) => AdConfigApi(
      client: client,
      now: () => _now,
      nonceGenerator: () => _nonce,
    );

void main() {
  group('signing', () {
    test('canonical message matches the backend contract', () {
      expect(
        canonicalConfigMessage(
          packageName: _package,
          platform: 'android',
          version: '20',
          ts: '1700000000',
          nonce: _nonce,
          tz: '210',
          op: '432|11',
        ),
        '$_package|android|20|1700000000|$_nonce|210|432|11',
      );
    });

    test('HMAC-SHA256 matches an independent vector', () {
      final signature = calculateConfigSignature(
        apiKey: AdBackend.apiKey,
        packageName: _package,
        platform: 'android',
        version: '20',
        ts: '1700000000',
        nonce: _nonce,
        tz: '210',
        op: '432|11',
      );
      expect(
        signature,
        '69189bdad60f2940355db6a6bd3f84d42c1280ea44e40912cad8be31be07e95c',
      );
    });

    test('normalises operator and timezone signals', () {
      expect(normalizeOperatorForSignature('43211'), '432|11');
      expect(normalizeOperatorForSignature('432|11'), '432|11');
      expect(normalizeOperatorForSignature('MCI'), '');
      expect(normalizeTimezoneOffset(210), 210);
      expect(normalizeTimezoneOffset(5000), 840);
      expect(normalizeTimezoneOffset(-5000), -840);
    });

    test('builds the signed config URL with every parameter', () {
      final uri = AdConfigApi.buildConfigUri(
        baseUrl: 'apps.goshimi.ir',
        packageName: _package,
        platform: 'android',
        version: '20',
        ts: '1700000000',
        nonce: _nonce,
        tz: '210',
        op: '432|11',
        signature: 'sig',
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'apps.goshimi.ir');
      expect(uri.path, '/config.php');
      expect(uri.queryParameters, <String, String>{
        'package': _package,
        'platform': 'android',
        'version': '20',
        'ts': '1700000000',
        'nonce': _nonce,
        'tz': '210',
        'op': '432|11',
        'sig': 'sig',
      });
    });
  });

  group('AES-256-GCM payload', () {
    test('decrypts nonce|ciphertext|tag with SHA-256(apiKey)', () async {
      final data = await _encryptSetting(<String, dynamic>{
        'ads_status': 1,
        'app_name': 'پروکسی مدرن',
      });
      final setting = await AdConfigApi.decryptSettingData(data);
      expect(setting['ads_status'], 1);
      expect(setting['app_name'], 'پروکسی مدرن');
    });

    test('rejects a payload that is too short', () async {
      await expectLater(
        AdConfigApi.decryptSettingData(base64Encode(<int>[1, 2, 3])),
        throwsA(isA<AdBackendException>()),
      );
    });
  });

  group('config.php failover', () {
    test('rotates to the next domain after an HTTP failure', () async {
      final calls = <Uri>[];
      final client = MockClient((request) async {
        calls.add(request.url);
        if (request.url.host == 'apps.goshimi.ir') {
          return http.Response('blocked', 500);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'result': 'true',
            'setting': <String, dynamic>{'ads_status': 1},
          }),
          200,
        );
      });

      final result = await _api(client).fetchSetting(
        packageName: _package,
        version: '20',
        candidates: const <String>[
          'https://apps.goshimi.ir',
          'https://mirror.example.com',
        ],
        tz: '210',
        op: '432|11',
      );

      expect(result.setting['ads_status'], 1);
      expect(result.baseUrl, 'https://mirror.example.com');
      expect(calls.map((uri) => uri.host), <String>[
        'apps.goshimi.ir',
        'mirror.example.com',
      ]);
      expect(calls.last.path, '/config.php');
      expect(calls.last.queryParameters['sig'], isNotEmpty);
    });

    test('decrypts an encrypted envelope', () async {
      final data = await _encryptSetting(<String, dynamic>{
        'ads_status': 1,
        'app_id': 'ca-app-pub-8261107325783752~3868070072',
      });
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'result': 'true',
            'message': 'ok',
            'encrypted': true,
            'data': data,
          }),
          200,
        );
      });

      final result = await _api(client).fetchSetting(
        packageName: _package,
        version: '20',
        candidates: const <String>['https://apps.goshimi.ir'],
        tz: '210',
        op: '',
      );
      expect(result.setting['ads_status'], 1);
      expect(result.setting['app_id'], contains('~'));
    });

    test('throws when every mirror fails', () async {
      final client = MockClient((request) async {
        throw Exception('connection reset');
      });

      await expectLater(
        _api(client).fetchSetting(
          packageName: _package,
          version: '20',
          candidates: const <String>[
            'https://apps.goshimi.ir',
            'https://mirror.example.com',
          ],
          tz: '210',
          op: '',
        ),
        throwsA(isA<AdBackendException>()),
      );
    });
  });

  group('session.php', () {
    test('signs the request and rotates domains', () async {
      final calls = <Uri>[];
      final client = MockClient((request) async {
        calls.add(request.url);
        if (request.url.host == 'apps.goshimi.ir') {
          throw Exception('timeout');
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'session_id': 'stk-1',
            'relay_name': 'relay-a',
          }),
          200,
        );
      });

      final sessionId = await _api(client).fetchVerifiedSession(
        packageName: _package,
        relayName: 'relay-a',
        candidates: const <String>[
          'https://apps.goshimi.ir',
          'https://mirror.example.com',
        ],
      );

      expect(sessionId, 'stk-1');
      expect(calls.map((uri) => uri.host), <String>[
        'apps.goshimi.ir',
        'mirror.example.com',
      ]);
      expect(calls.last.path, '/session.php');
      expect(calls.last.queryParameters['relay'], 'relay-a');
      expect(
        calls.last.queryParameters['sig'],
        'e72b061e54f340d425f0897f6aaea8cb7f1b5bb0ab2324d9fb5c441d4763b0e5',
      );
    });

    test('empty relay name returns empty without a request', () async {
      final client = MockClient((request) async {
        fail('no request expected');
      });
      final sessionId = await _api(client).fetchVerifiedSession(
        packageName: _package,
        relayName: '',
        candidates: const <String>['https://apps.goshimi.ir'],
      );
      expect(sessionId, '');
    });
  });
}
