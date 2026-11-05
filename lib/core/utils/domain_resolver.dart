import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

import '../models/ad_config.dart';
import '../params/ad_backend.dart';

/// Persists the backend mirror list and the last domain that answered.
///
/// `config.php` may be filtered (DNS poisoning / 403 / 5xx) while another
/// mirror still works, so every request walks an ordered candidate list:
///
///   last good domain → fresh backend list → cached list → bad domains.
///
/// A failing domain is bad-flagged for [AdBackend.badDomainTtl]; it stays at
/// the end of the list (still tried as a last resort) and recovers afterwards.
class DomainResolver {
  DomainResolver._();

  static final DomainResolver instance = DomainResolver._();

  static const String _keyDomains = 'cached_domains';
  static const String _keyLastGood = 'last_good_domain';

  final GetStorage _box = GetStorage();
  final Map<String, DateTime> _badUntil = <String, DateTime>{};

  List<String> get cached {
    try {
      return normalizeBaseUrls(_box.read(_keyDomains));
    } catch (_) {
      return const <String>[];
    }
  }

  String? get lastGood {
    try {
      return normalizeBaseUrl(_box.read(_keyLastGood));
    } catch (_) {
      return null;
    }
  }

  /// Saves the fresh mirror list together with the domain that served it.
  ///
  /// Older cached mirrors are kept as a fallback: if the backend ever returns
  /// an empty `domains` array, wiping the list would leave a filtered device
  /// with no alternative host on the next launch.
  void save(List<String> domains, String goodDomain) {
    final good = normalizeBaseUrl(goodDomain);
    final cachedList = cached;
    final merged = <String>[
      if (good != null) good,
      ...normalizeBaseUrls(domains),
      ...cachedList,
    ];
    final list = normalizeBaseUrls(merged, max: 12);
    try {
      _box.write(_keyDomains, list);
      if (good != null) _box.write(_keyLastGood, good);
      for (final domain in list) {
        _badUntil.remove(domain);
      }
      debugPrint('[Ads] backend domains saved: ${list.join(', ')}');
    } catch (error) {
      debugPrint('[Ads] saving backend domains failed: $error');
    }
  }

  /// Temporarily deprioritises [domain] after a timeout / DNS / HTTP failure.
  void markBad(String domain) {
    final normalized = normalizeBaseUrl(domain);
    if (normalized == null) return;
    _badUntil[normalized] = DateTime.now().add(AdBackend.badDomainTtl);
    debugPrint('[Ads] domain bad-flagged: $normalized');
  }

  Set<String> get _activeBadDomains {
    final now = DateTime.now();
    _badUntil.removeWhere((_, until) => !until.isAfter(now));
    return _badUntil.keys.toSet();
  }

  /// Candidate list for the next request.
  List<String> order(List<String> fresh) {
    return orderDomainCandidates(
      fresh: fresh,
      cached: cached,
      lastGood: lastGood,
      badDomains: _activeBadDomains,
    );
  }

  /// Restores state for unit tests and hot restarts.
  @visibleForTesting
  void resetForTests() {
    _badUntil.clear();
    try {
      _box.remove(_keyDomains);
      _box.remove(_keyLastGood);
    } catch (_) {
      // Storage may be unavailable in tests.
    }
  }
}

/// Pure ordering helper (exported for tests).
List<String> orderDomainCandidates({
  required List<String> fresh,
  required List<String> cached,
  String? lastGood,
  Set<String> badDomains = const <String>{},
}) {
  final freshList = normalizeBaseUrls(fresh, max: 20);
  final cachedList = normalizeBaseUrls(cached, max: 20);
  final bad = badDomains.map(normalizeBaseUrl).whereType<String>().toSet();
  final good = normalizeBaseUrl(lastGood);

  final result = <String>[];
  void add(String? value) {
    if (value == null) return;
    if (result
        .any((existing) => existing.toLowerCase() == value.toLowerCase())) {
      return;
    }
    result.add(value);
  }

  // 1) The last domain that actually answered (unless it just failed).
  if (good != null && !bad.contains(good)) add(good);

  // 2) Fresh list, healthy mirrors first.
  for (final domain in freshList) {
    if (!bad.contains(domain)) add(domain);
  }

  // 3) Domains learned during previous launches.
  for (final domain in cachedList) {
    if (!bad.contains(domain)) add(domain);
  }

  // 4) Bad-flagged mirrors are still tried last, so a false positive recovers.
  for (final domain in freshList) {
    if (bad.contains(domain)) add(domain);
  }
  for (final domain in cachedList) {
    if (bad.contains(domain)) add(domain);
  }

  // 5) First install with no cache/config at all.
  if (result.isEmpty) add(AdBackend.defaultBaseUrl);
  return List<String>.unmodifiable(result);
}
