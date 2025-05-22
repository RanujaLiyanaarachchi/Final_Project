import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';

class SecureStorageService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const String _userNicKey = 'secure_user_nic';
  static const String _userPhoneKey = 'secure_user_phone';
  static const String _userLoggedInKey = 'secure_user_logged_in';
  static const String _userCustomerIdKey = 'secure_user_customer_id';
  static const String _encryptionKeyKey = 'encryption_key';
  static const String _fcmTokenKey = 'secure_fcm_token';
  static const String _lastNotificationCheckKey =
      'secure_last_notification_check';

  static Future<void> write({
    required String key,
    required String value,
  }) async {
    await _secureStorage.write(key: key, value: value);
  }

  static Future<String?> read({required String key}) async {
    return await _secureStorage.read(key: key);
  }

  static Future<void> remove({required String key}) async {
    await _secureStorage.delete(key: key);
  }

  static Future<void> clearUserData() async {
    final storage = FlutterSecureStorage();
    await storage.delete(key: 'user_nic');
    await storage.delete(key: 'user_customer_id');
    await storage.delete(key: 'user_phone');
    await storage.delete(key: 'is_logged_in');
    await storage.delete(key: 'fcm_token');
  }

  static Future<void> initialize() async {
    try {
      String? encryptionKey = await _secureStorage.read(key: _encryptionKeyKey);

      if (encryptionKey.isEmpty) {
        final key = encrypt.Key.fromSecureRandom(32).base64;
        await _secureStorage.write(key: _encryptionKeyKey, value: key);
      }

      await _migrateFromSharedPreferences();

      debugPrint("Secure storage initialized");
    } catch (e) {
      debugPrint("Error initializing secure storage: $e");
      rethrow;
    }
  }

  static Future<void> saveProfileImageUrl(String url) async {
    final storage = FlutterSecureStorage();
    await storage.write(key: 'profileImageUrl', value: url);
  }

  static Future<String?> getProfileImageUrl() async {
    final storage = FlutterSecureStorage();
    return await storage.read(key: 'profileImageUrl');
  }

  static Future<void> clearAppData() async {
    final storage = FlutterSecureStorage();

    try {
      await storage.deleteAll();

      final key = encrypt.Key.fromSecureRandom(32).base64;
      await storage.write(key: _encryptionKeyKey, value: key);

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', false);
        await prefs.setBool('isLanguageSelected', false);
        await prefs.setBool('isWelcomeScreenSeen', false);
      } catch (_) {}
    } catch (e) {
      debugPrint('Error clearing app data');
    }
  }

  static Future<void> _migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final hasMigrated = prefs.getBool('secure_storage_migrated') ?? false;
      if (hasMigrated) return;

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

      await prefs.setBool('secure_storage_migrated', true);

      debugPrint("Migration from SharedPreferences completed");
    } catch (e) {
      debugPrint("Error during data migration: $e");
    }
  }

  static Future<void> saveUserNic(String nic) async {
    try {
      await _secureStorage.write(key: _userNicKey, value: nic);
    } catch (e) {
      debugPrint("Error saving user NIC: $e");
      rethrow;
    }
  }

  static Future<String?> getUserNic() async {
    try {
      return await _secureStorage.read(key: _userNicKey);
    } catch (e) {
      debugPrint("Error retrieving user NIC: $e");
      return null;
    }
  }

  static Future<void> saveUserPhone(String phone) async {
    try {
      await _secureStorage.write(key: _userPhoneKey, value: phone);
    } catch (e) {
      debugPrint("Error saving user phone: $e");
      rethrow;
    }
  }

  static Future<String?> getUserPhone() async {
    try {
      return await _secureStorage.read(key: _userPhoneKey);
    } catch (e) {
      debugPrint("Error retrieving user phone: $e");
      return null;
    }
  }

  static Future<void> saveUserLoggedIn(bool isLoggedIn) async {
    try {
      await _secureStorage.write(
        key: _userLoggedInKey,
        value: isLoggedIn.toString(),
      );
    } catch (e) {
      debugPrint("Error saving login status: $e");
      rethrow;
    }
  }

  static Future<bool> isUserLoggedIn() async {
    try {
      final value = await _secureStorage.read(key: _userLoggedInKey);
      return value == 'true';
    } catch (e) {
      debugPrint("Error checking login status: $e");
      return false;
    }
  }

  static Future<void> saveUserCustomerId(String customerId) async {
    try {
      await _secureStorage.write(key: _userCustomerIdKey, value: customerId);
    } catch (e) {
      debugPrint("Error saving customer ID: $e");
      rethrow;
    }
  }

  static Future<String?> getUserCustomerId() async {
    try {
      return await _secureStorage.read(key: _userCustomerIdKey);
    } catch (e) {
      debugPrint("Error retrieving customer ID: $e");
      return null;
    }
  }

  static Future<void> saveFcmToken(String token) async {
    try {
      await _secureStorage.write(key: _fcmTokenKey, value: token);
    } catch (e) {
      debugPrint("Error saving FCM token: $e");
    }
  }

  static Future<String?> getFcmToken() async {
    try {
      return await _secureStorage.read(key: _fcmTokenKey);
    } catch (e) {
      debugPrint("Error retrieving FCM token: $e");
      return null;
    }
  }

  static Future<void> saveLastNotificationCheck(DateTime time) async {
    try {
      await _secureStorage.write(
        key: _lastNotificationCheckKey,
        value: time.millisecondsSinceEpoch.toString(),
      );
    } catch (e) {
      debugPrint("Error saving notification check time: $e");
    }
  }

  static Future<DateTime?> getLastNotificationCheck() async {
    try {
      final value = await _secureStorage.read(key: _lastNotificationCheckKey);
      if (value == null || value.isEmpty) return null;

      final timestamp = int.parse(value);
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      debugPrint("Error retrieving notification check time: $e");
      return null;
    }
  }

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
      debugPrint("Error retrieving user data: $e");
      return {};
    }
  }

  static Future<void> clearAllData() async {
    try {
      await _secureStorage.deleteAll();

      final key = encrypt.Key.fromSecureRandom(32).base64;
      await _secureStorage.write(key: _encryptionKeyKey, value: key);

      debugPrint("All secure data cleared");
    } catch (e) {
      debugPrint("Error clearing secure data: $e");
      rethrow;
    }
  }

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
      debugPrint("Error encrypting data: $e");
      return _hashData(plainText);
    }
  }

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
      debugPrint("Error decrypting data: $e");
      return null;
    }
  }

  static String _hashData(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static const String _lastMessageTimestampKey = 'last_message_timestamp';
  static const String _processedMessageIdsKey = 'processed_message_ids';
  static const String _lastTappedMessageIdKey = 'last_tapped_message_id';

  static Future<void> saveLastMessageTimestamp(int timestamp) async {
    try {
      await _secureStorage.write(
        key: _lastMessageTimestampKey,
        value: timestamp.toString(),
      );
    } catch (e) {
      debugPrint("Error saving last message timestamp: $e");
    }
  }

  static Future<int?> getLastMessageTimestamp() async {
    try {
      final timestampStr = await _secureStorage.read(
        key: _lastMessageTimestampKey,
      );
      if (timestampStr == null || timestampStr.isEmpty) return null;
      return int.tryParse(timestampStr);
    } catch (e) {
      debugPrint("Error retrieving last message timestamp: $e");
      return null;
    }
  }

  static Future<void> saveProcessedMessageIds(List<String> messageIds) async {
    try {
      if (messageIds.length > 100) {
        messageIds = messageIds.sublist(messageIds.length - 100);
      }

      final jsonData = json.encode(messageIds);
      await _secureStorage.write(key: _processedMessageIdsKey, value: jsonData);
    } catch (e) {
      debugPrint("Error saving processed message IDs: $e");
    }
  }

  static Future<List<String>?> getProcessedMessageIds() async {
    try {
      final jsonData = await _secureStorage.read(key: _processedMessageIdsKey);
      if (jsonData == null || jsonData.isEmpty) return [];

      final List<dynamic> decoded = json.decode(jsonData);
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint("Error retrieving processed message IDs: $e");
      return [];
    }
  }

  static Future<void> clearProcessedMessageIds() async {
    try {
      await _secureStorage.delete(key: _processedMessageIdsKey);
    } catch (e) {
      debugPrint("Error clearing processed message IDs: $e");
    }
  }

  static Future<void> saveLastTappedMessageId(String messageId) async {
    try {
      await _secureStorage.write(
        key: _lastTappedMessageIdKey,
        value: messageId,
      );
    } catch (e) {
      debugPrint("Error saving last tapped message ID: $e");
    }
  }

  static Future<String?> getLastTappedMessageId() async {
    try {
      return await _secureStorage.read(key: _lastTappedMessageIdKey);
    } catch (e) {
      debugPrint("Error getting last tapped message ID: $e");
      return null;
    }
  }

  static Future<void> clearLastTappedMessageId() async {
    try {
      await _secureStorage.delete(key: _lastTappedMessageIdKey);
    } catch (e) {
      debugPrint("Error clearing last tapped message ID: $e");
    }
  }
}
