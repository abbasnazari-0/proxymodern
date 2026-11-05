import 'package:flutter_test/flutter_test.dart';
import 'package:proxymodern/core/models/ad_config.dart';
import 'package:proxymodern/core/params/ad_backend.dart';
import 'package:proxymodern/core/utils/ad_report_service.dart';
import 'package:proxymodern/core/utils/domain_resolver.dart';
import 'package:proxymodern/core/utils/relay_selector.dart';

void main() {
  group('domain ordering', () {
    test('last good → fresh → cached → bad-flagged', () {
      final ordered = orderDomainCandidates(
        fresh: const <String>[
          'apps.goshimi.ir',
          'https://mirror.example.com/',
          'https://bad.example.com',
        ],
        cached: const <String>[
          'https://old.example.com',
          'https://apps.goshimi.ir',
        ],
        lastGood: 'mirror.example.com',
        badDomains: const <String>{'https://bad.example.com'},
      );

      expect(ordered, <String>[
        'https://mirror.example.com',
        'https://apps.goshimi.ir',
        'https://old.example.com',
        'https://bad.example.com',
      ]);
    });

    test('a bad-flagged last-good domain goes to the end', () {
      final ordered = orderDomainCandidates(
        fresh: const <String>['https://a.example.com', 'https://b.example.com'],
        cached: const <String>['https://c.example.com'],
        lastGood: 'https://a.example.com',
        badDomains: const <String>{'https://a.example.com'},
      );
      expect(ordered, <String>[
        'https://b.example.com',
        'https://c.example.com',
        'https://a.example.com',
      ]);
    });

    test('empty input falls back to the primary domain', () {
      expect(
        orderDomainCandidates(
          fresh: const <String>[],
          cached: const <String>[],
          lastGood: null,
        ),
        <String>['https://apps.goshimi.ir'],
      );
    });

    test('invalid and duplicated domains are removed', () {
      final ordered = orderDomainCandidates(
        fresh: const <String>[
          'not a host',
          'https://APP.EXAMPLE.com',
          'https://app.example.com/',
          'ftp://files.example.com',
        ],
        cached: const <String>[],
        lastGood: null,
      );
      expect(ordered, <String>['https://app.example.com']);
    });
  });

  group('relay selection', () {
    test('picks the lowest non-null latency', () {
      expect(
        pickFastestRelayUrl(const <(String, int?)>[
          ('relay-a', 120),
          ('relay-b', 45),
          ('relay-c', null),
        ]),
        'relay-b',
      );
    });

    test('returns null when no relay answered', () {
      expect(
        pickFastestRelayUrl(const <(String, int?)>[
          ('relay-a', null),
          ('relay-b', null),
        ]),
        isNull,
      );
    });

    test('validates proxy URLs and builds sticky usernames', () {
      const valid = RelayConfig(
        name: 'a',
        url: 'http://1.2.3.4:8080',
        proxyUsername: 'user',
        proxyPassword: 'pass',
        proxyMode: 'sticky',
        proxyTtlSeconds: 1200,
      );
      expect(valid.isValid, isTrue);
      expect(valid.usernameWithSession('stk1'), 'user-sid-stk1-ttl-1200');
      expect(valid.usernameWithSession(''), 'user');

      const noPort = RelayConfig(name: 'b', url: 'http://1.2.3.4');
      expect(noPort.isValid, isTrue);
      expect(noPort.proxyUrl, 'http://1.2.3.4:80');

      const credentialsInUrl = RelayConfig(
        name: 'c',
        url: 'http://user:pass@1.2.3.4:8080',
      );
      expect(credentialsInUrl.isValid, isFalse);

      const withPath = RelayConfig(
        name: 'd',
        url: 'https://relay.example.com:443/path',
      );
      expect(withPath.isValid, isTrue);
      expect(withPath.proxyUrl, 'https://relay.example.com:443');

      const halfCredentials = RelayConfig(
        name: 'e',
        url: 'https://relay.example.com:443',
        proxyUsername: 'user',
      );
      expect(halfCredentials.isValid, isFalse);
    });
  });

  group('ad reporting', () {
    tearDown(AdReportService.instance.resetForTests);

    test('classifies SDK errors into short codes', () {
      expect(AdReportService.classifyError('No fill (NO_FILL)'), 'NO_FILL');
      expect(
        AdReportService.classifyError('Invalid request INVALID_REQUEST'),
        'INVALID_REQUEST',
      );
      expect(
        AdReportService.classifyError('Internal error, please retry'),
        'Internal error',
      );
      expect(
        AdReportService.classifyError('Account not approved'),
        'Account not approved',
      );
      expect(
        AdReportService.classifyError('Request timeout'),
        'timeout',
      );
      expect(
        AdReportService.classifyError('x' * 80).length,
        48,
      );
    });

    test('report signature matches an independent vector', () {
      final signature = AdReportService.calculateReportSignature(
        apiKey: AdBackend.apiKey,
        packageName: 'af.arianadeveloper.proxymodern',
        ts: '1700000000',
        nonce: 'nonce123',
        body: '{"events":[]}',
      );
      expect(
        signature,
        'e31435f6b2ffbfdcd7fe99bccd9265264f2b12adfcbc2fb39662064b88e9da77',
      );
    });

    test('is a no-op without api_key and queues after configure', () {
      final service = AdReportService.instance;
      service.resetForTests();
      service.addEvent(event: 'load_fail', unitKey: 'splash');
      expect(service.pendingCount, 0);

      service.configure(apiKey: AdBackend.apiKey);
      service.addEvent(event: 'load_fail', unitKey: 'splash');
      expect(service.pendingCount, 1);
      expect(service.isConfigured, isTrue);
    });
  });
}
