# Firebase (Analytics + Cloud Messaging + Performance)

Everything below is already wired in the repo. The app targets the Firebase
project **`space-sum`** (project number `104331095974`).

| Item                | Value                                                    |
| ------------------- | -------------------------------------------------------- |
| Android package     | `af.arianadeveloper.proxymodern`                         |
| Second Android app  | `com.arianadeveloper.spacesum` (same project, if needed) |
| Native config       | `android/app/google-services.json`                       |
| iOS config          | `ios/Runner/GoogleService-Info.plist` (see iOS section)   |
| Notification channel| `general_notifications` (high importance)            |
| General topic       | `all`                                                    |

## Where the code lives

| File | Responsibility |
| ---- | -------------- |
| `lib/core/utils/firebase_service.dart` | `Firebase.initializeApp`, Analytics helpers, custom traces, `HttpMetric` helpers. Every call is best-effort and never throws. |
| `lib/core/utils/notification_service.dart` | FCM permission, `all` topic subscription, token delivery, foreground/background display, tap deep-linking. |
| `lib/core/utils/firebase_performance_interceptor.dart` | Dio interceptor that reports request latency/status to Performance Monitoring. |
| `lib/main.dart` | Firebase boot before `runApp`; `MainWrapper` starts the notification service. |

## Boot order (important)

1. `FirebaseService.initialize()` runs **before** `runApp` (Firebase Core +
   Analytics + Performance), guarded by try/catch — a missing Google Play
   services never blocks the app.
2. `runApp(...)`.
3. From `MainWrapper.initState`, `NotificationService.init(navigatorKey: ...)`
   initializes local notifications and FCM: permission prompt, `register()`,
   subscribe to the `all` topic, message listeners and the background handler.
4. The FCM token is delivered to the backend via
   `onTokenChanged` → `POST /register-device-token`.
5. On every app resume, `ensureAllTopicSubscription()` re-subscribes to `all`.

## The `all` topic is always re-subscribed

FCM stores topic subscriptions on its own servers, so they survive restarts.
They are **lost** when the token/installation changes (re-install, "clear
data", restore on a new device), so `NotificationService` subscribes to `all`:

- after FCM registration on every launch (`_setupMessaging`),
- on every app resume (`ensureAllTopicSubscription` from `MainWrapper`).

No screen needs to do anything; this happens for every install automatically.

### ⚠️ FCM needs reachable Google servers

Topic messages are delivered by Google Play Services, so the device must be able
to open a TLS connection to `fcmregistrations.googleapis.com` (and the MCS
endpoints on port 5228). On networks where Google is filtered — the normal case
for this app's Iranian users before they connect a proxy — registration fails
with:

```
java.io.IOException: FCM Registration failed!
```

and logcat shows the real cause:

```
E/chromium: handshake failed ... net_error -100   (ERR_CONNECTION_CLOSED)
W/AsyncOperation: OperationException[Status{statusCode=UNAVAILABLE}]
```

In that state the device is **not** in the topic, so campaigns do not arrive.
This is a network limitation, not an app bug: the service retries forever (see
above) and subscribes as soon as the device can reach FCM (for example right
after the user turns on a VPN/tunnel that also routes Google Play Services).
Confirm it with:

```bash
adb logcat | grep "\[Push\]"
# expected once the network allows it:
# [Push] subscribed to "all" (startup)
```

In debug builds the FCM token is also printed (`[Push] FCM token: ...`); paste
it in the Firebase console's *Send test message* dialog for a per-device test.

## Sending a test notification

Firebase console → **Messaging** → *Create campaign* → *Notifications* →
target **Topic** → `all`.

- Background/terminated: the system tray renders the message with
  `@drawable/ic_notification` and the accent color `#3DDC97`.
- Foreground (Android): the app re-posts it as a local notification on the
  `general_notifications` channel.
- Tapping it opens the app; if `data.url` or `data.link` is present the app
  opens that link (e.g. an update page or a `tg://` proxy link).

Supported data payload keys:

```json
{
  "notification": { "title": "...", "body": "..." },
  "data": { "url": "https://example.com/app.apk" }
}
```

`title`/`body` may also be sent inside `data` only; the foreground handler
falls back to them.

`POST_NOTIFICATIONS` is declared in the manifest and requested at runtime on
Android 13+. If the user denies it, pushes are still received but not shown
until the permission is granted in system settings.

## Analytics

Collection is enabled explicitly at boot (`setAnalyticsCollectionEnabled(true)`).
`app_open` is logged from `main.dart`; screens are named manually because GetX
routes are anonymous closures (a `FirebaseAnalyticsObserver` would see no
names).

| Event | Parameters | Where |
| ----- | ---------- | ----- |
| `app_open` | – | `main.dart` |
| `screen_view` (`splash`, `channels`) | `screen_name` | splash / channel screens |
| `splash_boot_failed` | `error` | splash |
| `notification_opened` | `has_url` | notification deep-link |
| `proxy_opened` | `source` (`found_sheet`, `info_sheet`) | proxy sheets |

Add more events with `FirebaseService.instance.logEvent(name, params)`; it is
safe to call before Firebase is ready (it becomes a no-op). Parameter names must
be snake_case, values `String`/`num`, max 25 parameters per event.

## Performance Monitoring

- Automatic traces (app start, screen rendering) are collected by the SDK.
- Custom trace `splash_boot`: duration of config fetch + ads init during the
  splash, with the `ads_enabled` attribute.
- Every `Dio` request made by `ChannelController`, `AdReportService` and
  `ProxyReportService` produces an `HttpMetric` (latency, status code, payload
  size). Query strings are stripped before reporting, so signatures/nonces never
  reach Firebase.
- The optional `com.google.firebase.firebase-perf` Gradle plugin is **not**
  applied on purpose: it instruments Java/Kotlin code and OkHttp, while every
  request in this app goes through `Dio` and is already covered manually.
- Data appears in the console within ~12 hours (Performance Monitoring is not
  real-time). Use **DebugView** for Analytics if you need instant feedback.

## iOS — remaining manual steps

The repository currently contains **no iOS app for `space-sum`**: the existing
`ios/Runner/GoogleService-Info.plist` belongs to `bio-shick-feacd` (a different
Firebase project). Until it is replaced, iOS will not deliver pushes and its
Analytics will go to the old project.

1. Firebase console → project `space-sum` → *Add app* → iOS with bundle id
   `af.arianadeveloper.proxymodern.proxymodern` (keep it in sync with Xcode).
2. Download `GoogleService-Info.plist` and replace
   `ios/Runner/GoogleService-Info.plist` (add it to the Runner target).
3. Xcode → Runner → *Signing & Capabilities*:
   - add **Push Notifications**,
   - add **Background Modes → Remote notifications** (the `UIBackgroundModes`
     key is already in `Info.plist`).
4. Firebase console → *Project settings* → *Cloud Messaging* → upload an APNs
   authentication key (`.p8`) from the Apple Developer portal.
5. `flutter build ios` and test on a real device (the simulator cannot receive
   remote pushes).

## Troubleshooting

```bash
# watch the Dart side
adb logcat | grep -E "\[Push\]|\[Firebase\]|\[Perf\]"
```

| Symptom | Check |
| ------- | ----- |
| Build fails with `File google-services.json is missing` | the file must be at `android/app/google-services.json` (not `android/`) |
| `Default FirebaseApp is not initialized` | `com.google.gms.google-services` plugin missing in `android/app/build.gradle.kts` |
| Push received in background but not foreground | notification permission denied, or channel `general_notifications` blocked in system settings |
| No push at all | app must appear under the topic after a successful `subscribeToTopic('all')`; check logcat for `subscribed to topic` and make sure the campaign targets topic `all` |
| `IOException: FCM Registration failed!` / `SERVICE_NOT_AVAILABLE` | the device cannot reach `fcmregistrations.googleapis.com` / MCS (typical without a working proxy in IR, or with a VPN that drops port 5228); subscription re-runs on the next launch/resume once the network allows it |
| Topic subscription keeps failing | device cannot reach FCM; subscription re-runs on the next launch/resume |
| Performance data missing | it can take up to 12 h; confirm the app is a release/profile build (debug data is still uploaded, but sampling differs) |

## Dependency notes

```yaml
firebase_core: ^5.1.0
firebase_analytics: ^13.0.1
firebase_messaging: ^17.0.1
firebase_performance: ^0.12.1
flutter_local_notifications: ^18.0.1
```

`flutter_local_notifications` requires core-library desugaring; it is enabled in
`android/app/build.gradle.kts` with `desugar_jdk_libs:2.1.5`. Keep that version
at 2.1.4+ (the plugin's minimum) when upgrading AGP.

