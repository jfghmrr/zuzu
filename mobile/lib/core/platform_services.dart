import 'ru.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';

class PlatformServices {
  final notifications = FlutterLocalNotificationsPlugin();
  String zone = 'UTC';
  bool ready = false;
  bool? permitted;
  String? pushError;
  void Function(String)? onRoute;
  StreamSubscription<String>? tokenSub;
  StreamSubscription<RemoteMessage>? messageSub;
  Future<void> init() async {
    tzdata.initializeTimeZones();
    final info = await FlutterTimezone.getLocalTimezone();
    zone = info;
    tz.setLocalLocation(tz.getLocation(zone));
    if (kIsWeb) return;
    await notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) onRoute?.call(r.payload!);
      },
    );
    final launch = await notifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final payload = launch?.notificationResponse?.payload;
      if (payload != null) onRoute?.call(payload);
    }
    ready = true;
  }

  Future<bool> requestPermission() async {
    if (kIsWeb || !ready) {
      permitted = false;
      return false;
    }
    final ios = notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final android = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    permitted = ios != null
        ? await ios.requestPermissions(alert: true, badge: true, sound: true)
        : await android?.requestNotificationsPermission();
    return permitted ?? false;
  }

  int id(String uuid) {
    // stable FNV-1a, independent of Dart runtime hash randomisation
    var hash = 2166136261;
    for (final c in uuid.codeUnits) {
      hash = ((hash ^ c) * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> syncReminders(Api api) async {
    if (!ready) return;
    final settings = await api.call('GET', '/settings');
    if (settings['push'] == false) {
      await notifications.cancelAll();
      return;
    }
    final rows = <dynamic>[];
    Map<String, dynamic>? cursor;
    do {
      final query = cursor == null
          ? ''
          : '&before=${cursor['before']}&cursor_id=${cursor['cursor_id']}';
      final data = await api.call('GET', '/items/reminders?limit=50$query');
      rows.addAll(data['items']);
      cursor = data['next'] == null
          ? null
          : Map<String, dynamic>.from(data['next']);
    } while (cursor != null);
    await notifications.cancelAll();
    rows.sort((a, b) => a['data']['due_at'].compareTo(b['data']['due_at']));
    var count = 0;
    for (final r in rows) {
      final d = r['data'];
      final due = DateTime.parse(d['due_at']);
      if (d['done'] == true || !due.isAfter(DateTime.now())) continue;
      if (count++ >= 60) {
        break; // iOS pending limit; refill on foreground/resume.
      }
      await notifications.zonedSchedule(
        id(r['id']),
        d['title'],
        Ru.text75,
        tz.TZDateTime.from(due, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'care',
            Ru.text74,
            importance: Importance.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({'route': 'reminder', 'target': r['id']}),
      );
    }
  }

  Future<void> connectPush(Api api) async {
    if (kIsWeb || !const bool.fromEnvironment('ENABLE_PUSH')) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await api.call('PUT', '/devices', {'token': token});
      await tokenSub?.cancel();
      tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((v) async {
        if (api.token != null) {
          try {
            await api.call('PUT', '/devices', {'token': v});
          } catch (_) {
            pushError = Ru.text73;
          }
        }
      });
      await messageSub?.cancel();
      messageSub = FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => onRoute?.call(jsonEncode(m.data)),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) onRoute?.call(jsonEncode(initial.data));
    } catch (_) {
      pushError = Ru.text72;
    }
  }

  Future<void> clear() async {
    await tokenSub?.cancel();
    await messageSub?.cancel();
    if (ready) await notifications.cancelAll();
    if (!kIsWeb && Firebase.apps.isNotEmpty) {
      await FirebaseMessaging.instance.deleteToken();
    }
  }
}
