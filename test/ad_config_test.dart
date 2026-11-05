import 'package:flutter_test/flutter_test.dart';
import 'package:proxymodern/core/models/ad_config.dart';
import 'package:proxymodern/core/models/app_update.dart';
import 'package:proxymodern/core/utils/ad_cap_policy.dart';

const Map<String, dynamic> _setting = <String, dynamic>{
  'package_name': 'af.arianadeveloper.proxymodern',
  'app_name': 'پروکسی مدرن',
  'app_id': 'ca-app-pub-8261107325783752~3868070072',
  'ad_min_interval_seconds': 45,
  'ad_max_per_session': 3,
  'ad_retry_count': 2,
  'ads_status': 1,
  'country_code': 'ir',
  'language_code': 'FA',
  'language_tags': <String>['fa-IR', 'en-US'],
  'network_operator_code': '43211',
  'timezone_offset_minutes': 210,
  'version': '21',
  'update_title': 'نسخه جدید',
  'update_desc': 'برای ادامه به‌روزرسانی کنید',
  'update_url': 'https://example.com/app.apk',
  'should_update': 'true',
  'ad_units': <Map<String, dynamic>>[
    <String, dynamic>{
      // The panel key contains U+0640 ARABIC TATWEEL.
      'key': 'Interstitial\u0640splash',
      'value': 'ca-app-pub-7764262870428683/4194767781',
      'enabled': 1,
      'comment': 'اینترستیشیال اسپلش',
    },
    <String, dynamic>{
      'key': 'on_connect_Interstitial',
      'value': 'ca-app-pub-7764262870428683/4194767782',
      'enabled': 1,
      'comment': 'اینترستیشیال اتصال',
    },
    <String, dynamic>{
      'key': 'banner',
      'value': 'ca-app-pub-7764262870428683/4194767783',
      'enabled': 0,
      'comment': 'بنر',
    },
  ],
  'is_ir': 1,
  'visitor_country': 'IR',
  'relays': <Map<String, dynamic>>[
    <String, dynamic>{
      'name': 'relay-a',
      'url': 'http://1.2.3.4:8080',
      'proxy_username': 'user-a',
      'proxy_password': 'pass-a',
      'proxy_mode': 'sticky',
      'proxy_ttl_seconds': 3600,
    },
    <String, dynamic>{
      'name': 'relay-b',
      'url': 'https://5.6.7.8:443',
      'proxy_username': '',
      'proxy_password': '',
      'proxy_mode': 'rotation',
      'proxy_ttl_seconds': 0,
    },
  ],
  'domains': <String>[
    'apps.goshimi.ir',
    'https://mirror.example.com/',
    'apps.goshimi.ir',
  ],
};

void main() {
  group('AdConfig', () {
    final config = AdConfig.fromJson(_setting);

    test('maps every contract field', () {
      expect(config.packageName, 'af.arianadeveloper.proxymodern');
      expect(config.appId, 'ca-app-pub-8261107325783752~3868070072');
      expect(config.adsStatus, 1);
      expect(config.adsEnabled, isTrue);
      expect(config.isIr, 1);
      expect(config.isIranian, isTrue);
      expect(config.countryCode, 'ir');
      expect(config.languageTags, <String>['fa-IR', 'en-US']);
      expect(config.timezoneOffsetMinutes, 210);
      expect(config.adMinIntervalSeconds, 45);
      expect(config.adMaxPerSession, 3);
      expect(config.adRetryCount, 2);
      expect(config.maxLoadAttempts, 3);
      expect(config.version, '21');
      expect(config.shouldUpdate, isTrue);
      expect(config.updateRequired, isTrue);
    });

    test('resolves splash/connect units including tatweel keys', () {
      expect(
        config.unitIdFor(AdSlot.splash),
        'ca-app-pub-7764262870428683/4194767781',
      );
      expect(
        config.unitIdFor(AdSlot.connect),
        'ca-app-pub-7764262870428683/4194767782',
      );
      expect(
          normalizeAdUnitKey('Interstitial\u0640splash'), 'interstitialsplash');
      expect(normalizeAdUnitKey('on_connect_Interstitial'),
          'onconnectinterstitial');
    });

    test('a declared but disabled unit is never replaced', () {
      expect(config.unitIdFor(AdSlot.banner), isNull);
    });

    test('normalises and de-duplicates backend domains', () {
      expect(config.domains, <String>[
        'https://apps.goshimi.ir',
        'https://mirror.example.com',
      ]);
    });

    test('parses relays and sticky usernames', () {
      expect(config.relays, hasLength(2));
      final sticky = config.relays.first;
      expect(sticky.isValid, isTrue);
      expect(sticky.isSticky, isTrue);
      expect(sticky.hasCredentials, isTrue);
      expect(
        sticky.usernameWithSession('stk-123'),
        'user-a-sid-stk-123-ttl-3600',
      );
      expect(config.relays.last.isSticky, isFalse);
      expect(config.relays.last.usernameWithSession('ignored'), '');
    });

    test('toJson round-trips the payload', () {
      final again = AdConfig.fromJson(config.toJson());
      expect(again.packageName, config.packageName);
      expect(again.adUnits.length, config.adUnits.length);
      expect(again.unitIdFor(AdSlot.splash), config.unitIdFor(AdSlot.splash));
      expect(again.relays.length, config.relays.length);
      expect(again.domains, config.domains);
      expect(again.version, config.version);
    });

    test('legacy flat unit ids work when ad_units is absent', () {
      final legacy = AdConfig.fromJson(<String, dynamic>{
        'ads_status': 1,
        'interstitial_unit_id': 'ca-app-pub-7764262870428683/4194767781',
      });
      expect(
        legacy.unitIdFor(AdSlot.splash),
        'ca-app-pub-7764262870428683/4194767781',
      );
      expect(legacy.unitIdFor(AdSlot.connect), isNull);
    });

    test('ads_status 0 disables everything', () {
      final off = AdConfig.fromJson(<String, dynamic>{'ads_status': 0});
      expect(off.adsEnabled, isFalse);
    });

    test('accepts boolean flags returned by the live panel', () {
      final live = AdConfig.fromJson(<String, dynamic>{
        'ads_status': 1,
        'is_ir': true,
        'should_update': false,
        'network_operator_code': '310410',
        'timezone_offset_minutes': -300,
      });
      expect(live.isIranian, isTrue);
      expect(live.shouldUpdate, isFalse);
      expect(live.networkOperatorCode, '310410');
      expect(live.timezoneOffsetMinutes, -300);
    });

    test('falls back to comments and the documented two-unit order', () {
      const splashId = 'ca-app-pub-7764262870428683/4194767781';
      const connectId = 'ca-app-pub-7764262870428683/4194767782';

      final byComment = AdConfig.fromJson(<String, dynamic>{
        'ads_status': 1,
        'ad_units': <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'unknown_a',
            'value': splashId,
            'enabled': 1,
            'comment': 'اینترستیشیال اسپلش',
          },
          <String, dynamic>{
            'key': 'unknown_b',
            'value': connectId,
            'enabled': 1,
            'comment': 'اینترستیشیال اتصال',
          },
        ],
      });
      expect(byComment.unitIdFor(AdSlot.splash), splashId);
      expect(byComment.unitIdFor(AdSlot.connect), connectId);

      final byOrder = AdConfig.fromJson(<String, dynamic>{
        'ads_status': 1,
        'ad_units': <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'foo',
            'value': splashId,
            'enabled': 1,
            'comment': '',
          },
          <String, dynamic>{
            'key': 'bar',
            'value': connectId,
            'enabled': 1,
            'comment': '',
          },
        ],
      });
      expect(byOrder.unitIdFor(AdSlot.splash), splashId);
      expect(byOrder.unitIdFor(AdSlot.connect), connectId);

      final disabledFirst = AdConfig.fromJson(<String, dynamic>{
        'ads_status': 1,
        'ad_units': <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'foo',
            'value': splashId,
            'enabled': 0,
            'comment': '',
          },
          <String, dynamic>{
            'key': 'bar',
            'value': connectId,
            'enabled': 1,
            'comment': '',
          },
        ],
      });
      expect(disabledFirst.unitIdFor(AdSlot.splash), isNull);
      expect(disabledFirst.unitIdFor(AdSlot.connect), connectId);
    });

    test('non-Iranian visitors have empty relays and signals', () {
      final world = AdConfig.fromJson(<String, dynamic>{
        'ads_status': 1,
        'is_ir': 0,
        'relays': <Map<String, dynamic>>[],
        'country_code': '',
        'timezone_offset_minutes': null,
      });
      expect(world.isIranian, isFalse);
      expect(world.usableRelays, isEmpty);
      expect(world.timezoneOffsetMinutes, isNull);
    });
  });

  group('AdCapPolicy', () {
    final now = DateTime(2026, 11, 5, 12);

    test('zero limits mean unlimited', () {
      const policy = AdCapPolicy(
        minIntervalSeconds: 0,
        maxPerSession: 0,
        shownCount: 999,
        lastShownAt: null,
      );
      expect(policy.canRequest, isTrue);
      expect(policy.remainingSessionShows, -1);
      expect(policy.remainingInterval, Duration.zero);
    });

    test('session cap is enforced', () {
      final policy = AdCapPolicy(
        minIntervalSeconds: 0,
        maxPerSession: 2,
        shownCount: 2,
        now: now,
      );
      expect(policy.hasSessionCapacity, isFalse);
      expect(policy.canRequest, isFalse);
      expect(policy.remainingSessionShows, 0);
    });

    test('minimum interval is enforced and survives a clock skew', () {
      final blocked = AdCapPolicy(
        minIntervalSeconds: 60,
        maxPerSession: 0,
        shownCount: 0,
        lastShownAt: now.subtract(const Duration(seconds: 30)),
        now: now,
      );
      expect(blocked.isIntervalElapsed, isFalse);
      expect(blocked.canRequest, isFalse);
      expect(blocked.remainingInterval.inSeconds, 30);

      final allowed = AdCapPolicy(
        minIntervalSeconds: 60,
        maxPerSession: 0,
        shownCount: 0,
        lastShownAt: now.subtract(const Duration(seconds: 61)),
        now: now,
      );
      expect(allowed.isIntervalElapsed, isTrue);

      final skewed = AdCapPolicy(
        minIntervalSeconds: 60,
        maxPerSession: 0,
        shownCount: 0,
        lastShownAt: now.add(const Duration(minutes: 5)),
        now: now,
      );
      expect(skewed.isIntervalElapsed, isTrue);
    });
  });

  group('AppUpdatePolicy', () {
    test('newer build number creates a forced update', () {
      final info = AppUpdatePolicy.evaluate(
        config: AdConfig.fromJson(_setting),
        currentBuildNumber: '20',
        currentVersionName: '1.5.20-release',
      );
      expect(info, isNotNull);
      expect(info!.forced, isTrue);
      expect(info.latestVersion, '21');
      expect(info.title, 'نسخه جدید');
      expect(info.updateUrl, 'https://example.com/app.apk');
    });

    test('same build number means no update', () {
      final info = AppUpdatePolicy.evaluate(
        config: AdConfig.fromJson(_setting),
        currentBuildNumber: '21',
        currentVersionName: '1.5.21',
      );
      expect(info, isNull);
    });

    test('optional updates are not forced', () {
      final optional = AdConfig.fromJson(<String, dynamic>{
        ..._setting,
        'should_update': 'false',
      });
      final info = AppUpdatePolicy.evaluate(
        config: optional,
        currentBuildNumber: '20',
        currentVersionName: '1.5.20',
      );
      expect(info, isNotNull);
      expect(info!.forced, isFalse);
    });

    test('falls back to semantic version comparison', () {
      final info = AppUpdatePolicy.evaluate(
        config: AdConfig.fromJson(<String, dynamic>{
          'version': '1.5.21',
          'should_update': 'false',
        }),
        currentBuildNumber: '20',
        currentVersionName: '1.5.20',
      );
      expect(info, isNotNull);
      expect(info!.forced, isFalse);
    });
  });
}
