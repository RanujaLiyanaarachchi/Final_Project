import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:upay/screens/dashboard_screen.dart';
import 'package:upay/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upay/services/secure_storage_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NicScreen extends StatefulWidget {
  final String phoneNumber;

  const NicScreen({super.key, required this.phoneNumber});

  @override
  State<NicScreen> createState() => _NicScreenState();
}

class _NicScreenState extends State<NicScreen> with WidgetsBindingObserver {
  // Controllers
  final TextEditingController _nicController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _nicFocusNode = FocusNode();

  // State flags - using bool instead of multiple enums for memory efficiency
  bool _isNicValid = false;
  bool _isLoading = false;
  bool _isPressed = false;
  bool _submitted = false;
  bool _isKeyboardVisible = false;
  bool _isBackPressed = false;

  // For error display
  String? _errorText;

  // Regular expressions compiled once for reuse
  static final RegExp _nicType1Regex = RegExp(r'^\d{12}$');
  static final RegExp _nicType2Regex = RegExp(r'^\d{9}[vV]$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nicFocusNode.addListener(_handleFocusChange);

    // Mark that we're on NIC screen at startup
    _markNicScreenActive();
  }

  // Mark that NIC screen is active
  Future<void> _markNicScreenActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Store current navigation state
      await prefs.setBool('on_nic_screen', true);

      // Ensure user is not logged in when on NIC screen
      await SecureStorageService.saveUserLoggedIn(false);

      // Clear any previously auto-filled NIC
      await prefs.remove('auto_fill_nic');
    } catch (e) {
      debugPrint("Error marking NIC screen active: $e");
    }
  }

  void _handleFocusChange() {
    if (_nicFocusNode.hasFocus) {
      setState(() {
        _errorText = null;
        _submitted = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only update state if necessary
    if (state == AppLifecycleState.resumed && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  // Optimized NIC validation - avoid redundant regex checks
  bool _validateNicFormat(String nic) {
    final int length = nic.length;
    if (length == 12) {
      return _nicType1Regex.hasMatch(nic);
    } else if (length == 10) {
      return _nicType2Regex.hasMatch(nic);
    }
    return false;
  }

  // Check internet connection
  Future<bool> _checkInternetConnection() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult.contains(ConnectivityResult.wifi) ||
          connectivityResult.contains(ConnectivityResult.mobile) ||
          connectivityResult.contains(ConnectivityResult.ethernet);
    } catch (e) {
      debugPrint("Error checking connectivity: $e");
      return false;
    }
  }

  Future<void> _validateNic({bool autoVerify = false}) async {
    // Never allow auto-verification
    if (autoVerify) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
    });

    final String nic = _nicController.text.trim();

    // Don't continue if NIC is empty
    if (nic.isEmpty) {
      setState(() {
        _errorText =
            AppLocalizations.of(context)?.enter_valid_nic ?? 'Enter valid NIC';
      });
      return;
    }

    // Check NIC format
    if (!_validateNicFormat(nic)) {
      setState(() {
        _errorText =
            AppLocalizations.of(context)?.nic_incorrect_format ??
            'NIC in incorrect format';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    // Check internet connection first
    bool hasInternet = await _checkInternetConnection();
    if (!hasInternet) {
      if (!mounted) return;
      setState(() {
        _errorText =
            AppLocalizations.of(context)?.connection_error ??
            'Connection error, Try again';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      // Use one Firestore instance to reduce connection overhead
      final firestore = FirebaseFirestore.instance;

      // Check if NIC exists in customers collection
      final QuerySnapshot result =
          await firestore
              .collection('customers')
              .where('nic', isEqualTo: nic)
              .get();

      // Try alternative NIC format if not found
      bool isNicValid = result.docs.isNotEmpty;

      // Only try alternative formats if needed
      if (!isNicValid && nic.length == 10) {
        final String lastChar = nic[9];
        if (lastChar == 'v' || lastChar == 'V') {
          final alternativeChar = (lastChar == 'v') ? 'V' : 'v';
          final alternativeNic = '${nic.substring(0, 9)}$alternativeChar';

          final alternativeResult =
              await firestore
                  .collection('customers')
                  .where('nic', isEqualTo: alternativeNic)
                  .get();

          isNicValid = alternativeResult.docs.isNotEmpty;
        }
      }

      // Case-insensitive search as last resort
      if (!isNicValid) {
        final allDocs =
            await firestore
                .collection('customers')
                .limit(50) // Limit query for better performance
                .get();

        final nicLower = nic.toLowerCase();
        for (final doc in allDocs.docs) {
          final String? docNic = doc.data()['nic'] as String?;
          if (docNic?.toLowerCase() == nicLower) {
            isNicValid = true;
            break;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _isNicValid = isNicValid;
        _isLoading = false;
      });

      if (!isNicValid) {
        setState(() {
          _errorText =
              AppLocalizations.of(context)?.nic_incorrect_format ??
              'Incorrect NIC number. Try again';
        });

        // Clear any saved validation state since NIC is invalid
        await _clearNicValidationState();
      } else {
        // IMPORTANT: Clear the NIC screen flag ONLY for valid NIC
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('on_nic_screen');

        // Save user login information - only for valid NICs
        await AuthService.saveUserLogin(nic: nic, phone: widget.phoneNumber);

        // Store in secure storage for better security
        await SecureStorageService.saveUserNic(nic);
        await SecureStorageService.saveUserPhone(widget.phoneNumber);
        await SecureStorageService.saveUserLoggedIn(true);

        // Link the phone number with this NIC in the database
        await _updateUserData(nic);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
        }
      }
    } catch (e) {
      debugPrint("Error validating NIC: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorText =
              AppLocalizations.of(context)?.connection_error ??
              'Connection error. Try again';
        });

        // Clear any saved validation state on error
        await _clearNicValidationState();
      }
    }
  }

  // Clear all NIC validation state when validation fails
  Future<void> _clearNicValidationState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('nic_verified');

      // Keep on_nic_screen flag to ensure we come back here
      await prefs.setBool('on_nic_screen', true);

      // Remove auto-fill NIC to prevent incorrect NIC from being displayed again
      await prefs.remove('auto_fill_nic');

      // Also clear from secure storage
      await SecureStorageService.saveUserLoggedIn(false);
    } catch (e) {
      debugPrint("Error clearing NIC validation state: $e");
    }
  }

  Future<void> _updateUserData(String nic) async {
    try {
      // Find the customer document by NIC
      final customerQuery =
          await FirebaseFirestore.instance
              .collection('customers')
              .where('nic', isEqualTo: nic)
              .get();

      if (customerQuery.docs.isNotEmpty) {
        // Get the document ID
        final String customerId = customerQuery.docs.first.id;

        // Save the customer ID
        await SecureStorageService.saveUserCustomerId(customerId);

        // Update the document with the new phone number
        await FirebaseFirestore.instance
            .collection('customers')
            .doc(customerId)
            .update({
              'mobileNumber':
                  widget.phoneNumber.startsWith('+94')
                      ? '0${widget.phoneNumber.substring(3)}'
                      : widget.phoneNumber,
            });

        // Only save the last verified NIC - not for auto-fill but for tracking
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_verified_nic', nic);
        await prefs.setString('last_phone', widget.phoneNumber);

        // Add validation flag ONLY for successfully validated NICs
        await prefs.setBool('nic_verified', true);
      }
    } catch (e) {
      debugPrint("Error updating user data: $e");
      // Continue with navigation even if update fails
    }
  }

  @override
  void dispose() {
    _nicController.dispose();
    _nicFocusNode.removeListener(_handleFocusChange);
    _nicFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate dimensions once for reuse
    final size = MediaQuery.of(context).size;
    final horizontalPadding = size.width < 600 ? 40.0 : 50.0;
    final imageHeight = size.width < 600 ? 300.0 : 280.0;

    // Check if keyboard is visible
    final viewInsets = MediaQuery.of(context).viewInsets;
    _isKeyboardVisible = viewInsets.bottom > 0;

    // Prepare colors - reused from sign in page
    final borderColor = Colors.blue.shade100;
    final buttonStartColor = Colors.blue.shade300;
    final buttonEndColor = Colors.blue.shade500;
    final buttonPressedStartColor = Colors.blue.shade800;
    final buttonPressedEndColor = Colors.blue.shade900;

    // Circle bubble color (same as sign in page)
    const circleColor = Color.fromRGBO(59, 130, 246, 0.07);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFEFEFF),
        // This preserves the bottom bubble position when keyboard opens
        resizeToAvoidBottomInset: false,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFEFEFF), Color(0xFFEFF6FF)],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // Decorative circle bubbles (same as sign in page)
                Positioned(
                  top: -size.width * 0.24,
                  right: -size.width * 0.24,
                  child: Container(
                    width: size.width * 0.5,
                    height: size.width * 0.5,
                    decoration: const BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -size.width * 0.25,
                  left: -size.width * 0.25,
                  child: Container(
                    width: size.width * 0.6,
                    height: size.width * 0.6,
                    decoration: const BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                // Main content
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Custom header with back button
                      Padding(
                        padding: EdgeInsets.only(
                          top: 60.0,
                          left: horizontalPadding,
                          right: horizontalPadding,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Centered title
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                AppLocalizations.of(
                                      context,
                                    )?.nic_verification_heading ??
                                    'NIC Verification',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            // Back button aligned to the left with custom animation
                            Positioned(
                              left: -10,
                              child: GestureDetector(
                                onTapDown:
                                    (_) =>
                                        setState(() => _isBackPressed = true),
                                onTapUp: (_) {
                                  setState(() => _isBackPressed = false);
                                  Navigator.pop(context);
                                },
                                onTapCancel:
                                    () =>
                                        setState(() => _isBackPressed = false),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  color: Colors.transparent,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 100),
                                    transform:
                                        Matrix4.identity()
                                          ..scale(_isBackPressed ? 0.9 : 1.0),
                                    child: const Icon(
                                      Icons.arrow_back_ios_rounded,
                                      size: 24,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Expanded(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Space between heading and content
                              SizedBox(height: _isKeyboardVisible ? 100 : 65),

                              // Only show image when keyboard is not visible
                              if (!_isKeyboardVisible) ...[
                                Image.asset(
                                  'assets/images/nic/nic.png',
                                  height: imageHeight,
                                  fit: BoxFit.fitHeight,
                                  errorBuilder:
                                      (_, __, ___) => Container(
                                        height: imageHeight,
                                        color: Colors.grey[200],
                                        child: Center(
                                          child: Icon(
                                            Icons.person_pin,
                                            size: 80,
                                            color: buttonStartColor,
                                          ),
                                        ),
                                      ),
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Added heading text (visible regardless of keyboard state)
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.enter_valid_nic_number ??
                                    'Enter Your NIC',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Added description text (visible regardless of keyboard state)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.nic_verification_message ??
                                      'Please enter your NIC registered with our service',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),

                              // NIC Field - Matching sign in screen design
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: borderColor),
                                ),
                                child: TextFormField(
                                  controller: _nicController,
                                  focusNode: _nicFocusNode,
                                  decoration: InputDecoration(
                                    hintText:
                                        AppLocalizations.of(context)?.nic ??
                                        'NIC Number',
                                    prefixIcon: const Icon(
                                      Icons.assignment_ind_rounded,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 18,
                                    ),
                                    suffixIcon:
                                        _isNicValid
                                            ? Icon(
                                              Icons.check_circle,
                                              color: Colors.blue.shade600,
                                            )
                                            : null,
                                    errorStyle: const TextStyle(
                                      height: 0,
                                      fontSize: 0,
                                    ),
                                  ),
                                  enabled: !_isLoading,
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(12),
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9vV]'),
                                    ),
                                  ],
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                    if (!_isLoading) _validateNic();
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return AppLocalizations.of(
                                            context,
                                          )?.enter_valid_nic ??
                                          'Enter valid NIC';
                                    }
                                    if (!_validateNicFormat(value)) {
                                      return AppLocalizations.of(
                                            context,
                                          )?.nic_incorrect_format ??
                                          'NIC in incorrect format';
                                    }
                                    return null;
                                  },
                                  onChanged:
                                      (value) => setState(
                                        () =>
                                            _isNicValid = _validateNicFormat(
                                              value,
                                            ),
                                      ),
                                  onTap:
                                      () => setState(() {
                                        _submitted = false;
                                        _errorText = null;
                                      }),
                                ),
                              ),

                              const SizedBox(height: 30),

                              // Verify Button - styled like the sign in button
                              GestureDetector(
                                onTapDown:
                                    (_) => setState(() => _isPressed = true),
                                onTapUp:
                                    (_) => setState(() => _isPressed = false),
                                onTapCancel:
                                    () => setState(() => _isPressed = false),
                                onTap: _isLoading ? null : _validateNic,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors:
                                          _isPressed
                                              ? [
                                                buttonPressedStartColor,
                                                buttonPressedEndColor,
                                              ]
                                              : [
                                                buttonStartColor,
                                                buttonEndColor,
                                              ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            _isPressed
                                                ? buttonPressedEndColor
                                                    .withAlpha(
                                                      (0.4 * 255).round(),
                                                    )
                                                : buttonStartColor.withAlpha(
                                                  (0.2 * 255).round(),
                                                ),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                        offset:
                                            _isPressed
                                                ? const Offset(0, 3)
                                                : const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child:
                                        _isLoading
                                            ? Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 3,
                                                      ),
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  AppLocalizations.of(
                                                        context,
                                                      )?.verifying ??
                                                      'Verifying...',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ],
                                            )
                                            : Text(
                                              AppLocalizations.of(
                                                    context,
                                                  )?.verify ??
                                                  'Verify',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                  ),
                                ),
                              ),

                              // Bottom padding depending on keyboard visibility
                              SizedBox(height: _isKeyboardVisible ? 10 : 20),
                            ],
                          ),
                        ),
                      ),

                      // Error messages - only show when keyboard is hidden and there's an error
                      if (_submitted &&
                          !_isKeyboardVisible &&
                          _errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 40,
                            left: 20,
                            right: 20,
                          ),
                          child: Text(
                            _errorText!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
