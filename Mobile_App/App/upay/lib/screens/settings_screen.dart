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

class SettingsScreenState extends State<SettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _selectedLanguage = "English";
  String _userName = "Your Name";
  String _customerId = "Customer ID";
  String? _profileImageUrl;
  bool _autoSignOutEnabled = false;
  bool _isUploadingImage = false;
  String? _nic;

  final Map<String, bool> _invalidUrls = {};

  final Map<String, String> languageMap = {
    "English": "en",
    "සිංහල": "si",
    "தமிழ்": "ta",
  };

  StreamSubscription? _userProfileSubscription;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFFEF7FF),
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _loadInitialData();

    _setupUserProfileStream();
  }

  @override
  void dispose() {
    _userProfileSubscription?.cancel();
    super.dispose();
  }

  Future<void> _setupUserProfileStream() async {
    try {
      _nic = await SecureStorageService.getUserNic();

      if (_nic != null && _nic!.isNotEmpty) {
        _userProfileSubscription = FirebaseFirestore.instance
            .collection('customers')
            .where('nic', isEqualTo: _nic)
            .limit(1)
            .snapshots()
            .listen((snapshot) {
              if (snapshot.docs.isNotEmpty && mounted) {
                final data = snapshot.docs.first.data();

                String name = _extractName(data);
                String customerId =
                    data['customerId'] ??
                    data['customerID'] ??
                    data['customerNo'] ??
                    _nic ??
                    _customerId;
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

  Future<void> _loadInitialData() async {
    try {
      await Future.wait([
        _loadSettings(),
        _loadLanguagePreference(),
        _loadUserData(),
      ]);
    } catch (e) {
      debugPrint("Error loading initial data: $e");
    }
  }

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

  Future<void> _saveSettings(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint("Error saving setting $key: $e");
    }
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;

    try {
      await Future.wait([
        _loadUserDataFromAuth(),
        _loadUserDataFromFirebaseAuth(''),
      ]);

      _nic = await SecureStorageService.getUserNic();
      String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (_nic != null && _nic!.isNotEmpty) {
        await _loadUserDataFromFirestore(_nic!, userId);
      }

      await _loadUserDataFromFirebaseAuth(userId);
    } catch (e) {
      debugPrint("Error in _loadUserData: $e");
    }
  }

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

          if (imageUrl != null && !_invalidUrls.containsKey(imageUrl)) {
            _profileImageUrl = imageUrl;
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading user data from AuthService: $e");
    }
  }

  Future<void> _loadUserDataFromFirestore(String nic, String userId) async {
    try {
      String customerId = _customerId;

      QuerySnapshot snapshot =
          await FirebaseFirestore.instance
              .collection('customers')
              .where('nic', isEqualTo: nic)
              .limit(1)
              .get();

      if (snapshot.docs.isEmpty && nic.length == 10) {
        if (nic.endsWith('v')) {
          final upperNic = '${nic.substring(0, 9)}V';
          snapshot =
              await FirebaseFirestore.instance
                  .collection('customers')
                  .where('nic', isEqualTo: upperNic)
                  .limit(1)
                  .get();
        } else if (nic.endsWith('V')) {
          final lowerNic = '${nic.substring(0, 9)}v';
          snapshot =
              await FirebaseFirestore.instance
                  .collection('customers')
                  .where('nic', isEqualTo: lowerNic)
                  .limit(1)
                  .get();
        }
      }

      if (snapshot.docs.isNotEmpty && mounted) {
        final data = snapshot.docs.first.data() as Map<String, dynamic>;

        String name = _extractName(data);

        customerId =
            data['customerId'] ??
            data['customerID'] ??
            data['customerNo'] ??
            nic;

        String? docUserId =
            data['userId'] ?? data['uid'] ?? data['user_id'] ?? '';

        if (docUserId != null && docUserId.isNotEmpty) {
          userId = docUserId;
        }

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

  Future<void> _loadProfileImageFromStorage(
    String? nic,
    String userId,
    String customerId,
  ) async {
    if (!mounted) return;

    try {
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

      final String? url = await _tryImagePaths(storage, identifiers);

      if (url != null && mounted) {
        setState(() {
          _profileImageUrl = url;
        });
        return;
      }

      try {
        final listResult = await storage
            .ref('customer_images')
            .list(const ListOptions(maxResults: 25));

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
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        debugPrint("Error listing files in storage: $e");
      }

      final List<String> folders = [
        'profiles',
        'profile_images',
        'avatars',
        'users',
      ];

      for (int i = 0; i < folders.length && mounted; i++) {
        try {
          final listResult = await storage
              .ref(folders[i])
              .list(const ListOptions(maxResults: 15));

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
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("Error in _loadProfileImageFromStorage: $e");
    }
  }

  Future<String?> _tryImagePaths(
    FirebaseStorage storage,
    List<String> identifiers,
  ) async {
    final paths = <String>[];

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

    for (int i = 0; i < paths.length && i < 10; i++) {
      try {
        final ref = storage.ref().child(paths[i]);
        final url = await ref.getDownloadURL();
        return url;
      } catch (e) {
        debugPrint("Error getting download URL for $paths[i]: $e");
      }
    }
    return null;
  }

  Future<void> _pickAndUploadImage() async {
    if (_isUploadingImage) return;

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 70,
      );

      if (image == null) return;

      setState(() => _isUploadingImage = true);

      final File imageFile = File(image.path);

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

      final TaskSnapshot snapshot = await storageRef.putFile(imageFile);
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      await _updateFirestoreImage(downloadUrl);

      if (_profileImageUrl != null) {
        _invalidUrls.remove(_profileImageUrl);
      }

      if (mounted) {
        setState(() {
          _profileImageUrl = downloadUrl;
          _isUploadingImage = false;
        });

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

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  Future<void> _updateFirestoreImage(String downloadUrl) async {
    try {
      if (_nic == null || _nic!.isEmpty) {
        _nic = await SecureStorageService.getUserNic();
      }

      if (_nic != null && _nic!.isNotEmpty) {
        QuerySnapshot customerSnap =
            await FirebaseFirestore.instance
                .collection('customers')
                .where('nic', isEqualTo: _nic)
                .limit(1)
                .get();

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
          await customerSnap.docs.first.reference.update({
            'profileImage': downloadUrl,
            'profileImageUrl': downloadUrl,
            'photoURL': downloadUrl,
            'photoUrl': downloadUrl,
          });

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

  Future<void> _cleanData() async {
    final t = AppLocalizations.of(context)!;
    final confirm = await _showConfirmationDialog(
      t.clean_app_data,
      t.clean_app_data_message,
    );

    if (!confirm) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final language = prefs.getString('language');

      await prefs.clear();
      await prefs.setBool('isWelcomeScreenSeen', false);
      await prefs.setBool('isLoggedIn', false);
      await prefs.setBool('isLanguageSelected', false);

      if (language != null) {
        await prefs.setString('language', language);
      }

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

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  Future<bool> _showConfirmationDialog(String title, String message) async {
    final t = AppLocalizations.of(context)!;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (dialogContext) => AlertDialog(
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

  Future<void> _signOut(BuildContext context) async {
    final t = AppLocalizations.of(context)!;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
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

      if (mounted && context.mounted) {
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
    super.build(context);

    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      body: Column(
        children: [
          const SizedBox(height: 80),
          Text(
            t.settings,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 50),

          _buildProfileHeader(),

          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
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
                        items:
                            languageMap.keys.map((language) {
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
                    onTap:
                        () => Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation1, animation2) =>
                                    const AppGuideScreen(),
                            transitionDuration: Duration.zero,
                          ),
                        ),
                  ),

                  _buildSettingTile(
                    title: t.about_us,
                    icon: Icons.info,
                    iconColor: Colors.teal,
                    onTap:
                        () => Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation1, animation2) =>
                                    const AboutUsScreen(),
                            transitionDuration: Duration.zero,
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
              color: Colors.black.withAlpha(13),
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
                      child:
                          _isUploadingImage
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

  Widget _buildProfileImage() {
    if (_profileImageUrl == null || _profileImageUrl!.isEmpty) {
      return const Icon(Icons.person, size: 40, color: Colors.purple);
    }

    String imageUrl = _profileImageUrl!.trim();

    if (!imageUrl.startsWith('http')) {
      if (imageUrl.startsWith('www.')) {
        imageUrl = 'https://$imageUrl';
      } else {
        _invalidUrls[imageUrl] = true;
        return const Icon(Icons.person, size: 40, color: Colors.purple);
      }
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: 64,
      height: 64,
      cacheWidth: 128,
      cacheHeight: 128,
      errorBuilder: (_, __, ___) {
        _invalidUrls[imageUrl] = true;
        return const Icon(Icons.person, size: 40, color: Colors.purple);
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Icon(Icons.person, size: 40, color: Colors.purple);
      },
    );
  }

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
            color: Colors.black.withAlpha(10),
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
                    color:
                        isDanger
                            ? Colors.red.withAlpha(26)
                            : iconColor.withAlpha(26),
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
