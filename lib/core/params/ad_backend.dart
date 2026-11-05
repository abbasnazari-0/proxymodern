/// Contract constants for the `af.arianadeveloper.proxymodern` workspace of
/// the Goshimi backend (`config.php` / `session.php` / `report.php`).
///
/// The HMAC key is shared with the panel and is the same value the server uses
/// to derive the AES-256-GCM key (`SHA-256(apiKey)`). It is a public client
/// secret by design: it only authenticates this app's requests.
abstract final class AdBackend {
  /// Signing key + AES-256-GCM master key (the AES key is SHA-256 of this).
  static const String apiKey =
      '72683d04a23735c605abc5470214d905b127392c623437a42847b4276c5b1cf2';

  /// Workspace key used by the backend to look up this app's settings.
  static const String packageName = 'af.arianadeveloper.proxymodern';

  /// AdMob application id (`ca-app-pub-...~...`).
  static const String adMobAppId = 'ca-app-pub-8261107325783752~3868070072';

  /// Primary backend origin. Alternatives arrive in `setting.domains`.
  static const String defaultBaseUrl = 'https://apps.goshimi.ir';

  static const String configPath = '/config.php';
  static const String sessionPath = '/session.php';
  static const String reportPath = '/report.php';

  static const String platform = 'android';

  /// Upper bound for one backend HTTP attempt so domain rotation stays fast.
  static const Duration requestTimeout = Duration(seconds: 10);

  /// When every mirror fails, retry this long after the first failure.
  static const Duration domainRetryDelay = Duration(seconds: 60);

  /// A domain that failed is deprioritised for this long (bad-flag).
  static const Duration badDomainTtl = Duration(minutes: 2);
}
