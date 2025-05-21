import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upay/providers/language_provider.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:upay/screens/sign_in_screen.dart';
import 'package:upay/screens/about_us_screen.dart';
import 'package:upay/screens/app_guide_screen.dart';
import 'package:upay/services/auth_service.dart';
import 'package:upay/services/secure_storage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> with AutomaticKeepAliveClientMixin {
  // Enable AutomaticKeepAliveClientMixin to prevent rebuilding when navigating
  @override
  bool get wantKeepAlive => true;
  
  String _selectedLanguage = "English";
  // No more loading state - we'll show content instantly with defaults
  String _userName = "Your Name";
  String _customerId = "Customer ID";
  String? _profileImageUrl;
  bool _autoSignOutEnabled = false;
  bool _isUploadingImage = false;
  String? _nic;

  // Cache for validated URLs to avoid repeated failed requests
  final Map<String, bool> _invalidUrls = {};

  // Language mapping for selection dropdown
  final Map<String, String> languageMap = {
    "English": "en",
    "සිංහල": "si",
    "தமிழ்": "ta",
  };

  // Stream subscriptions for real-time updates
  StreamSubscription? _userProfileSubscription;

  @override
  void initState() {
    super.initState();

    // Set status bar to match background color
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFFEF7FF),
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    // Begin loading everything in parallel
    _loadInitialData();
    
    // Set up real-time updates for user profile
    _setupUserProfileStream();
  }

  @override
  void dispose() {
    // Cancel stream subscriptions to prevent memory leaks
    _userProfileSubscription?.cancel();
    super.dispose();
  }

  // Set up real-time listener for user profile updates
  Future<void> _setupUserProfileStream() async {
    try {
      _nic = await SecureStorageService.getUserNic();
      
      if (_nic != null && _nic!.isNotEmpty) {
        // Listen to customer document changes
        _userProfileSubscription = FirebaseFirestore.instance
            .collection('customers')
            .where('nic', isEqualTo: _nic)
            .limit(1)
            .snapshots()
            .listen((snapshot) {
          if (snapshot.docs.isNotEmpty && mounted) {
            final data = snapshot.docs.first.data();
            
            // Extract user details
            String name = _extractName(data);
            String customerId = data['customerId'] ?? data['customerID'] ?? data['customerNo'] ?? _nic ?? _customerId;
            String? profileImage = _extractProfileImage(data);
            
            setState(() {
              if (name.isNotEmpty) _userName = name;
              _customerId = customerId;
              if (profileImage != null && 
                  profileImage.isNotEmpty && 
                  !_invalidUrls.containsKey(profileImage)) {
                _profileImageUrl = profileImage;
              }
            });
          }
        });
      }
    } catch (e) {
      debugPrint("Error setting up profile stream: $e");
    }
  }

  // Load all initial data in parallel
  Future<void> _loadInitialData() async {
    try {
      // Load all data in parallel for faster startup
      await Future.wait([
        _loadSettings(),
        _loadLanguagePreference(),
        _loadUserData(),
      ]);
    } catch (e) {
      debugPrint("Error loading initial data: $e");
    }
  }

  // Load app settings from shared preferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _autoSignOutEnabled = prefs.getBool('auto_sign_out_enabled') ?? false;
        });
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  // Save app settings to shared preferences
  Future<void> _saveSettings(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint("Error saving setting $key: $e");
    }
  }

  // Load user data from multiple sources
  Future<void> _loadUserData() async {
    if (!mounted) return;

    try {
      // Try loading user data from different sources in parallel
      await Future.wait([
        _loadUserDataFromAuth(),
        _loadUserDataFromFirebaseAuth(''),
      ]);

      // Try to get more data from Firestore using NIC
      _nic = await SecureStorageService.getUserNic();
      String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (_nic != null && _nic!.isNotEmpty) {
        await _loadUserDataFromFirestore(_nic!, userId);
      }

      // Use Firebase Auth as a fallback
      await _loadUserDataFromFirebaseAuth(userId);
    } catch (e) {
      debugPrint("Error in _loadUserData: $e");
    }
  }

  // Load user data from AuthService
  Future<void> _loadUserDataFromAuth() async {
    try {
      final userData = await AuthService.getUserData();

      if (userData.isNotEmpty && mounted) {
        setState(() {
          _userName =
              userData['name'] ??
              userData['fullName'] ??
              userData['nic'] ??
              _userName;
          _customerId =
              userData['customerId'] ?? userData['nic'] ?? _customerId;

          // Check for profile image URL but verify it's not empty
          String? imageUrl;
          if (userData.containsKey('profileImage') &&
              userData['profileImage'] != null &&
              userData['profileImage'].toString().isNotEmpty) {
            imageUrl = userData['profileImage'];
          } else if (userData.containsKey('profileImageUrl') &&
              userData['profileImageUrl'] != null &&
              userData['profileImageUrl'].toString().isNotEmpty) {
            imageUrl = userData['profileImageUrl'];
          } else if (userData.containsKey('photoURL') &&
              userData['photoURL'] != null &&
              userData['photoURL'].toString().isNotEmpty) {
            imageUrl = userData['photoURL'];
          }

          // Only set the URL if it's not already identified as invalid
          if (imageUrl != null && !_invalidUrls.containsKey(imageUrl)) {
            _profileImageUrl = imageUrl;
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading user data from AuthService: $e");
    }
  }

  // Load user data from Firestore
  Future<void> _loadUserDataFromFirestore(String nic, String userId) async {
    try {
      // Initialize customerId with a default value from class member
      String customerId = _customerId;

      // Try with exact NIC first (with shorter timeout)
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('customers')
          .where('nic', isEqualTo: nic)
          .limit(1)
          .get();

      // If no results, try with lowercase/uppercase 'v'/'V' at the end
      if (snapshot.docs.isEmpty && nic.length == 10) {
        if (nic.endsWith('v')) {
          final upperNic = '${nic.substring(0, 9)}V';
          snapshot = await FirebaseFirestore.instance
              .collection('customers')
              .where('nic', isEqualTo: upperNic)
              .limit(1)
              .get();
        } else if (nic.endsWith('V')) {
          final lowerNic = '${nic.substring(0, 9)}v';
          snapshot = await FirebaseFirestore.instance
              .collection('customers')
              .where('nic', isEqualTo: lowerNic)
              .limit(1)
              .get();
        }
      }

      if (snapshot.docs.isNotEmpty && mounted) {
        final data = snapshot.docs.first.data() as Map<String, dynamic>;

        // Extract name from various possible fields
        String name = _extractName(data);

        // Extract customer ID
        customerId =
            data['customerId'] ??
            data['customerID'] ??
            data['customerNo'] ??
            nic;

        // Get user ID if it's in the document
        String? docUserId =
            data['userId'] ?? data['uid'] ?? data['user_id'] ?? '';

        if (docUserId != null && docUserId.isNotEmpty) {
          userId = docUserId;
        }

        // Extract profile image URL
        String? profileImage = _extractProfileImage(data);

        if (mounted) {
          setState(() {
            if (name.isNotEmpty) _userName = name;
            _customerId = customerId;
            if (profileImage != null &&
                profileImage.isNotEmpty &&
                !_invalidUrls.containsKey(profileImage)) {
              _profileImageUrl = profileImage;
            }
          });
        }
      }

      // If we still don't have a profile image, try to load it from Firebase Storage
      if ((_profileImageUrl == null ||
              _profileImageUrl!.isEmpty ||
              _invalidUrls.containsKey(_profileImageUrl)) &&
          mounted) {
        await _loadProfileImageFromStorage(nic, userId, customerId);
      }
    } catch (e) {
      debugPrint("Error loading user data from Firestore: $e");
    }
  }

  // Extract name from Firestore data
  String _extractName(Map<String, dynamic> data) {
    if (data.containsKey('fullName') && data['fullName'] != null) {
      return data['fullName'].toString();
    } else if (data.containsKey('name') && data['name'] != null) {
      return data['name'].toString();
    } else if (data.containsKey('firstName') && data['firstName'] != null) {
      String name = data['firstName'].toString();
      if (data.containsKey('lastName') && data['lastName'] != null) {
        name += ' ${data['lastName']}';
      }
      return name;
    }
    return '';
  }

  // Extract profile image URL from Firestore data
  String? _extractProfileImage(Map<String, dynamic> data) {
    final imageFields = [
      'profileImage',
      'profileImageUrl',
      'photoURL',
      'photoUrl',
      'image',
      'imageUrl',
      'avatar',
      'avatarUrl',
      'picture',
      'pictureUrl',
    ];

    for (final field in imageFields) {
      if (data.containsKey(field) &&
          data[field] != null &&
          data[field].toString().isNotEmpty) {
        return data[field].toString();
      }
    }

    return null;
  }

  // Load user data from Firebase Auth
  Future<void> _loadUserDataFromFirebaseAuth(String userId) async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && mounted) {
        setState(() {
          if (_userName == "Your Name" && currentUser.displayName != null) {
            _userName = currentUser.displayName!;
          }

          if ((_profileImageUrl == null ||
                  _profileImageUrl!.isEmpty ||
                  _invalidUrls.containsKey(_profileImageUrl)) &&
              currentUser.photoURL != null &&
              currentUser.photoURL!.isNotEmpty) {
            _profileImageUrl = currentUser.photoURL;
          }
        });

        // Final fallback for profile image loading
        if (_profileImageUrl == null ||
            _profileImageUrl!.isEmpty ||
            _invalidUrls.containsKey(_profileImageUrl)) {
          if (userId.isEmpty) userId = currentUser.uid;
          await _loadProfileImageFromStorage(null, userId, _customerId);
        }
      }
    } catch (e) {
      debugPrint("Error loading from Firebase Auth: $e");
    }
  }

  // Load profile image from Firebase Storage
  Future<void> _loadProfileImageFromStorage(
    String? nic,
    String userId,
    String customerId,
  ) async {
    if (!mounted) return;

    try {
      // Build a list of identifiers to use (prioritizing userId)
      List<String> identifiers = [];
      if (userId.isNotEmpty) identifiers.add(userId);
      if (customerId != "Customer ID" && customerId.isNotEmpty) {
        identifiers.add(customerId);
      }
      if (nic != null && nic.isNotEmpty) identifiers.add(nic);

      if (identifiers.isEmpty) {
        return;
      }

      final storage = FirebaseStorage.instance;

      // Try direct paths first with reduced timeout
      final String? url = await _tryImagePaths(storage, identifiers);

      if (url != null && mounted) {
        setState(() {
          _profileImageUrl = url;
        });
        return;
      }

      // If direct paths failed, try listing files
      try {
        final listResult = await storage
            .ref('customer_images')
            .list(const ListOptions(maxResults: 25)); // Reduced from 50 for better performance

        for (final id in identifiers) {
          for (var item in listResult.items) {
            if (item.name.toLowerCase().contains(id.toLowerCase())) {
              try {
                final url = await item.getDownloadURL();
                if (mounted) {
                  setState(() {
                    _profileImageUrl = url;
                  });
                  return;
                }
              } catch (_) {
                // Continue to next item
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Error listing files in storage: $e");
      }

      // Check additional common folders
      final List<String> folders = ['profiles', 'profile_images', 'avatars', 'users'];
      
      for (int i = 0; i < folders.length && mounted; i++) {
        try {
          final listResult = await storage
              .ref(folders[i])
              .list(const ListOptions(maxResults: 15)); // Reduced from 30 for better performance

          for (final id in identifiers) {
            for (var item in listResult.items) {
              if (item.name.toLowerCase().contains(id.toLowerCase())) {
                try {
                  final url = await item.getDownloadURL();
                  if (mounted) {
                    setState(() {
                      _profileImageUrl = url;
                    });
                    return;
                  }
                } catch (_) {
                  // Continue to next item
                }
              }
            }
          }
        } catch (_) {
          // Continue to next folder
        }
      }
    } catch (e) {
      debugPrint("Error in _loadProfileImageFromStorage: $e");
    }
  }

  // Try multiple image paths in Firebase Storage
  Future<String?> _tryImagePaths(
    FirebaseStorage storage,
    List<String> identifiers,
  ) async {
    final paths = <String>[];

    // Generate paths to try for each identifier
    for (final id in identifiers) {
      paths.addAll([
        'customer_images/customer_$id.jpg',
        'customer_images/customer_$id.png',
        'customer_images/$id.jpg',
        'customer_images/$id.png',
        'profiles/$id.jpg',
        'profiles/$id.png',
      ]);
    }

    // Try each path - fewer attempts for better performance
    for (int i = 0; i < paths.length && i < 10; i++) {
      try {
        final ref = storage.ref().child(paths[i]);
        final url = await ref.getDownloadURL();
        return url;
      } catch (e) {
        // Just continue to the next path
      }
    }
    return null;
  }

  // Pick and upload profile image
  Future<void> _pickAndUploadImage() async {
    if (_isUploadingImage) return;

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600, // Reduced from 800 for better performance
        maxHeight: 600, // Reduced from 800 for better performance
        imageQuality: 70, // Reduced from 80 for better performance
      );

      if (image == null) return;

      setState(() => _isUploadingImage = true);

      final File imageFile = File(image.path);

      // Create a better filename based on available identifiers
      String fileIdentifier;
      if (_customerId != "Customer ID" && _customerId.isNotEmpty) {
        fileIdentifier = _customerId;
      } else if (_nic != null && _nic!.isNotEmpty) {
        fileIdentifier = _nic!;
      } else {
        final userId =
            FirebaseAuth.instance.currentUser?.uid ??
            DateTime.now().millisecondsSinceEpoch.toString();
        fileIdentifier = userId;
      }

      final String filename =
          'customer_${fileIdentifier.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.jpg';
      final Reference storageRef = FirebaseStorage.instance.ref().child(
        'customer_images/$filename',
      );

      // Upload the file
      final TaskSnapshot snapshot = await storageRef.putFile(imageFile);
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      // Update the image URL in Firestore
      await _updateFirestoreImage(downloadUrl);

      // Clear any invalid URL entries if we have a new valid URL
      if (_profileImageUrl != null) {
        _invalidUrls.remove(_profileImageUrl);
      }

      // Update local state
      if (mounted) {
        setState(() {
          _profileImageUrl = downloadUrl;
          _isUploadingImage = false;
        });

        // Show success message
        _showSnackBar(
          AppLocalizations.of(context)?.profile_image_updated ??
              'Profile image updated successfully',
          Colors.green,
        );
      }
    } catch (e) {
      debugPrint("Error picking/uploading image: $e");
      if (mounted) {
        setState(() => _isUploadingImage = false);
        _showSnackBar(
          AppLocalizations.of(context)?.profile_image_update_failed ??
              'Failed to update profile image',
          Colors.red,
        );
      }
    }
  }

  // Show a snackbar message
  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  // Update user profile image in Firestore
  Future<void> _updateFirestoreImage(String downloadUrl) async {
    try {
      if (_nic == null || _nic!.isEmpty) {
        _nic = await SecureStorageService.getUserNic();
      }

      if (_nic != null && _nic!.isNotEmpty) {
        // Try with exact NIC first
        QuerySnapshot customerSnap =
            await FirebaseFirestore.instance
                .collection('customers')
                .where('nic', isEqualTo: _nic)
                .limit(1)
                .get();

        // If no results, try with lowercase/uppercase 'v'/'V' at the end
        if (customerSnap.docs.isEmpty && _nic!.length == 10) {
          if (_nic!.endsWith('v')) {
            final upperNic = '${_nic!.substring(0, 9)}V';
            customerSnap =
                await FirebaseFirestore.instance
                    .collection('customers')
                    .where('nic', isEqualTo: upperNic)
                    .limit(1)
                    .get();
          } else if (_nic!.endsWith('V')) {
            final lowerNic = '${_nic!.substring(0, 9)}v';
            customerSnap =
                await FirebaseFirestore.instance
                    .collection('customers')
                    .where('nic', isEqualTo: lowerNic)
                    .limit(1)
                    .get();
          }
        }

        if (customerSnap.docs.isNotEmpty) {
          // Update with the new URL (all possible field names)
          await customerSnap.docs.first.reference.update({
            'profileImage': downloadUrl,
            'profileImageUrl': downloadUrl,
            'photoURL': downloadUrl,
            'photoUrl': downloadUrl,
          });

          // Also update Firebase Auth user photo URL
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await user.updatePhotoURL(downloadUrl);
            }
          } catch (e) {
            debugPrint("Error updating Firebase Auth photo URL: $e");
          }
        }
      }
    } catch (e) {
      debugPrint("Error updating Firestore document: $e");
    }
  }

  // Load language preference from shared preferences
  Future<void> _loadLanguagePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedLanguage = prefs.getString("language") ?? "en";

      if (mounted) {
        setState(() {
          for (final entry in languageMap.entries) {
            if (entry.value == storedLanguage) {
              _selectedLanguage = entry.key;
              break;
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading language preference: $e");
    }
  }

  // Change app language
  Future<void> _changeLanguage(String language) async {
    if (!mounted) return;

    final localeCode = languageMap[language] ?? "en";

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("language", localeCode);

      setState(() => _selectedLanguage = language);
      if (mounted) {
        Provider.of<LanguageProvider>(
          context,
          listen: false,
        ).setLocale(Locale(localeCode));
      }
    } catch (e) {
      debugPrint("Error changing language: $e");
    }
  }

  // Clean app data
  Future<void> _cleanData() async {
    final t = AppLocalizations.of(context)!;
    final confirm = await _showConfirmationDialog(
      t.clean_app_data,
      t.clean_app_data_message,
    );

    if (!confirm) return;

    try {
      // Get shared preferences instance
      final prefs = await SharedPreferences.getInstance();
      final language = prefs.getString('language');

      await prefs.clear();
      await prefs.setBool('isWelcomeScreenSeen', false);
      await prefs.setBool('isLoggedIn', false);
      await prefs.setBool('isLanguageSelected', false);

      if (language != null) {
        await prefs.setString('language', language);
      }

      // Clear caches and sign out
      imageCache.clear();
      imageCache.clearLiveImages();
      PaintingBinding.instance.imageCache.clear();

      try {
        await SecureStorageService.clearAllData();
      } catch (_) {}
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      try {
        await FirebaseFirestore.instance.clearPersistence();
      } catch (_) {}

      if (mounted) {
        _showSnackBar(t.data_cleaned_restarting, Colors.green);
        
        // Use smooth navigation without animation
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/', 
            (route) => false,
            // Use PageRouteBuilder for smoother transition
          );
        }
      }
    } catch (_) {
      // Force restart regardless of errors
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  // Show confirmation dialog
  Future<bool> _showConfirmationDialog(String title, String message) async {
    final t = AppLocalizations.of(context)!;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
                title: Text(title),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(t.cancel_clean),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: Text(
                      t.confirm_clean,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
        ) ??
        false;
  }

  // Sign out
  Future<void> _signOut(BuildContext context) async {
    final t = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Text(t.sign_out),
                content: Text(t.sign_out_confirm_message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(t.cancel),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                    ),
                    child: Text(
                      t.sign_out,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await AuthService.signOut();

      // After the async gap, check if both the widget is still mounted and context is valid
      if (mounted && context.mounted) {
        // Use PageRouteBuilder for smoother transition without animation
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, animation1, animation2) => const SignInScreen(),
            transitionDuration: Duration.zero,
          ),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint("Error signing out: $e");
      if (mounted && context.mounted) {
        _showSnackBar(t.sign_out_error, Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Required for AutomaticKeepAliveClientMixin
    super.build(context);
    
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      body: Column(
        children: [
          const SizedBox(height: 80),
          // Title
          Text(
            t.settings,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 50),

          // Profile Header with Image
          _buildProfileHeader(),

          const SizedBox(height: 28), // Space after profile
          // Settings options in scrollable area
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(), // Better physics for low-end devices
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSettingTile(
                    title: t.language,
                    icon: Icons.language,
                    iconColor: Colors.blue,
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedLanguage,
                        borderRadius: BorderRadius.circular(12),
                        items: languageMap.keys.map((language) {
                          return DropdownMenuItem(
                            value: language,
                            child: Text(language),
                          );
                        }).toList(),
                        onChanged: (newLang) {
                          if (newLang != null) _changeLanguage(newLang);
                        },
                      ),
                    ),
                  ),

                  _buildSettingTile(
                    title: t.auto_sign_out,
                    icon: Icons.logout_outlined,
                    iconColor: Colors.orange,
                    trailing: Switch(
                      value: _autoSignOutEnabled,
                      activeColor: Colors.purpleAccent,
                      onChanged: (value) {
                        setState(() => _autoSignOutEnabled = value);
                        _saveSettings('auto_sign_out_enabled', value);
                      },
                    ),
                  ),

                  _buildSettingTile(
                    title: t.app_guide,
                    icon: Icons.help_outline,
                    iconColor: Colors.cyan,
                    onTap: () => Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation1, animation2) => const AppGuideScreen(),
                        transitionDuration: Duration.zero, // No animation for smoother transition
                      ),
                    ),
                  ),

                  _buildSettingTile(
                    title: t.about_us,
                    icon: Icons.info,
                    iconColor: Colors.teal,
                    onTap: () => Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation1, animation2) => const AboutUsScreen(),
                        transitionDuration: Duration.zero, // No animation for smoother transition
                      ),
                    ),
                  ),

                  _buildSettingTile(
                    title: t.clean_data,
                    icon: Icons.cleaning_services,
                    iconColor: Colors.green,
                    onTap: _cleanData,
                  ),

                  _buildSettingTile(
                    title: t.sign_out,
                    icon: Icons.logout,
                    iconColor: Colors.red,
                    isDanger: true,
                    onTap: () => _signOut(context),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build profile header with image
  Widget _buildProfileHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13), // 0.05 * 255 ≈ 13
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _isUploadingImage ? null : _pickAndUploadImage,
              child: Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.purpleAccent, width: 2),
                    ),
                    child: ClipOval(
                      child: _isUploadingImage
                          ? _buildProgressIndicator(24)
                          : _profileImageUrl != null
                              ? _buildProfileImage()
                              : const Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Colors.purple,
                                ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.purpleAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _customerId,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build progress indicator for uploads
  Widget _buildProgressIndicator(double size) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(
          color: Colors.purpleAccent,
          strokeWidth: 2,
        ),
      ),
    );
  }

  // Build profile image from URL
  Widget _buildProfileImage() {
    if (_profileImageUrl == null || _profileImageUrl!.isEmpty) {
      return const Icon(Icons.person, size: 40, color: Colors.purple);
    }

    String imageUrl = _profileImageUrl!.trim();

    // Fix common URL issues
    if (!imageUrl.startsWith('http')) {
      if (imageUrl.startsWith('www.')) {
        imageUrl = 'https://$imageUrl';
      } else {
        // Likely a Firebase Storage URL that failed to load properly
        // Mark as invalid so we don't try it again
        _invalidUrls[imageUrl] = true;
        return const Icon(Icons.person, size: 40, color: Colors.purple);
      }
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: 64,
      height: 64,
      cacheWidth: 128, // Memory efficient caching
      cacheHeight: 128, // Memory efficient caching
      errorBuilder: (_, __, ___) {
        // If load fails, mark URL as invalid so we don't try again
        _invalidUrls[imageUrl] = true;
        return const Icon(Icons.person, size: 40, color: Colors.purple);
      },
      // Simplified loading builder without animation for better performance
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Icon(Icons.person, size: 40, color: Colors.purple);
      },
    );
  }

  // Build setting tile with consistent style
  Widget _buildSettingTile({
    required String title,
    required IconData icon,
    required Color iconColor,
    Widget? trailing,
    bool isDanger = false,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10), // 0.04 * 255 ≈ 10
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDanger
                        ? Colors.red.withAlpha(26) // 0.1 * 255 ≈ 26
                        : iconColor.withAlpha(26), // 0.1 * 255 ≈ 26
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDanger ? Colors.red : null,
                    ),
                  ),
                ),
                if (trailing != null)
                  trailing
                else if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: isDanger ? Colors.red : Colors.grey,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}