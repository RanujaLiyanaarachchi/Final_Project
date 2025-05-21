import 'package:firebase_core/firebase_core.dart';

Future<void> initializeFirebase() async {
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyC7YjS8RYmvHAeO3FFE5wZKwN5PanT1Upc",
      authDomain: "unicon-finance-srilanka.firebaseapp.com",
      projectId: "unicon-finance-srilanka",
      storageBucket: "unicon-finance-srilanka.firebasestorage.app",
      messagingSenderId: "192169165327",
      appId: "1:192169165327:web:df53e7e5a02194b557997a",
    ),
  );
}
