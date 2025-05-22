import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:upay/services/secure_storage_service.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();

  factory BackgroundService() {
    return _instance;
  }

  BackgroundService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot>? _messageSubscription;
  String? _customerId;
  String? _userNic;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _customerId = await SecureStorageService.getUserCustomerId();
      _userNic = await SecureStorageService.getUserNic();

      if (_customerId == null || _userNic == null) {
        debugPrint('Background service: User not logged in');
        return;
      }

      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          );

      debugPrint('User granted permission: ${settings.authorizationStatus}');

      await _subscribeToNewMessages();

      _initialized = true;
      debugPrint('Background service initialized');
    } catch (e) {
      debugPrint('Error initializing background service: $e');
    }
  }

  Future<void> _subscribeToNewMessages() async {
    if (_customerId == null) return;

    await _messageSubscription?.cancel();

    final lastMessageTime =
        await SecureStorageService.getLastMessageTimestamp();

    Query query = _firestore
        .collection('messages')
        .where('customerId', isEqualTo: _customerId);

    if (lastMessageTime != null) {
      query = query.where(
        'createdAt',
        isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastMessageTime),
      );
    }

    _messageSubscription = query.snapshots().listen(
      (snapshot) {
        _handleNewMessages(snapshot);
      },
      onError: (error) {
        debugPrint('❌ Error subscribing to messages: $error');
      },
    );
  }

  Future<void> _handleNewMessages(QuerySnapshot snapshot) async {
    try {
      for (final doc in snapshot.docChanges) {
        if (doc.type != DocumentChangeType.added) continue;

        final message = doc.doc.data() as Map<String, dynamic>?;
        if (message == null) continue;

        if (message['customerId'] != _customerId) continue;

        final messageId = doc.doc.id;
        final createdAt = message['createdAt'] as Timestamp?;

        if (createdAt != null) {
          await SecureStorageService.saveLastMessageTimestamp(
            createdAt.millisecondsSinceEpoch,
          );
        }

        if (message['delivered'] == true) continue;

        await _showNotification(message, messageId);

        await _firestore.collection('messages').doc(messageId).update({
          'delivered': true,
          'deliveredAt': FieldValue.serverTimestamp(),
          'deliveryMethod': 'background_service',
        });
      }
    } catch (e) {
      debugPrint('Error handling new messages: $e');
    }
  }

  Future<void> _showNotification(
    Map<String, dynamic> message,
    String messageId,
  ) async {
    try {
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();

      if (Platform.isAndroid) {
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'high_importance_channel',
          'High Importance Notifications',
          description: 'Important notifications that require attention',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        );

        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(channel);
      }

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
      await flutterLocalNotificationsPlugin.initialize(initSettings);

      String title = message['heading'] ?? 'New Message';
      String body = message['message'] ?? '';

      final NotificationDetails platformDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'Important notifications that require attention',
          importance: Importance.max,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          playSound: true,
          enableVibration: true,
          largeIcon: DrawableResourceAndroidBitmap('@drawable/ic_launcher'),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await flutterLocalNotificationsPlugin.show(
        messageId.hashCode,
        title,
        body,
        platformDetails,
        payload: json.encode({'messageId': messageId, 'type': 'message'}),
      );

      debugPrint('Showed notification for message: $messageId');
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  void dispose() {
    _messageSubscription?.cancel();
    _initialized = false;
  }
}
