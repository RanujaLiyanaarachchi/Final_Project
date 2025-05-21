import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:upay/services/secure_storage_service.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Check if user is logged in
  static Future<bool> isUserLoggedIn() async {
    try {
      // Check secure storage first
      bool isLoggedIn = await SecureStorageService.isUserLoggedIn();
      
      // Also check Firebase Auth
      User? currentUser = _auth.currentUser;
      
      return isLoggedIn && currentUser != null;
    } catch (e) {
      debugPrint("Error checking login status: $e");
      return false;
    }
  }

  // Save user login information
  static Future<void> saveUserLogin({
    required String nic,
    required String phone,
    String? customerId,
  }) async {
    try {
      // Save data in secure storage
      await SecureStorageService.saveUserNic(nic);
      await SecureStorageService.saveUserPhone(phone);
      await SecureStorageService.saveUserLoggedIn(true);
      
      if (customerId != null) {
        await SecureStorageService.saveUserCustomerId(customerId);
      } else {
        // Try to get customer ID from Firestore
        try {
          final result = await _firestore
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
  
  // Get stored user data
  static Future<Map<String, String>> getUserData() async {
    return SecureStorageService.getUserData();
  }
  
  // Sign out user
  static Future<void> signOut() async {
    try {
      // Sign out from Firebase
      await _auth.signOut();
      
      // Clear saved login status
      await SecureStorageService.clearAllData();
      
      debugPrint("User signed out successfully");
    } catch (e) {
      debugPrint("Error signing out: $e");
      rethrow;
    }
  }
  
  // Update FCM token in Firestore
  static Future<void> updateFcmToken() async {
    try {
      String? nic = await SecureStorageService.getUserNic();
      
      if (nic == null || nic.isEmpty) {
        debugPrint("User NIC not found. Cannot update FCM token.");
        return;
      }
      
      // Always update in tokens collection for reliability
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
        // Update Firebase Auth user profile
        await currentUser.updateProfile(photoURL: imageUrl);
        
        // If you store user data in Firestore, update it there too
        final uid = currentUser.uid;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'profileImage': imageUrl, 'photoURL': imageUrl});
      }
    } catch (e) {
      debugPrint("Error updating profile image: $e");
      rethrow;
    }
  }


  // Helper to get platform name
  static String _getPlatformName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}