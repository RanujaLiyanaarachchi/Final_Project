import 'package:flutter/material.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:upay/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  String? _error;
  String? _profileImageUrl;
  bool _isLoadingImage = true;

  String fullName = '';
  String accountNumber = '';
  String customerId = '';
  String nic = '';
  String address = '';
  String email = '';
  String birthDay = '';
  String gender = '';
  String landLine = '';
  String mobile = '';
  String userId = '';

  // Cache keys
  static const String _cacheKey = 'profile_data_cache';
  static const String _cacheDateKey = 'profile_data_cache_date';
  static const String _cacheImageKey = 'profile_image_cache';
  static const int _cacheValidityHours = 24;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      if (await _loadFromCache()) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      await _loadUserData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error loading data: ${e.toString()}';
      });
    }
  }

  Future<bool> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedDataJson = prefs.getString(_cacheKey);
      final cacheDateString = prefs.getString(_cacheDateKey);
      final cachedImageUrl = prefs.getString(_cacheImageKey);

      if (cachedDataJson == null || cacheDateString == null) {
        return false;
      }

      final cacheDate = DateTime.parse(cacheDateString);
      final now = DateTime.now();
      final difference = now.difference(cacheDate);

      if (difference.inHours > _cacheValidityHours) {
        return false;
      }

      final Map<String, dynamic> cachedData = jsonDecode(cachedDataJson);

      setState(() {
        fullName = cachedData['fullName'] ?? '';
        accountNumber = cachedData['accountNumber'] ?? '';
        customerId = cachedData['customerId'] ?? '';
        nic = cachedData['nic'] ?? '';
        address = cachedData['address'] ?? '';
        email = cachedData['email'] ?? '';
        birthDay = cachedData['birthDay'] ?? '';
        gender = cachedData['gender'] ?? '';
        landLine = cachedData['landLine'] ?? '';
        mobile = cachedData['mobile'] ?? '';
        userId = cachedData['userId'] ?? '';

        if (cachedImageUrl != null && cachedImageUrl.isNotEmpty) {
          _profileImageUrl = cachedImageUrl;
        }

        _isLoadingImage = false;
      });

      debugPrint("Loaded profile data from cache");
      return true;
    } catch (e) {
      debugPrint("Failed to load from cache: $e");
      return false;
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final Map<String, dynamic> cacheData = {
        'fullName': fullName,
        'accountNumber': accountNumber,
        'customerId': customerId,
        'nic': nic,
        'address': address,
        'email': email,
        'birthDay': birthDay,
        'gender': gender,
        'landLine': landLine,
        'mobile': mobile,
        'userId': userId,
      };

      await prefs.setString(_cacheKey, jsonEncode(cacheData));
      await prefs.setString(_cacheDateKey, DateTime.now().toIso8601String());

      if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
        await prefs.setString(_cacheImageKey, _profileImageUrl!);
      }

      debugPrint("Saved profile data to cache");
    } catch (e) {
      debugPrint("Failed to save to cache: $e");
    }
  }

  @pragma('vm:entry-point')
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheDateKey);
      await prefs.remove(_cacheImageKey);
      debugPrint("Profile cache cleared");
    } catch (e) {
      debugPrint("Failed to clear profile cache: $e");
    }
  }

  Future<void> _loadUserData() async {
    try {
      final User? currentUser = _auth.currentUser;
      userId = currentUser?.uid ?? '';

      final userNic = await SecureStorageService.getUserNic();

      if (userNic == null || userNic.isEmpty) {
        setState(() {
          _isLoading = false;
          _isLoadingImage = false;
          _error = 'User NIC not found. Please login again.';
        });
        return;
      }

      setState(() {
        nic = userNic;
      });

      debugPrint('Fetching user data with NIC: $userNic');

      final QuerySnapshot snapshot =
          await _firestore
              .collection('customers')
              .where('nic', isEqualTo: userNic)
              .limit(1)
              .get();

      if (snapshot.docs.isEmpty && userNic.length == 10) {
        String alternativeNic;
        if (userNic.endsWith('v')) {
          alternativeNic = '${userNic.substring(0, 9)}V';
        } else if (userNic.endsWith('V')) {
          alternativeNic = '${userNic.substring(0, 9)}v';
        } else {
          alternativeNic = userNic;
        }

        if (alternativeNic != userNic) {
          final alternativeSnapshot =
              await _firestore
                  .collection('customers')
                  .where('nic', isEqualTo: alternativeNic)
                  .limit(1)
                  .get();

          if (alternativeSnapshot.docs.isNotEmpty) {
            _updateUserDataFromDocument(alternativeSnapshot.docs.first);
            await _loadProfileImage();
            await _saveToCache();
            return;
          }
        }
      } else if (snapshot.docs.isNotEmpty) {
        _updateUserDataFromDocument(snapshot.docs.first);
        await _loadProfileImage();
        await _saveToCache();
        return;
      }

      if (currentUser != null && currentUser.phoneNumber != null) {
        final phoneSnapshot =
            await _firestore
                .collection('customers')
                .where('mobile', isEqualTo: currentUser.phoneNumber)
                .limit(1)
                .get();

        if (phoneSnapshot.docs.isNotEmpty) {
          _updateUserDataFromDocument(phoneSnapshot.docs.first);
          await _loadProfileImage();
          await _saveToCache();
          return;
        }
      }

      setState(() {
        _isLoading = false;
        _isLoadingImage = false;
        _error = 'Could not find your profile data.';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingImage = false;
        _error = 'Error loading profile: ${e.toString()}';
      });
      debugPrint('Error loading profile data: $e');
    }
  }

  Future<void> _loadProfileImage() async {
    if (!mounted) return;

    setState(() {
      _isLoadingImage = true;
    });

    try {
      debugPrint("Starting profile image loading...");
      debugPrint("userId=$userId, customerId=$customerId, nic=$nic");

      if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
        debugPrint("Using existing profile URL: $_profileImageUrl");
        setState(() {
          _isLoadingImage = false;
        });
        return;
      }

      List<String> identifiers = [];
      if (userId.isNotEmpty) identifiers.add(userId);
      if (customerId.isNotEmpty) identifiers.add(customerId);
      if (nic.isNotEmpty) identifiers.add(nic);

      if (identifiers.isEmpty) {
        debugPrint("No identifiers available, skipping image loading");
        setState(() {
          _isLoadingImage = false;
        });
        return;
      }

      debugPrint("Will try with identifiers: $identifiers");

      try {
        debugPrint("Listing files in customer_images folder");
        final listResult = await _storage.ref('customer_images').listAll();

        debugPrint(
          "Found ${listResult.items.length} files in customer_images folder",
        );
        for (var item in listResult.items) {
          debugPrint("File found: ${item.name}");
        }

        for (final id in identifiers) {
          for (var item in listResult.items) {
            if (item.name.contains(id)) {
              debugPrint("Found matching file for ID $id: ${item.name}");
              try {
                final url = await item.getDownloadURL();
                debugPrint("Got download URL: $url");

                if (mounted) {
                  setState(() {
                    _profileImageUrl = url;
                    _isLoadingImage = false;
                  });
                }

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_cacheImageKey, url);

                return;
              } catch (e) {
                debugPrint("Error getting download URL: $e");
              }
            }
          }
        }

        debugPrint("No matching files found in listing");
      } catch (e) {
        debugPrint("Error listing files: $e");
      }

      debugPrint("Trying direct paths");

      for (final id in identifiers) {
        final paths = [
          'customer_images/$id.jpg',
          'customer_images/$id.png',
          'customer_images/${id}_profile.jpg',
          'customer_images/${id}_profile.png',
          'customer_images/profile_$id.jpg',
          'customer_images/profile_$id.png',
          'profiles/$id.jpg',
          'profiles/$id.png',
        ];

        for (final path in paths) {
          try {
            debugPrint("Trying path: $path");
            final ref = _storage.ref().child(path);
            final url = await ref.getDownloadURL();

            debugPrint("Success! Found image at $path");
            if (mounted) {
              setState(() {
                _profileImageUrl = url;
                _isLoadingImage = false;
              });

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_cacheImageKey, url);
            }
            return;
          } catch (e) {
            debugPrint("Failed for path $path: $e");
          }
        }
      }

      debugPrint("No profile image found after all attempts");
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
        });
      }
    } catch (e) {
      debugPrint("Error in _loadProfileImage: $e");
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
        });
      }
    }
  }

  void _updateUserDataFromDocument(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;

      String? docProfileImageUrl;
      if (data.containsKey('profileImage') && data['profileImage'] != null) {
        docProfileImageUrl = data['profileImage'];
      } else if (data.containsKey('profileImageUrl') &&
          data['profileImageUrl'] != null) {
        docProfileImageUrl = data['profileImageUrl'];
      } else if (data.containsKey('photoURL') && data['photoURL'] != null) {
        docProfileImageUrl = data['photoURL'];
      } else if (data.containsKey('photoUrl') && data['photoUrl'] != null) {
        docProfileImageUrl = data['photoUrl'];
      } else if (data.containsKey('image') && data['image'] != null) {
        docProfileImageUrl = data['image'];
      }

      String? docUserId =
          data['userId'] ?? data['uid'] ?? data['user_id'] ?? '';

      setState(() {
        fullName = data['fullName'] ?? data['name'] ?? '';
        accountNumber = data['accountNumber'] ?? '';
        customerId =
            data['customerId'] ??
            data['customerID'] ??
            data['customerNo'] ??
            '';
        address = data['address'] ?? '';
        email = data['email'] ?? '';
        birthDay = data['birthday'] ?? data['dateOfBirth'] ?? '';
        gender = data['gender'] ?? '';
        landLine = data['landPhone'] ?? data['landLine'] ?? '';
        mobile = data['mobileNumber'] ?? data['mobile'] ?? '';

        if (docUserId != null && docUserId.isNotEmpty) {
          userId = docUserId;
        }

        if (docProfileImageUrl != null && docProfileImageUrl.isNotEmpty) {
          _profileImageUrl = docProfileImageUrl;
          _isLoadingImage = false;

          SharedPreferences.getInstance().then((prefs) {
            if (docProfileImageUrl != null) {
              prefs.setString(_cacheImageKey, docProfileImageUrl);
            }
          });
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error in _updateUserDataFromDocument: $e");
      setState(() {
        _isLoading = false;
        _isLoadingImage = false;
      });
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    await _loadUserData();
  }

  @override
  Widget build(BuildContext context) {
    final textFieldLabels = [
      AppLocalizations.of(context)?.full_name ?? 'Full Name',
      AppLocalizations.of(context)?.account_number ?? 'Account Number',
      AppLocalizations.of(context)?.nic_number ?? 'NIC Number',
      AppLocalizations.of(context)?.address ?? 'Address',
      AppLocalizations.of(context)?.email ?? 'Email',
      AppLocalizations.of(context)?.birth_day ?? 'Birth Day',
      AppLocalizations.of(context)?.gender ?? 'Gender',
      AppLocalizations.of(context)?.land_line ?? 'Land Line',
      AppLocalizations.of(context)?.mobile ?? 'Mobile',
    ];

    final textFieldValues = [
      fullName,
      accountNumber,
      nic,
      address,
      email,
      birthDay,
      gender,
      landLine,
      mobile,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      body: Column(
        children: [
          const SizedBox(height: 80),
          Stack(
            alignment: Alignment.center,
            children: [
              Text(
                AppLocalizations.of(context)?.profile ?? 'Profile',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),

              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(10.0),
                      child: Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),

              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _refreshData,
                    child: const Padding(
                      padding: EdgeInsets.all(10.0),
                      child: Icon(Icons.refresh, color: Colors.black54),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_isLoading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text('Loading your profile...'),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 60,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, color: Colors.red),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _error = null;
                          });
                          _loadUserData();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 50),
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.purpleAccent,
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: Container(
                                  width: 70,
                                  height: 70,
                                  color: Colors.blue.shade100,
                                  child:
                                      _isLoadingImage
                                          ? const Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.blue,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                          : _profileImageUrl == null
                                          ? Image.asset(
                                            "assets/images/profile/profile.png",
                                            fit: BoxFit.cover,
                                          )
                                          : Image.network(
                                            _profileImageUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (
                                              context,
                                              error,
                                              stackTrace,
                                            ) {
                                              debugPrint(
                                                "Error rendering image: $error",
                                              );
                                              return Image.asset(
                                                "assets/images/profile/profile.png",
                                                fit: BoxFit.cover,
                                              );
                                            },
                                            loadingBuilder: (
                                              context,
                                              child,
                                              loadingProgress,
                                            ) {
                                              if (loadingProgress == null) {
                                                return child;
                                              }
                                              return Center(
                                                child: CircularProgressIndicator(
                                                  value:
                                                      loadingProgress
                                                                  .expectedTotalBytes !=
                                                              null
                                                          ? loadingProgress
                                                                  .cumulativeBytesLoaded /
                                                              loadingProgress
                                                                  .expectedTotalBytes!
                                                          : null,
                                                  color: Colors.blue,
                                                  strokeWidth: 2,
                                                ),
                                              );
                                            },
                                          ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    customerId.isNotEmpty
                                        ? customerId
                                        : 'No Customer ID',
                                    style: const TextStyle(color: Colors.grey),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Divider(thickness: 1),
                        const SizedBox(height: 5),
                      ],
                    ),
                  ),

                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refreshData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: List.generate(textFieldLabels.length, (
                            index,
                          ) {
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 25,
                              ),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 20,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(255, 235, 245, 255),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    textFieldLabels[index],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color.fromARGB(215, 0, 0, 0),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    textFieldValues[index].isNotEmpty
                                        ? textFieldValues[index]
                                        : 'Not provided',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color:
                                          textFieldValues[index].isNotEmpty
                                              ? const Color(0xFF606264)
                                              : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
