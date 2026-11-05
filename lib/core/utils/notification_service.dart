import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'data_extractor.dart';
import 'firebase_service.dart';

/// 🔔 نمایش محلی پیام FCM از داخل isolate پس‌زمینه.
///
/// این تابع باید top-level باشد تا موتور Flutter بتواند آن را در isolate
/// جداگانه اجرا کند. پیام‌های data (بدون بخش notification) به‌صورت خودکار
/// توسط سیستم نمایش داده نمی‌شوند؛ اینجا همان نمایش انجام می‌شود.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // در isolate پس‌زمینه باید Firebase دوباره initialize شود.
  await Firebase.initializeApp();

  final notification = message.notification;
  final title = notification?.title ?? (message.data['title'] as String?);
  final body = notification?.body ?? (message.data['body'] as String?);
  if (title == null && body == null) return;

  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    await plugin.show(
      id: message.hashCode & 0x7fffffff,
      title: title ?? 'سوپر پروکسی',
      body: body ?? '',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.channelId,
          NotificationService.channelName,
          channelDescription: NotificationService.channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
        ),
      ),
      payload: _encodePayload(message.data),
    );
    debugPrint('✅ FCM background notification shown: $title');
  } catch (error) {
    debugPrint('❌ FCM background notification failed: $error');
  }
}

/// سریالیزه‌کردن data پیام برای دیپ‌لینک.
String? _encodePayload(Map<String, dynamic> data) {
  if (data.isEmpty) return null;
  try {
    return json.encode(data);
  } catch (_) {
    return null;
  }
}

/// 🔔 سرویس نوتیفیکیشن (Firebase Cloud Messaging + نمایش محلی).
///
/// وظایف:
/// - دریافت مجوز نوتیفیکیشن (Android 13+ و iOS)؛
/// - دریافت/تازه‌سازی توکن FCM و تحویل آن به بک‌اند از طریق [onTokenChanged]؛
/// - نمایش نوتیفیکیشن وقتی اپ در Foreground است؛
/// - نمایش پیام‌های data در پس‌زمینه (background handler)؛
/// - دیپ‌لینک به URL داخل payload هنگام لمس نوتیفیکیشن.
///
/// قرارداد payload:
/// ```json
/// {
///   "url": "https://t.me/...",   // اختیاری: لینک بازشونده هنگام لمس
///   "title": "عنوان",             // برای پیام‌های data
///   "body": "متن اعلان"           // برای پیام‌های data
/// }
/// ```
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String channelId = 'general_notifications';
  static const String channelName = 'اعلان‌ها';
  static const String channelDescription = 'اعلان‌های عمومی سوپر پروکسی';

  /// 🏷️ تاپیک عمومی که همهٔ دستگاه‌ها باید همیشه عضو آن باشند تا هر
  /// اعلان گروهی (مثلاً ارسال از کنسول Firebase) فوراً دریافت شود.
  static const String allTopic = 'all';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialized = false;

  String? _token;
  RemoteMessage? _initialMessage;

  /// پلاگین تحویل توکن؛ با توکن جدید (اولیه یا تازه‌شده) صدا زده می‌شود.
  /// در main.dart به ثبت‌نام در بک‌اند وصل می‌شود.
  Future<void> Function(String token)? onTokenChanged;

  String? get token => _token;

  /// راه‌اندازی کامل سرویس. باید بعد از runApp (با navigatorKey واقعی اپ)
  /// صدا زده شود تا دیپ‌لینک نوتیفیکیشن کار کند.
  Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    try {
      await _initLocalNotifications();
    } catch (error) {
      debugPrint('Local notifications init failed: $error');
    }

    unawaited(_setupMessaging());
  }

  /// ⚙️ کانال و پلاگین نمایش محلی (برای حالت Foreground).
  Future<void> _initLocalNotifications() async {
    final android = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
      ),
    );

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: _handleLocalNotificationTap,
    );
  }

  /// 🪙 دریافت مجوز، توکن و اتصال به رویدادهای FCM.
  Future<void> _setupMessaging() async {
    try {
      // 🔐 مجوز نوتیفیکیشن (Android 13+ دیالوگ سیستم را نشان می‌دهد).
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('⚠️ FCM permission status: ${settings.authorizationStatus}');
      } else {
        debugPrint('✅ FCM permission granted: ${settings.authorizationStatus}');
      }

      // اندروید 13+: درخواست مستقیم مجوز نمایش اعلان.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }

      // 🪙 ثبت‌نام FCM: توکن از طریق onRegistered تحویل می‌شود.
      await _registerForToken();

      // 🏷️ عضویت دائمی در تاپیک عمومی «all» تا اعلان‌های گروهی همیشه برسند.
      final subscribed = await subscribeToTopic(allTopic);
      if (subscribed) {
        debugPrint(
            '✅ FCM messaging setup complete. Topic "$allTopic" subscribed.');
      } else {
        debugPrint(
          '⚠️ FCM topic "$allTopic" NOT subscribed — messages will not arrive '
          'until FCM registration succeeds on this network.',
        );
      }

      // 🔁 تازه‌شدن توکن (register مجدد هم از همین استریم می‌آید)
      _messaging.onRegistered.listen((newToken) async {
        _token = newToken;
        await onTokenChanged?.call(newToken);
      });

      // 🟢 پیام در حالت Foreground → نمایش محلی
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 🟡 لمس نوتیفیکیشن وقتی اپ در پس‌زمینه است → دیپ‌لینک
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpen);

      // ⚪ اپ از روی نوتیفیکیشن باز شده (cold start) → در صفحهٔ اصلی پردازش می‌شود
      _initialMessage = await _messaging.getInitialMessage();

      // ⚫ هندلر پیام در پس‌زمینه / اپ بسته
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (error) {
      debugPrint('FCM setup failed: $error');
    }
  }

  /// ثبت‌نام در FCM. توکن جدید از طریق onRegistered دریافت و به بک‌اند
  /// ارسال می‌شود؛ هر فراخوانی [register] در صورت تغییر توکن، آن را
  /// دوباره از همان استریم اعلام می‌کند.
  Future<void> _registerForToken() async {
    try {
      await _messaging.register();
    } catch (error) {
      debugPrint('FCM register failed: $error');
    }
  }

  /// 🟢 پیام در Foreground: نوتیفیکیشن محلی با همان محتوا.
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
      '📩 FCM foreground message: id=${message.messageId} '
      'topic=${message.from} data=${message.data} '
      'notification=${message.notification?.title}/${message.notification?.body}',
    );
    final notification = message.notification;
    final title = notification?.title ?? (message.data['title'] as String?);
    final body = notification?.body ?? (message.data['body'] as String?);
    if (title == null && body == null) return;

    unawaited(_showLocalNotification(
      id: message.hashCode & 0x7fffffff,
      title: title ?? 'سوپر پروکسی',
      body: body ?? '',
      payload: _encodePayload(message.data),
    ));
  }

  /// 🟡 لمس نوتیفیکیشن FCM (اپ در پس‌زمینه).
  void _handleMessageOpen(RemoteMessage message) {
    unawaited(_navigateFromPayload(message.data));
  }

  /// لمس نوتیفیکیشن محلی (نمایش Foreground).
  void _handleLocalNotificationTap(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;

    Map<String, dynamic> data = {};
    try {
      data = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {}
    unawaited(_navigateFromPayload(data));
  }

  /// ⚪ پردازش پیام اولیه (cold start). باید بعد از نمایش صفحهٔ اصلی
  /// صدا زده شود تا push روی ناوبری آماده انجام شود.
  Future<void> handleInitialMessage() async {
    final message = _initialMessage;
    if (message == null) return;
    _initialMessage = null;
    await _navigateFromPayload(message.data);
  }

  /// 🧭 دیپ‌لینک: اگر url در payload باشد، اپ به صفحهٔ اصلی برمی‌گردد و
  /// همان لینک باز می‌شود.
  Future<void> _navigateFromPayload(Map<String, dynamic> data) async {
    final url = data['url']?.toString() ?? data['link']?.toString() ?? '';
    if (url.isEmpty) return;

    final navigator = _navigatorKey?.currentState;
    if (navigator != null) {
      navigator.popUntil((route) => route.isFirst);
    }

    unawaited(
      FirebaseService.instance.logEvent(
        'notification_opened',
        <String, Object>{'has_url': url.isNotEmpty},
      ),
    );

    try {
      await DataExtractor.launchUrl(url);
    } catch (error) {
      debugPrint('Deep link navigation failed: $error');
    }
  }

  /// نمایش محلی (استفادهٔ عمومی؛ مثلاً اعلان داخل اپ).
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) {
    return _showLocalNotification(
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
  }

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      await _localNotifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
            color: Color(0xFF3DDC97),
          ),
        ),
        payload: payload,
      );
    } catch (error) {
      debugPrint('Local notification show failed: $error');
    }
  }

  /// عضویت در تاپیک (برای ارسال گروهی از کنسول Firebase).
  Future<bool> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('✅ FCM subscribed to topic: "$topic"');
      return true;
    } catch (error) {
      debugPrint('❌ FCM subscribeToTopic("$topic") failed: $error');
      return false;
    }
  }

  /// تضمین عضویت در تاپیک عمومی «all» (مثلاً هنگام برگشت اپ از پس‌زمینه).
  /// FCM گاهی عضویت در تاپیک را از دست می‌دهد؛ این متد آن را دوباره برقرار
  /// می‌کند تا اعلان‌ها هیچ‌وقت قطع نشوند.
  Future<bool> ensureAllTopicSubscription() => subscribeToTopic(allTopic);

  /// لغو عضویت از تاپیک.
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
    } catch (error) {
      debugPrint('FCM unsubscribeFromTopic($topic) failed: $error');
    }
  }
}
