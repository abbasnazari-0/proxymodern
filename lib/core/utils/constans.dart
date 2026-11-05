const int versionApplication = 2;

const String package_name = "";

const String storageKeyLegacyListMode = "legacy_list_mode";

/// GetStorage key holding the last decoded `config.php` payload.
const String storageKeyAdConfig = "ad_config";

/// GetStorage key holding the timestamp (ms) of the last successful ad show.
///
/// The session counter resets on every launch, but the minimum interval between
/// two impressions must survive a restart, so the timestamp is persisted.
const String storageKeyAdLastShownAt = "ad_last_shown_at_ms";

/// FCM topic that every install must be listening to.
///
/// The panel publishes general announcements here. Topic subscriptions live on
/// FCM's servers, so they survive restarts but not a new token/re-install —
/// `NotificationService` subscribes on every launch and on resume.
const String firebaseTopicAll = "all";
