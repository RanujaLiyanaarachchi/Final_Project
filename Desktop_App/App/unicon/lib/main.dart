import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'screens/splash.dart';
import 'server/firebase.dart'; // your custom firebase initializer

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Center window on desktop platforms (Windows, macOS, Linux)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    // Only configure window position to center, keep default size
    WindowOptions windowOptions = const WindowOptions(
      center: true, // This centers the window on the screen
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await initializeFirebase(); // initialize with your web config
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}
