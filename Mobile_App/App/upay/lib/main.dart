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

// Global notification plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Background message handler - MUST BE TOP-LEVEL FUNCTION
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase first
  await Firebase.initializeApp();
  debugPrint("📲 Background message handler initialized");

  // Extract message data
  final notification = message.notification;
  final data = message.data;
  final String? messageId = message.messageId ?? data['messageId'];

  if (messageId == null) {
    debugPrint("❌ Message has no ID, cannot process");
    return;
  }

  // Create notification channel (required for Android)
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

  // Initialize notifications plugin
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
  String title, body;
  if (notification != null) {
    title = notification.title ?? 'New Message';
    body = notification.body ?? '';
  } else {
    title = data['title'] ?? data['heading'] ?? 'New Message';
    body = data['body'] ?? data['message'] ?? '';
  }

  // Check for attachments
  if (data['url'] != null && data['url'].toString().isNotEmpty) {
    title = 'title';
  } else if (data['attachments'] != null) {
    title = 'title';
  }

  // Create notification details
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

  // Show notification
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

  // Mark as delivered if possible
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
    debugPrint("✅ Marked message as delivered from background handler");
  } catch (e) {
    debugPrint("❌ Error marking message as delivered: $e");
  }
}

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved language and welcome screen flag - we'll need this whether Firebase initializes or not
  SharedPreferences prefs;
  bool isLanguageSelected;
  bool isWelcomeScreenSeen;
  String savedLanguage;
  bool isLoggedIn = false;
  bool autoSignOutEnabled = false;

  try {
    // Check for auto sign out setting
    prefs = await SharedPreferences.getInstance();
    autoSignOutEnabled = prefs.getBool('auto_sign_out_enabled') ?? false;

    // If auto sign out is enabled, clear login state
    if (autoSignOutEnabled) {
      debugPrint("🔐 Auto sign out enabled, signing out user");
      await SecureStorageService.clearUserData();
      await prefs.setBool('isLoggedIn', false);
    }

    // 1. Initialize Firebase first
    await Firebase.initializeApp();
    debugPrint("✅ Firebase initialized successfully");

    // 2. Register background handler IMMEDIATELY after Firebase init
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint("✅ Background message handler registered");

    // 3. Set up notification channel for Android
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
      debugPrint("✅ Android notification channel created");
    }

    // Initialize the payment messages service
    await PaymentMessagesInitializer.initialize();
    debugPrint("✅ Payment messages service initialized");

    // After Firebase initialization and before runApp()
    // Initialize the payment reminder service
    await PaymentReminderInitializer.initialize();
    debugPrint("✅ Payment reminder service initialized");

    // 4. Initialize local notifications
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

    // Handle notification taps
    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationTap(response.payload);
      },
    );
    debugPrint("✅ Local notifications initialized");

    // 5. Initialize SecureStorage - do this early
    await SecureStorageService.initialize();
    debugPrint("✅ Secure storage initialized successfully");

    // 6. Initialize notification service
    await NotificationService.initialize();
    debugPrint("✅ Notification service initialized");

    // 7. Initialize background service
    await BackgroundService().initialize();
    debugPrint("✅ Background service initialized");

    // 8. Check if user is logged in (after potentially clearing with auto sign out)
    isLoggedIn = await SecureStorageService.isUserLoggedIn();
    debugPrint("👤 User logged in: $isLoggedIn");

    // If auto sign out was enabled, also sign out from Firebase
    if (autoSignOutEnabled && Firebase.apps.isNotEmpty) {
      try {
        await FirebaseAuth.instance.signOut();
        debugPrint(
          "✅ Successfully signed out Firebase user due to auto sign out setting",
        );
      } catch (e) {
        debugPrint("❌ Error signing out Firebase user: $e");
      }
    }

    // 9. If user is logged in, update FCM token and set up notification listeners
    if (isLoggedIn) {
      // Update FCM token in database
      await _updateFcmToken();

      // in main.dart after Firebase.initializeApp()
      await initializeGlobalNotifications();

      // Initialize the payment messages service

      // Dispose when your app is closing

      // Inside your main() function after Firebase initialization

      // When the app is closing

      // And before your app closes

      // Set up foreground message handler
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Set up message opened handler
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Check for initial message (app opened from terminated state)
      RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleInitialMessage(initialMessage);
      }
    }
  } catch (e) {
    debugPrint("❌ Firebase initialization error: $e");
    // Continue without Firebase for UI testing
  }

  // Set initial status bar color and icon brightness
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFEF7FF),
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Load user preferences
  try {
    prefs = await SharedPreferences.getInstance();
    isLanguageSelected = prefs.getBool('isLanguageSelected') ?? false;
    isWelcomeScreenSeen = prefs.getBool('isWelcomeScreenSeen') ?? false;
    savedLanguage = prefs.getString('language') ?? 'en';
  } catch (e) {
    debugPrint("❌ Error loading shared preferences: $e");
    // Fallback values
    isLanguageSelected = false;
    isWelcomeScreenSeen = false;
    savedLanguage = 'en';
  }

  // Launch the app
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

// Update FCM token
Future<void> _updateFcmToken() async {
  try {
    // Get FCM token
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    // Save token locally
    await SecureStorageService.saveFcmToken(token);

    // Get user info
    final nic = await SecureStorageService.getUserNic();
    final customerId = await SecureStorageService.getUserCustomerId();
    final phoneNumber = await SecureStorageService.getUserPhone();

    if (nic == null || nic.isEmpty) {
      debugPrint("❌ Cannot update FCM token: No NIC available");
      return;
    }

    // Create sanitized version of NIC for document ID
    final String safeNic = nic.replaceAll('/', '_').replaceAll('.', '_');

    // Update Identity collection
    await FirebaseFirestore.instance.collection('identity').doc(safeNic).set({
      'nic': nic,
      'customerId': customerId,
      'fcmToken': token,
      'phoneNumber': phoneNumber,
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'lastUpdated': FieldValue.serverTimestamp(),
      'active': true,
    }, SetOptions(merge: true));

    debugPrint("✅ Updated FCM token in Identity collection");

    // Subscribe to topics
    await FirebaseMessaging.instance.subscribeToTopic('all_users');

    // Subscribe to user-specific topic
    await FirebaseMessaging.instance.subscribeToTopic('user_$safeNic');

    // Subscribe to customer-specific topic if available
    if (customerId != null && customerId.isNotEmpty) {
      await FirebaseMessaging.instance.subscribeToTopic('customer_$customerId');
    }
  } catch (e) {
    debugPrint("❌ Error updating FCM token: $e");
  }
}

// Handle foreground messages
void _handleForegroundMessage(RemoteMessage message) {
  try {
    debugPrint("📲 Received foreground message: ${message.messageId}");

    // Extract message data
    final notification = message.notification;
    final data = message.data;
    final String? messageId = message.messageId ?? data['messageId'];

    if (messageId == null) return;

    // Format notification content
    String title, body;
    if (notification != null) {
      title = notification.title ?? 'New Message';
      body = notification.body ?? '';
    } else {
      title = data['title'] ?? data['heading'] ?? 'New Message';
      body = data['body'] ?? data['message'] ?? '';
    }

    // Check for attachments
    if (data['url'] != null && data['url'].toString().isNotEmpty) {
      title = 'title';
    } else if (data['attachments'] != null) {
      title = 'title';
    }

    // Show notification
    NotificationService.showLocalNotification(
      title: title,
      body: body,
      payload: json.encode({
        'messageId': messageId,
        'type': data['type'] ?? 'notification',
      }),
      id: messageId.hashCode,
    );

    // Mark as delivered
    FirebaseFirestore.instance.collection('messages').doc(messageId).update({
      'delivered': true,
      'deliveredAt': FieldValue.serverTimestamp(),
      'deliveryMethod': 'foreground',
    });
  } catch (e) {
    debugPrint("❌ Error handling foreground message: $e");
  }
}

// Handle notification taps
void _handleNotificationTap(String? payload) {
  try {
    if (payload == null) return;

    final data = json.decode(payload);
    final String? messageId = data['messageId'];

    if (messageId != null) {
      debugPrint("📱 Notification tapped: $messageId");

      // Store for navigation
      SecureStorageService.saveLastTappedMessageId(messageId);
    }
  } catch (e) {
    debugPrint("❌ Error handling notification tap: $e");
  }
}

// Handle when app is opened from a notification while in background
void _handleMessageOpenedApp(RemoteMessage message) {
  try {
    debugPrint("📱 App opened from notification in background");

    final String? messageId = message.messageId ?? message.data['messageId'];

    if (messageId != null) {
      // Store for navigation after app is fully loaded
      SecureStorageService.saveLastTappedMessageId(messageId);
    }
  } catch (e) {
    debugPrint("❌ Error handling message opened app: $e");
  }
}

// Handle when app is opened from a notification in terminated state
void _handleInitialMessage(RemoteMessage message) {
  try {
    debugPrint("📱 App opened from notification in terminated state");

    final String? messageId = message.messageId ?? message.data['messageId'];

    if (messageId != null) {
      // Store for navigation after app is fully loaded
      SecureStorageService.saveLastTappedMessageId(messageId);
    }
  } catch (e) {
    debugPrint("❌ Error handling initial message: $e");
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

    // Check for notification navigation after app is built
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
      // App came to the foreground - check for notifications
      _checkForStoredNotification();
    }
  }

  // Check if we need to navigate to a notification
  Future<void> _checkForStoredNotification() async {
    if (!widget.isLoggedIn) return;

    try {
      final String? messageId =
          await SecureStorageService.getLastTappedMessageId();

      if (messageId != null && messageId.isNotEmpty) {
        debugPrint("📱 Found stored notification to navigate to: $messageId");

        // Clear it to prevent repeated navigation
        await SecureStorageService.clearLastTappedMessageId();

        // Navigate to notification screen
        Future.delayed(const Duration(milliseconds: 500), () {
          Navigator.of(
            GlobalNavigatorKey.navigatorKey.currentContext!,
          ).pushNamed('/notifications', arguments: {'messageId': messageId});
        });
      }
    } catch (e) {
      debugPrint("❌ Error checking for stored notification: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LanguageProvider>(context);

    // Determine initial screen
    Widget initialScreen;

    // Force sign-in screen if auto sign out was enabled
    if (widget.autoSignOutEnabled) {
      debugPrint("🔐 Auto sign out was enabled, showing sign in screen");
      initialScreen = const SignInScreen();
    } else if (widget.isLoggedIn) {
      // User is logged in, go directly to dashboard
      initialScreen = const DashboardScreen();
    } else if (!widget.isLanguageSelected) {
      // Language not selected, show language selection
      initialScreen = const LanguageSelectionScreen();
    } else if (!widget.isWelcomeScreenSeen) {
      // Welcome screen not seen, show welcome
      initialScreen = const WelcomeScreen();
    } else {
      // Default to sign in screen
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

// Placeholder for required class
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
