import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upay/providers/language_provider.dart';
import 'package:upay/screens/welcome_screen.dart';
import 'package:upay/screens/language_selection_screen.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:upay/services/background_service.dart';
import 'package:upay/services/secure_storage_service.dart';
import 'package:upay/services/notification_service.dart';
import 'package:upay/screens/sign_in_screen.dart';
import 'package:upay/screens/dashboard_screen.dart';
import 'package:upay/screens/notification_screen.dart';
import 'package:upay/services/payment_message_service.dart';
import 'package:upay/services/payment_reminder_service.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Background message handler initialized");

  final notification = message.notification;
  final data = message.data;
  final String? messageId = message.messageId ?? data['messageId'];

  if (messageId == null) {
    debugPrint("Message has no ID, cannot process");
    return;
  }

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

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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

  String title, body;
  if (notification != null) {
    title = notification.title ?? 'New Message';
    body = notification.body ?? '';
  } else {
    title = data['title'] ?? data['heading'] ?? 'New Message';
    body = data['body'] ?? data['message'] ?? '';
  }

  if (data['url'] != null && data['url'].toString().isNotEmpty) {
    title = 'title';
  } else if (data['attachments'] != null) {
    title = 'title';
  }

  const NotificationDetails platformDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'Important notifications that require attention',
      importance: Importance.max,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.message,
      playSound: true,
      enableVibration: true,
    ),
    iOS: DarwinNotificationDetails(
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
    payload: json.encode({
      'messageId': messageId,
      'type': data['type'] ?? 'notification',
    }),
  );

  try {
    await Firebase.initializeApp();
    await FirebaseFirestore.instance
        .collection('messages')
        .doc(messageId)
        .update({
          'delivered': true,
          'deliveredAt': FieldValue.serverTimestamp(),
          'deliveryMethod': 'background_handler',
        });
    debugPrint("Marked message as delivered from background handler");
  } catch (e) {
    debugPrint("Error marking message as delivered: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SharedPreferences prefs;
  bool isLanguageSelected;
  bool isWelcomeScreenSeen;
  String savedLanguage;
  bool isLoggedIn = false;
  bool autoSignOutEnabled = false;

  try {
    prefs = await SharedPreferences.getInstance();
    autoSignOutEnabled = prefs.getBool('auto_sign_out_enabled') ?? false;

    if (autoSignOutEnabled) {
      debugPrint("Auto sign out enabled, signing out user");
      await SecureStorageService.clearUserData();
      await prefs.setBool('isLoggedIn', false);
    }

    await Firebase.initializeApp();
    debugPrint("Firebase initialized successfully");

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint("Background message handler registered");

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
      debugPrint("Android notification channel created");
    }

    await PaymentMessagesInitializer.initialize();
    debugPrint("Payment messages service initialized");

    await PaymentReminderInitializer.initialize();
    debugPrint("Payment reminder service initialized");

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

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationTap(response.payload);
      },
    );
    debugPrint("Local notifications initialized");

    await SecureStorageService.initialize();
    debugPrint("Secure storage initialized successfully");

    await NotificationService.initialize();
    debugPrint("Notification service initialized");

    await BackgroundService().initialize();
    debugPrint("Background service initialized");

    isLoggedIn = await SecureStorageService.isUserLoggedIn();
    debugPrint("User logged in: $isLoggedIn");

    if (autoSignOutEnabled && Firebase.apps.isNotEmpty) {
      try {
        await FirebaseAuth.instance.signOut();
        debugPrint(
          "Successfully signed out Firebase user due to auto sign out setting",
        );
      } catch (e) {
        debugPrint("Error signing out Firebase user: $e");
      }
    }

    if (isLoggedIn) {
      await _updateFcmToken();

      await initializeGlobalNotifications();

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleInitialMessage(initialMessage);
      }
    }
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFEF7FF),
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  try {
    prefs = await SharedPreferences.getInstance();
    isLanguageSelected = prefs.getBool('isLanguageSelected') ?? false;
    isWelcomeScreenSeen = prefs.getBool('isWelcomeScreenSeen') ?? false;
    savedLanguage = prefs.getString('language') ?? 'en';
  } catch (e) {
    debugPrint("Error loading shared preferences: $e");
    isLanguageSelected = false;
    isWelcomeScreenSeen = false;
    savedLanguage = 'en';
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => LanguageProvider(Locale(savedLanguage)),
      child: MyApp(
        isLanguageSelected: isLanguageSelected,
        isWelcomeScreenSeen: isWelcomeScreenSeen,
        isLoggedIn: isLoggedIn,
        autoSignOutEnabled: autoSignOutEnabled,
      ),
    ),
  );
}

Future<void> _updateFcmToken() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    await SecureStorageService.saveFcmToken(token);

    final nic = await SecureStorageService.getUserNic();
    final customerId = await SecureStorageService.getUserCustomerId();
    final phoneNumber = await SecureStorageService.getUserPhone();

    if (nic == null || nic.isEmpty) {
      debugPrint("Cannot update FCM token: No NIC available");
      return;
    }

    final String safeNic = nic.replaceAll('/', '_').replaceAll('.', '_');

    await FirebaseFirestore.instance.collection('identity').doc(safeNic).set({
      'nic': nic,
      'customerId': customerId,
      'fcmToken': token,
      'phoneNumber': phoneNumber,
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'lastUpdated': FieldValue.serverTimestamp(),
      'active': true,
    }, SetOptions(merge: true));

    debugPrint("Updated FCM token in Identity collection");

    await FirebaseMessaging.instance.subscribeToTopic('all_users');

    await FirebaseMessaging.instance.subscribeToTopic('user_$safeNic');

    if (customerId != null && customerId.isNotEmpty) {
      await FirebaseMessaging.instance.subscribeToTopic('customer_$customerId');
    }
  } catch (e) {
    debugPrint("Error updating FCM token: $e");
  }
}

void _handleForegroundMessage(RemoteMessage message) {
  try {
    debugPrint("Received foreground message: ${message.messageId}");

    final notification = message.notification;
    final data = message.data;
    final String? messageId = message.messageId ?? data['messageId'];

    if (messageId == null) return;

    String title, body;
    if (notification != null) {
      title = notification.title ?? 'New Message';
      body = notification.body ?? '';
    } else {
      title = data['title'] ?? data['heading'] ?? 'New Message';
      body = data['body'] ?? data['message'] ?? '';
    }

    if (data['url'] != null && data['url'].toString().isNotEmpty) {
      title = 'title';
    } else if (data['attachments'] != null) {
      title = 'title';
    }

    NotificationService.showLocalNotification(
      title: title,
      body: body,
      payload: json.encode({
        'messageId': messageId,
        'type': data['type'] ?? 'notification',
      }),
      id: messageId.hashCode,
    );

    FirebaseFirestore.instance.collection('messages').doc(messageId).update({
      'delivered': true,
      'deliveredAt': FieldValue.serverTimestamp(),
      'deliveryMethod': 'foreground',
    });
  } catch (e) {
    debugPrint("Error handling foreground message: $e");
  }
}

void _handleNotificationTap(String? payload) {
  try {
    if (payload == null) return;

    final data = json.decode(payload);
    final String? messageId = data['messageId'];

    if (messageId != null) {
      debugPrint("Notification tapped: $messageId");

      SecureStorageService.saveLastTappedMessageId(messageId);
    }
  } catch (e) {
    debugPrint("Error handling notification tap: $e");
  }
}

void _handleMessageOpenedApp(RemoteMessage message) {
  try {
    debugPrint("App opened from notification in background");

    final String? messageId = message.messageId ?? message.data['messageId'];

    if (messageId != null) {
      SecureStorageService.saveLastTappedMessageId(messageId);
    }
  } catch (e) {
    debugPrint("Error handling message opened app: $e");
  }
}

void _handleInitialMessage(RemoteMessage message) {
  try {
    debugPrint("App opened from notification in terminated state");

    final String? messageId = message.messageId ?? message.data['messageId'];

    if (messageId != null) {
      SecureStorageService.saveLastTappedMessageId(messageId);
    }
  } catch (e) {
    debugPrint("Error handling initial message: $e");
  }
}

class MyApp extends StatefulWidget {
  final bool isLanguageSelected;
  final bool isWelcomeScreenSeen;
  final bool isLoggedIn;
  final bool autoSignOutEnabled;

  const MyApp({
    super.key,
    required this.isLanguageSelected,
    required this.isWelcomeScreenSeen,
    required this.isLoggedIn,
    required this.autoSignOutEnabled,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForStoredNotification();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForStoredNotification();
    }
  }

  Future<void> _checkForStoredNotification() async {
    if (!widget.isLoggedIn) return;

    try {
      final String? messageId =
          await SecureStorageService.getLastTappedMessageId();

      if (messageId != null && messageId.isNotEmpty) {
        debugPrint("Found stored notification to navigate to: $messageId");

        await SecureStorageService.clearLastTappedMessageId();

        Future.delayed(const Duration(milliseconds: 500), () {
          Navigator.of(
            GlobalNavigatorKey.navigatorKey.currentContext!,
          ).pushNamed('/notifications', arguments: {'messageId': messageId});
        });
      }
    } catch (e) {
      debugPrint("Error checking for stored notification: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LanguageProvider>(context);

    Widget initialScreen;

    if (widget.autoSignOutEnabled) {
      debugPrint("Auto sign out was enabled, showing sign in screen");
      initialScreen = const SignInScreen();
    } else if (widget.isLoggedIn) {
      initialScreen = const DashboardScreen();
    } else if (!widget.isLanguageSelected) {
      initialScreen = const LanguageSelectionScreen();
    } else if (!widget.isWelcomeScreenSeen) {
      initialScreen = const WelcomeScreen();
    } else {
      initialScreen = const SignInScreen();
    }

    return MaterialApp(
      title: 'UPay',
      debugShowCheckedModeBanner: false,
      locale: provider.locale,
      navigatorKey: GlobalNavigatorKey.navigatorKey,
      supportedLocales: const [
        Locale('en', ''),
        Locale('si', ''),
        Locale('ta', ''),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFFEF7FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFEF7FF),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: initialScreen,
      routes: {
        '/dashboard': (context) => const DashboardScreen(),
        '/notifications': (context) => const NotificationScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/signin': (context) => const SignInScreen(),
      },
    );
  }
}

class GlobalNavigatorKey {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings Screen')),
    );
  }
}
