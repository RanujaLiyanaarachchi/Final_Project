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
      // Load user info
      _customerId = await SecureStorageService.getUserCustomerId();
      _userNic = await SecureStorageService.getUserNic();

      if (_customerId == null || _userNic == null) {
        debugPrint('⚠️ Background service: User not logged in');
        return;
      }

      // Request notification permissions
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          );

      debugPrint('📱 User granted permission: ${settings.authorizationStatus}');

      // Subscribe to real-time updates for new messages
      await _subscribeToNewMessages();

      _initialized = true;
      debugPrint('✅ Background service initialized');
    } catch (e) {
      debugPrint('❌ Error initializing background service: $e');
    }
  }

  Future<void> _subscribeToNewMessages() async {
    if (_customerId == null) return;

    // Cancel existing subscription if any
    await _messageSubscription?.cancel();

    // Get the last message timestamp
    final lastMessageTime =
        await SecureStorageService.getLastMessageTimestamp();

    // Create a query for messages newer than the last seen
    Query query = _firestore
        .collection('messages')
        .where('customerId', isEqualTo: _customerId);

    if (lastMessageTime != null) {
      query = query.where(
        'createdAt',
        isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastMessageTime),
      );
    }

    // Subscribe to real-time updates
    _messageSubscription = query.snapshots().listen(
      (snapshot) {
        // Handle new messages
        _handleNewMessages(snapshot);
      },
      onError: (error) {
        debugPrint('❌ Error subscribing to messages: $error');
      },
    );
  }

  Future<void> _handleNewMessages(QuerySnapshot snapshot) async {
    try {
      // Process each added or modified document
      for (final doc in snapshot.docChanges) {
        // Skip if not a new message
        if (doc.type != DocumentChangeType.added) continue;

        final message = doc.doc.data() as Map<String, dynamic>?;
        if (message == null) continue;

        // Skip messages that are not for this customer
        if (message['customerId'] != _customerId) continue;

        final messageId = doc.doc.id;
        final createdAt = message['createdAt'] as Timestamp?;

        // Update the last message timestamp
        if (createdAt != null) {
          await SecureStorageService.saveLastMessageTimestamp(
            createdAt.millisecondsSinceEpoch,
          );
        }

        // Check if the message was already delivered
        if (message['delivered'] == true) continue;

        // Show notification for this message
        await _showNotification(message, messageId);

        // Mark as delivered
        await _firestore.collection('messages').doc(messageId).update({
          'delivered': true,
          'deliveredAt': FieldValue.serverTimestamp(),
          'deliveryMethod': 'background_service',
        });
      }
    } catch (e) {
      debugPrint('❌ Error handling new messages: $e');
    }
  }

  Future<void> _showNotification(
    Map<String, dynamic> message,
    String messageId,
  ) async {
    try {
      // Initialize local notifications
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();

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

        await flutterLocalNotificationsPlugin
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
      await flutterLocalNotificationsPlugin.initialize(initSettings);

      // Format notification content
      String title = message['heading'] ?? 'New Message';
      String body = message['message'] ?? '';

      // Create notification details with style information
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

      // Show notification
      await flutterLocalNotificationsPlugin.show(
        messageId.hashCode,
        title,
        body,
        platformDetails,
        payload: json.encode({'messageId': messageId, 'type': 'message'}),
      );

      debugPrint('✅ Showed notification for message: $messageId');
    } catch (e) {
      debugPrint('❌ Error showing notification: $e');
    }
  }

  // Clean up when service is disposed
  void dispose() {
    _messageSubscription?.cancel();
    _initialized = false;
  }
}
