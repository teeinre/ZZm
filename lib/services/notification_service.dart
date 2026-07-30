import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../constants/api_constants.dart';
import '../services/api_service.dart';

/// Handles all push notification logic:
/// - FCM token management (registration, refresh, unregistration)
/// - Foreground notification display via flutter_local_notifications
/// - Background/terminated notification routing
/// - Server-side device token sync
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Callbacks
  void Function(String type, Map<String, String> data)? onNotificationOpened;

  // ─── Initialization ───────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Request notification permission (iOS + Android 13+)
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[Notify] Permission status: ${settings.authorizationStatus}');

    // Get FCM token
    final token = await _fcm.getToken();
    debugPrint('[Notify] FCM Token: $token');

    // Listen for token refresh
    _fcm.onTokenRefresh.listen((newToken) {
      debugPrint('[Notify] Token refreshed: $newToken');
      _registerDeviceToken(newToken);
    });

    // Initialize local notifications for foreground display
    await _initLocalNotifications();

    // Handle notification when app is opened from terminated state
    final initialMsg = await _fcm.getInitialMessage();
    if (initialMsg != null) {
      _handleNotificationTap(initialMsg.data);
    }

    // Handle notification taps while app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Handle foreground messages (display as local notification)
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages (data-only, no UI)
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Register device token
    if (token != null) {
      await _registerDeviceToken(token);
    }
  }

  // ─── Local Notifications Init ─────────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // Already requested via FCM
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _local.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) {
          try {
            _handleNotificationTap(Map<String, String>.from(jsonDecode(payload)));
          } catch (_) {}
        }
      },
    );

    // Create Android notification channel
    const androidChannel = AndroidNotificationChannel(
      'zzmore_notifications',  // Must match android_channel_id in FCM payload
      'ZZmore Store',
      description: 'Order updates, livestream alerts, and promotions',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  // ─── Show foreground notification ─────────────────────────────────────────

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[Notify] Foreground: ${message.notification?.title}');
    final notification = message.notification;
    if (notification == null) return;

    _local.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'zzmore_notifications',
          'ZZmore Store',
          channelDescription: 'Order updates, livestream alerts, and promotions',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFFE67E14),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('[Notify] Opened from notification: ${message.data}');
    _handleNotificationTap(message.data);
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final typedData = data.map((k, v) => MapEntry(k, v.toString()));
    final type = typedData['type'] ?? '';
    onNotificationOpened?.call(type, typedData);
  }

  // ─── Background handler (top-level, must be static) ───────────────────────

  @pragma('vm:entry-point')
  static Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
    debugPrint('[Notify] Background message received');
    // Background messages are displayed by the system automatically
    // when they include a notification payload. Data-only messages
    // would need flutter_local_notifications here, but Flutter
    // background isolates limit plugin usage.
  }

  // ─── Device Token Management ──────────────────────────────────────────────

  Future<void> _registerDeviceToken(String token) async {
    try {
      final api = ApiService();
      await api.post(
        ApiConstants.registerDeviceEndpoint,
        {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
        useWcAuth: false,
      );
      debugPrint('[Notify] Device token registered with server');
    } catch (e) {
      debugPrint('[Notify] Failed to register device token: $e');
    }
  }

  Future<void> unregisterDeviceToken() async {
    try {
      final token = await _fcm.getToken();
      if (token == null) return;
      final api = ApiService();
      await api.post(
        ApiConstants.unregisterDeviceEndpoint,
        {'token': token},
        useWcAuth: false,
      );
      debugPrint('[Notify] Device token unregistered');
    } catch (e) {
      debugPrint('[Notify] Failed to unregister device token: $e');
    }
  }

  // ─── Public helpers ───────────────────────────────────────────────────────

  /// Get the current FCM registration token.
  Future<String?> getToken() => _fcm.getToken();

  /// Delete the current FCM token (generates a new one on next getToken).
  Future<void> deleteToken() => _fcm.deleteToken();

  /// Subscribe to a topic (e.g., "promotions", "new_arrivals").
  Future<void> subscribeToTopic(String topic) => _fcm.subscribeToTopic(topic);

  /// Unsubscribe from a topic.
  Future<void> unsubscribeFromTopic(String topic) => _fcm.unsubscribeFromTopic(topic);
}
