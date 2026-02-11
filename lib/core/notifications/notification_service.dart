import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // ★このインポートが必須です
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      settings: settings,
    );
  }

  Future<void> requestPermissions() async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  void updateBadgeCount(int count) async {
    final isSupported = await AppBadgePlus.isSupported();
    if (!isSupported) return;

    if (count > 0) {
      AppBadgePlus.updateBadge(count);
    } else {
      AppBadgePlus.updateBadge(0);
    }
  }

  int _hashId(String docId) {
    return docId.hashCode;
  }

  Future<void> scheduleExpiryNotification({
    required String docId,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (scheduledDate.isBefore(DateTime.now())) return;

    final tz.TZDateTime tzScheduledDate = tz.TZDateTime.from(
      scheduledDate,
      tz.local,
    );

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'expiry_channel',
      '賞味期限通知',
      channelDescription: '賞味期限切れをお知らせします',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    // バージョンアップにより、引数はすべて名前付き(id: ... 等)にする必要があります
    await _notificationsPlugin.zonedSchedule(
      id: _hashId(docId),
      title: title,
      body: body,
      scheduledDate: tzScheduledDate,
      notificationDetails: platformDetails,
      // もしここでエラーが出る場合、パッケージのバージョンが古い可能性があります
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelNotification(String docId) async {
    await _notificationsPlugin.cancel(id: _hashId(docId));
  }

  Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }
}