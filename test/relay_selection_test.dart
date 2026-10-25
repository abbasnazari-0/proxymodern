import 'package:flutter_test/flutter_test.dart';
import 'package:proxymodern/core/utils/mobile_ads_service.dart';
import 'package:proxymodern/features/feature_channels/data/model/channel_model.dart';

void main() {
  group('pickFastestRelay', () {
    test('picks the lowest latency', () {
      expect(
        pickFastestRelay([
          ('http://a:8081', 120),
          ('http://b:8081', 40),
          ('http://c:8081', 90),
        ]),
        'http://b:8081',
      );
    });

    test('ignores unreachable relays (null latency)', () {
      expect(
        pickFastestRelay([
          ('http://a:8081', null),
          ('http://c:8081', 70),
        ]),
        'http://c:8081',
      );
    });

    test('returns null when everything is unreachable', () {
      expect(
        pickFastestRelay([
          ('http://a:8081', null),
          ('http://b:8081', null),
        ]),
        isNull,
      );
    });
  });

  group('AdConfig.proxyCandidates', () {
    test('filters empty entries and keeps order', () {
      final config = AdConfig(
        proxyUrl: 'http://a:8081',
        proxyUrl2: '',
        proxyUrl3: 'http://c:8081',
      );
      expect(config.proxyCandidates, ['http://a:8081', 'http://c:8081']);
    });

    test('parses proxy_url_2/3 from json', () {
      final config = AdConfig.fromJson({
        'proxy_url': 'http://a:8081',
        'proxy_url_2': 'http://b:8081',
        'proxy_url_3': 'http://c:8081',
      });
      expect(
        config.proxyCandidates,
        ['http://a:8081', 'http://b:8081', 'http://c:8081'],
      );
    });

    test('round-trips candidates through toJson', () {
      final config = AdConfig.fromJson({
        'proxy_url': 'http://a:8081',
        'proxy_url_2': 'http://b:8081',
        'proxy_url_3': 'http://c:8081',
      });
      final back = AdConfig.fromJson(config.toJson());
      expect(back.proxyCandidates, config.proxyCandidates);
    });
  });
}
