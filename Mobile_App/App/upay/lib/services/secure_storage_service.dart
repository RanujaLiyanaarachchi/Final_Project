import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';

class SecureStorageService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  
  // Key constants
  static const String _userNicKey = 'secure_user_nic';
  static const String _userPhoneKey = 'secure_user_phone';
  static const String _userLoggedInKey = 'secure_user_logged_in';
  static const String _userCustomerIdKey = 'secure_user_customer_id';
  static const String _encryptionKeyKey = 'encryption_key';
  static const String _fcmTokenKey = 'secure_fcm_token';
  static const String _lastNotificationCheckKey = 'secure_last_notification_check';

  // Write data
  static Future<void> write({required String key, required String value}) async {
    await _secureStorage.write(key: key, value: value);
  }

  // Read data
  static Future<String?> read({required String key}) async {
    return await _secureStorage.read(key: key);
  }
  
  // Remove data
  static Future<void> remove({required String key}) async {
    await _secureStorage.delete(key: key);
  }

  // Add the clearUserData method
  static Future<void> clearUserData() async {
    // Implementation that clears user-related data from secure storage
    final storage = FlutterSecureStorage();
    await storage.delete(key: 'user_nic');
    await storage.delete(key: 'user_customer_id');
    await storage.delete(key: 'user_phone');
    await storage.delete(key: 'is_logged_in');
    await storage.delete(key: 'fcm_token');
    // Add any other user-related keys that need to be cleared
  }
  
  // Existing methods like isUserLoggedIn, getUserNic, etc.


  // Initialize secure storage
  static Future<void> initialize() async {
    try {
      // Generate encryption key if not exists
      String? encryptionKey = await _secureStorage.read(key: _encryptionKeyKey);
      
      if (encryptionKey == null || encryptionKey.isEmpty) {
        // Generate a random key for encryption
        final key = encrypt.Key.fromSecureRandom(32).base64;
        await _secureStorage.write(key: _encryptionKeyKey, value: key);
      }
      
      // Migrate data from SharedPreferences if needed
      await _migrateFromSharedPreferences();
      
      debugPrint("✅ Secure storage initialized");
    } catch (e) {
      debugPrint("❌ Error initializing secure storage: $e");
      rethrow;
    }
  }
  


  // Add method to save profile image URL
  static Future<void> saveProfileImageUrl(String url) async {
    final storage = FlutterSecureStorage();
    await storage.write(key: 'profileImageUrl', value: url);
  }
  
  // Add method to get profile image URL
  static Future<String?> getProfileImageUrl() async {
    final storage = FlutterSecureStorage();
    return await storage.read(key: 'profileImageUrl');
  }



  // Method to clear app data - completely clear everything for fresh start
  static Future<void> clearAppData() async {
    final storage = FlutterSecureStorage();
    
    try {
      // Clear all secure storage data
      await storage.deleteAll();
      
      // Recreate encryption key for future use
      final key = encrypt.Key.fromSecureRandom(32).base64;
      await storage.write(key: _encryptionKeyKey, value: key);
      
      // Also clear the isLoggedIn flag in SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', false);
        await prefs.setBool('isLanguageSelected', false);
        await prefs.setBool('isWelcomeScreenSeen', false);
      } catch (_) {
        // Silently ignore errors
      }
    } catch (e) {
      // Silently ignore errors for clean data operation
    }
  }




  // Migrate data from SharedPreferences to SecureStorage (for app upgrades)
  static Future<void> _migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if we've already migrated
      final hasMigrated = prefs.getBool('secure_storage_migrated') ?? false;
      if (hasMigrated) return;
      
      // Migrate user data if available
      final legacyNic = prefs.getString('user_nic');
      final legacyPhone = prefs.getString('user_phone');
      final legacyLoggedIn = prefs.getBool('is_logged_in');
      
      if (legacyNic != null && legacyNic.isNotEmpty) {
        await saveUserNic(legacyNic);
      }
      
      if (legacyPhone != null && legacyPhone.isNotEmpty) {
        await saveUserPhone(legacyPhone);
      }
      
      if (legacyLoggedIn != null) {
        await saveUserLoggedIn(legacyLoggedIn);
      }
      
      // Mark migration as complete
      await prefs.setBool('secure_storage_migrated', true);
      
      debugPrint("✅ Migration from SharedPreferences completed");
    } catch (e) {
      debugPrint("❌ Error during data migration: $e");
    }
  }
  
  // Save user NIC securely
  static Future<void> saveUserNic(String nic) async {
    try {
      await _secureStorage.write(key: _userNicKey, value: nic);
    } catch (e) {
      debugPrint("❌ Error saving user NIC: $e");
      rethrow;
    }
  }
  
  // Get user NIC
  static Future<String?> getUserNic() async {
    try {
      return await _secureStorage.read(key: _userNicKey);
    } catch (e) {
      debugPrint("❌ Error retrieving user NIC: $e");
      return null;
    }
  }
  
  // Save user phone securely
  static Future<void> saveUserPhone(String phone) async {
    try {
      await _secureStorage.write(key: _userPhoneKey, value: phone);
    } catch (e) {
      debugPrint("❌ Error saving user phone: $e");
      rethrow;
    }
  }
  
  // Get user phone
  static Future<String?> getUserPhone() async {
    try {
      return await _secureStorage.read(key: _userPhoneKey);
    } catch (e) {
      debugPrint("❌ Error retrieving user phone: $e");
      return null;
    }
  }
  
  // Save login status
  static Future<void> saveUserLoggedIn(bool isLoggedIn) async {
    try {
      await _secureStorage.write(
        key: _userLoggedInKey, 
        value: isLoggedIn.toString()
      );
    } catch (e) {
      debugPrint("❌ Error saving login status: $e");
      rethrow;
    }
  }
  
  // Check if user is logged in
  static Future<bool> isUserLoggedIn() async {
    try {
      final value = await _secureStorage.read(key: _userLoggedInKey);
      return value == 'true';
    } catch (e) {
      debugPrint("❌ Error checking login status: $e");
      return false;
    }
  }
  
  // Save customer ID
  static Future<void> saveUserCustomerId(String customerId) async {
    try {
      await _secureStorage.write(key: _userCustomerIdKey, value: customerId);
    } catch (e) {
      debugPrint("❌ Error saving customer ID: $e");
      rethrow;
    }
  }
  
  // Get customer ID
  static Future<String?> getUserCustomerId() async {
    try {
      return await _secureStorage.read(key: _userCustomerIdKey);
    } catch (e) {
      debugPrint("❌ Error retrieving customer ID: $e");
      return null;
    }
  }
  
  // Save FCM token
  static Future<void> saveFcmToken(String token) async {
    try {
      await _secureStorage.write(key: _fcmTokenKey, value: token);
    } catch (e) {
      debugPrint("❌ Error saving FCM token: $e");
    }
  }
  
  // Get FCM token
  static Future<String?> getFcmToken() async {
    try {
      return await _secureStorage.read(key: _fcmTokenKey);
    } catch (e) {
      debugPrint("❌ Error retrieving FCM token: $e");
      return null;
    }
  }
  
  // Save last notification check time
  static Future<void> saveLastNotificationCheck(DateTime time) async {
    try {
      await _secureStorage.write(
        key: _lastNotificationCheckKey, 
        value: time.millisecondsSinceEpoch.toString()
      );
    } catch (e) {
      debugPrint("❌ Error saving notification check time: $e");
    }
  }
  
  // Get last notification check time
  static Future<DateTime?> getLastNotificationCheck() async {
    try {
      final value = await _secureStorage.read(key: _lastNotificationCheckKey);
      if (value == null || value.isEmpty) return null;
      
      final timestamp = int.parse(value);
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      debugPrint("❌ Error retrieving notification check time: $e");
      return null;
    }
  }
  
  // Get all user data in a single call (for profile display)
  static Future<Map<String, String>> getUserData() async {
    try {
      final Map<String, String> userData = {};
      
      final nic = await getUserNic();
      final phone = await getUserPhone();
      final customerId = await getUserCustomerId();
      
      if (nic != null) userData['nic'] = nic;
      if (phone != null) userData['phone'] = phone;
      if (customerId != null) userData['customerId'] = customerId;
      
      return userData;
    } catch (e) {
      debugPrint("❌ Error retrieving user data: $e");
      return {};
    }
  }
  
  // Clear all secure data (used during logout)
  static Future<void> clearAllData() async {
    try {
      await _secureStorage.deleteAll();
      
      // Recreate encryption key for future use
      final key = encrypt.Key.fromSecureRandom(32).base64;
      await _secureStorage.write(key: _encryptionKeyKey, value: key);
      
      debugPrint("✅ All secure data cleared");
    } catch (e) {
      debugPrint("❌ Error clearing secure data: $e");
      rethrow;
    }
  }
  
  // Utility: encrypt a string using the stored key
  static Future<String> encryptData(String plainText) async {
    try {
      final keyString = await _secureStorage.read(key: _encryptionKeyKey);
      if (keyString == null) throw Exception("Encryption key not found");
      
      final key = encrypt.Key.fromBase64(keyString);
      final iv = encrypt.IV.fromLength(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      return encrypted.base64;
    } catch (e) {
      debugPrint("❌ Error encrypting data: $e");
      // Fallback to simple hashing if encryption fails
      return _hashData(plainText);
    }
  }
  
  // Utility: decrypt a string using the stored key
  static Future<String?> decryptData(String encryptedText) async {
    try {
      final keyString = await _secureStorage.read(key: _encryptionKeyKey);
      if (keyString == null) return null;
      
      final key = encrypt.Key.fromBase64(keyString);
      final iv = encrypt.IV.fromLength(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      
      final encrypted = encrypt.Encrypted.fromBase64(encryptedText);
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      debugPrint("❌ Error decrypting data: $e");
      return null;
    }
  }
  
  // Simple hashing fallback (less secure than encryption)
  static String _hashData(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  


// Add these methods to your SecureStorageService class (if they aren't already there):

  static const String _lastMessageTimestampKey = 'last_message_timestamp';
  static const String _processedMessageIdsKey = 'processed_message_ids';
  static const String _lastTappedMessageIdKey = 'last_tapped_message_id';

  // Save last message timestamp to avoid duplicate notifications
  static Future<void> saveLastMessageTimestamp(int timestamp) async {
    try {
      await _secureStorage.write(
        key: _lastMessageTimestampKey, 
        value: timestamp.toString()
      );
    } catch (e) {
      debugPrint("❌ Error saving last message timestamp: $e");
    }
  }

  // Get last message timestamp
  static Future<int?> getLastMessageTimestamp() async {
    try {
      final timestampStr = await _secureStorage.read(key: _lastMessageTimestampKey);
      if (timestampStr == null || timestampStr.isEmpty) return null;
      return int.tryParse(timestampStr);
    } catch (e) {
      debugPrint("❌ Error retrieving last message timestamp: $e");
      return null;
    }
  }
  
  // Save processed message IDs to prevent duplicate notifications
  static Future<void> saveProcessedMessageIds(List<String> messageIds) async {
    try {
      // Keep only the latest 100 message IDs to prevent storage bloat
      if (messageIds.length > 100) {
        messageIds = messageIds.sublist(messageIds.length - 100);
      }
      
      final jsonData = json.encode(messageIds);
      await _secureStorage.write(key: _processedMessageIdsKey, value: jsonData);
    } catch (e) {
      debugPrint("❌ Error saving processed message IDs: $e");
    }
  }

  // Get processed message IDs
  static Future<List<String>?> getProcessedMessageIds() async {
    try {
      final jsonData = await _secureStorage.read(key: _processedMessageIdsKey);
      if (jsonData == null || jsonData.isEmpty) return [];
      
      final List<dynamic> decoded = json.decode(jsonData);
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint("❌ Error retrieving processed message IDs: $e");
      return [];
    }
  }

  // Clear processed message IDs (useful for debugging)
  static Future<void> clearProcessedMessageIds() async {
    try {
      await _secureStorage.delete(key: _processedMessageIdsKey);
    } catch (e) {
      debugPrint("❌ Error clearing processed message IDs: $e");
    }
  }

  // Save the ID of the last tapped message notification
  static Future<void> saveLastTappedMessageId(String messageId) async {
    try {
      await _secureStorage.write(key: _lastTappedMessageIdKey, value: messageId);
    } catch (e) {
      debugPrint("❌ Error saving last tapped message ID: $e");
    }
  }
  
  // Get the ID of the last tapped message notification
  static Future<String?> getLastTappedMessageId() async {
    try {
      return await _secureStorage.read(key: _lastTappedMessageIdKey);
    } catch (e) {
      debugPrint("❌ Error getting last tapped message ID: $e");
      return null;
    }
  }
  
  // Clear the stored message ID after navigation
  static Future<void> clearLastTappedMessageId() async {
    try {
      await _secureStorage.delete(key: _lastTappedMessageIdKey);
    } catch (e) {
      debugPrint("❌ Error clearing last tapped message ID: $e");
    }
  }



  

}