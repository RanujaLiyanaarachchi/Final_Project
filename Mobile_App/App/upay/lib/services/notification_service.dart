import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:upay/main.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone database
    tz.initializeTimeZones();

    // Create notification channel for Android
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'Important notifications that require attention',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    // Initialize notification settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Initialize with onDidReceiveNotificationResponse callback
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationTap(response.payload);
      },
    );

    _initialized = true;
    debugPrint('✅ NotificationService initialized');
  }

  // Handle notification taps
  static void _handleNotificationTap(String? payload) {
    if (payload == null) return;

    try {
      // Get the navigatorKey from main.dart
      final navigatorKey = GlobalNavigatorKey.navigatorKey;
      if (navigatorKey.currentContext == null) return;

      // Navigate to notifications screen
      Navigator.of(
        navigatorKey.currentContext!,
      ).pushNamed('/notifications', arguments: {'payload': payload});
    } catch (e) {
      debugPrint('❌ Error handling notification tap: $e');
    }
  }

  // Show a local notification
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int id = 0,
    String? imageUrl,
  }) async {
    try {
      if (!_initialized) await initialize();

      // Create notification details
      NotificationDetails platformDetails;

      if (imageUrl != null && imageUrl.isNotEmpty) {
        // With image (Android only)
        if (Platform.isAndroid) {
          final bigPictureStyleInformation = BigPictureStyleInformation(
            ByteArrayAndroidBitmap.fromBase64String(
              await _getBase64Image(imageUrl),
            ),
            hideExpandedLargeIcon: true,
            contentTitle: title,
            summaryText: body,
          );

          final androidDetails = AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            channelDescription:
                'Important notifications that require attention',
            importance: Importance.max,
            priority: Priority.high,
            styleInformation: bigPictureStyleInformation,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.message,
            largeIcon: DrawableResourceAndroidBitmap('@drawable/ic_launcher'),
          );

          platformDetails = NotificationDetails(android: androidDetails);
        } else {
          // Standard details for iOS
          platformDetails = const NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          );
        }
      } else {
        // Standard notification
        platformDetails = const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            channelDescription:
                'Important notifications that require attention',
            importance: Importance.max,
            priority: Priority.high,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.message,
            largeIcon: DrawableResourceAndroidBitmap('@drawable/ic_launcher'),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );
      }

      // Show notification
      await _notifications.show(
        id,
        title,
        body,
        platformDetails,
        payload: payload,
      );

      debugPrint('✅ Showed local notification: $title');
    } catch (e) {
      debugPrint('❌ Error showing local notification: $e');
    }
  }

  // Helper function to get base64 image for notifications with images
  static Future<String> _getBase64Image(String imageUrl) async {
    try {
      // Implementation would go here - this is a placeholder
      // You would download the image and convert to base64
      return '';
    } catch (e) {
      debugPrint('❌ Error getting base64 image: $e');
      return '';
    }
  }

  // Schedule a notification in the future
  static Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    int id = 0,
  }) async {
    try {
      if (!_initialized) await initialize();

      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            channelDescription:
                'Important notifications that require attention',
            importance: Importance.max,
            priority: Priority.high,
            largeIcon: DrawableResourceAndroidBitmap('@drawable/ic_launcher'),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
        payload: payload,
      );

      debugPrint('✅ Scheduled notification for: ${scheduledDate.toString()}');
    } catch (e) {
      debugPrint('❌ Error scheduling notification: $e');
    }
  }

  // Cancel a specific notification
  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  // Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
}
