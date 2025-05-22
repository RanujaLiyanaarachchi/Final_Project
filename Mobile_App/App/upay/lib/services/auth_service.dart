import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:upay/services/secure_storage_service.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<bool> isUserLoggedIn() async {
    try {
      bool isLoggedIn = await SecureStorageService.isUserLoggedIn();

      User? currentUser = _auth.currentUser;

      return isLoggedIn && currentUser != null;
    } catch (e) {
      debugPrint("Error checking login status: $e");
      return false;
    }
  }

  static Future<void> saveUserLogin({
    required String nic,
    required String phone,
    String? customerId,
  }) async {
    try {
      await SecureStorageService.saveUserNic(nic);
      await SecureStorageService.saveUserPhone(phone);
      await SecureStorageService.saveUserLoggedIn(true);

      if (customerId != null) {
        await SecureStorageService.saveUserCustomerId(customerId);
      } else {
        try {
          final result =
              await _firestore
                  .collection('customers')
                  .where('nic', isEqualTo: nic)
                  .limit(1)
                  .get();

          if (result.docs.isNotEmpty) {
            String fetchedCustomerId = result.docs.first.id;
            await SecureStorageService.saveUserCustomerId(fetchedCustomerId);
          }
        } catch (e) {
          debugPrint("Error fetching customer ID: $e");
        }
      }

      debugPrint("User login info saved securely: NIC=$nic, Phone=$phone");
    } catch (e) {
      debugPrint("Error saving user login: $e");
      rethrow;
    }
  }

  static Future<Map<String, String>> getUserData() async {
    return SecureStorageService.getUserData();
  }

  static Future<void> signOut() async {
    try {
      await _auth.signOut();

      await SecureStorageService.clearAllData();

      debugPrint("User signed out successfully");
    } catch (e) {
      debugPrint("Error signing out: $e");
      rethrow;
    }
  }

  static Future<void> updateFcmToken() async {
    try {
      String? nic = await SecureStorageService.getUserNic();

      if (nic.isEmpty) {
        debugPrint("User NIC not found. Cannot update FCM token.");
        return;
      }

      await _firestore.collection('tokens').doc(nic).set({
        'nic': nic,
        'lastUpdate': FieldValue.serverTimestamp(),
        'platform': _getPlatformName(),
      }, SetOptions(merge: true));

      debugPrint("User info updated successfully for NIC: $nic");
    } catch (e) {
      debugPrint("Error updating user info: $e");
    }
  }

  static Future<void> updateProfileImage(String imageUrl) async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await currentUser.updateProfile(photoURL: imageUrl);

        final uid = currentUser.uid;
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'profileImage': imageUrl,
          'photoURL': imageUrl,
        });
      }
    } catch (e) {
      debugPrint("Error updating profile image: $e");
      rethrow;
    }
  }

  static String _getPlatformName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}
