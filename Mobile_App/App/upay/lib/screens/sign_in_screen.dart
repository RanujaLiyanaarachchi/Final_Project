import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:upay/screens/otp_screen.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:upay/services/auth_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with WidgetsBindingObserver {
  // Controllers and form key
  final TextEditingController nicController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Focus nodes
  final FocusNode _nicFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();

  // State flags - using bool instead of multiple enums for memory efficiency
  bool _isNicValid = false;
  bool _isLoading = false;
  bool _isPressed = false;
  bool _submitted = false;
  bool _isAnyFieldFocused = false;
  bool _isKeyboardVisible = false;

  // For error display
  String? _errorText;

  // Timer for auth timeout
  Timer? _authTimeoutTimer;

  // Auth timeout duration (15 seconds is reasonable)
  static const authTimeoutDuration = Duration(seconds: 15);

  // Regular expressions compiled once for reuse
  static final RegExp _nicType1Regex = RegExp(r'^\d{12}$');
  static final RegExp _nicType2Regex = RegExp(r'^\d{9}[vV]$');
  static final RegExp _nonDigitsRegex = RegExp(r'\D');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nicFocusNode.addListener(_handleFocusChange);
    _phoneFocusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    // Clean up to prevent memory leaks
    WidgetsBinding.instance.removeObserver(this);
    _nicFocusNode.removeListener(_handleFocusChange);
    _phoneFocusNode.removeListener(_handleFocusChange);
    _nicFocusNode.dispose();
    _phoneFocusNode.dispose();
    nicController.dispose();
    phoneController.dispose();
    _authTimeoutTimer?.cancel();
    super.dispose();
  }

  void _handleFocusChange() {
    final bool newFocusState =
        _nicFocusNode.hasFocus || _phoneFocusNode.hasFocus;

    if (newFocusState != _isAnyFieldFocused) {
      setState(() {
        _isAnyFieldFocused = newFocusState;
        if (newFocusState) {
          _submitted = false;
          _errorText = null;
        }
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

  // Start timeout timer for auth process
  void _startAuthTimeout() {
    _authTimeoutTimer?.cancel();
    _authTimeoutTimer = Timer(authTimeoutDuration, () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _errorText =
              AppLocalizations.of(context)?.code_timed_out ??
              'Timed out. Try again';
        });
      }
    });
  }

  // Cancel timeout timer
  void _cancelAuthTimeout() {
    _authTimeoutTimer?.cancel();
    _authTimeoutTimer = null;
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

  // Optimized phone formatting with fewer string operations
  String _formatPhoneNumber(String phone) {
    String cleanPhone = phone.replaceAll(_nonDigitsRegex, '');

    if (cleanPhone.startsWith('0')) {
      return '+94${cleanPhone.substring(1)}';
    } else if (cleanPhone.length == 9) {
      return '+94$cleanPhone';
    } else if (cleanPhone.startsWith('94') && cleanPhone.length > 10) {
      return '+$cleanPhone';
    } else if (!cleanPhone.startsWith('+')) {
      return '+94$cleanPhone';
    }
    return phone;
  }

  // Check internet connection
  Future<bool> _checkInternetConnection() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult.contains(ConnectivityResult.wifi) ||
          connectivityResult.contains(ConnectivityResult.mobile) ||
          connectivityResult.contains(ConnectivityResult.ethernet);
    } catch (e) {
      // If there's an error checking connectivity, assume no connection
      debugPrint("Error checking connectivity: $e");
      return false;
    }
  }

  // Reset all form data
  void _resetForm() {
    nicController.clear();
    phoneController.clear();
    setState(() {
      _isNicValid = false;
      _submitted = false;
      _errorText = null;
      _isLoading = false;
    });
  }

  // Navigate to OTP screen and refresh this page when returning
  void _navigateToOtp({
    required String phoneNumber,
    required String nic,
    String verificationId = '',
    int? resendToken,
    PhoneAuthCredential? credential,
  }) async {
    // Cancel the timeout timer since we're navigating
    _cancelAuthTimeout();

    // Reset form before navigation
    _resetForm();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => OtpScreen(
              verificationId: verificationId,
              phoneNumber: phoneNumber,
              nic: nic,
              resendToken: resendToken,
              credential: credential,
            ),
      ),
    );
  }

  // Submit form handler
  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _submitted = true;
      _isAnyFieldFocused = false;
    });

    // Quick validation before full form validation
    final String nic = nicController.text;
    final String phone = phoneController.text;

    if (nic.isEmpty && phone.isEmpty) {
      setState(
        () =>
            _errorText =
                AppLocalizations.of(context)?.enter_valid_nic_and_phone ??
                'Enter NIC and phone number',
      );
      return;
    }

    _errorText = null;

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

    setState(() => _isLoading = true);

    // Start timeout timer to handle cases where Firebase doesn't respond
    _startAuthTimeout();

    final String formattedPhone = _formatPhoneNumber(phone.trim());
    final String trimmedNic = nic.trim();

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (!mounted) return;

          setState(() => _isLoading = false);

          // Cancel timeout since we got a response
          _cancelAuthTimeout();

          await AuthService.saveUserLogin(
            nic: trimmedNic,
            phone: formattedPhone,
          );

          if (!mounted) return;

          _navigateToOtp(
            phoneNumber: formattedPhone,
            nic: trimmedNic,
            credential: credential,
          );
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;

          // Cancel timeout since we got a response
          _cancelAuthTimeout();

          setState(() {
            _isLoading = false;
            // For any Firebase errors, display generic connection error
            _errorText =
                AppLocalizations.of(context)?.connection_error ??
                'Connection error, Try again';
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;

          // Cancel timeout since we got a response
          _cancelAuthTimeout();

          setState(() => _isLoading = false);

          _navigateToOtp(
            phoneNumber: formattedPhone,
            nic: trimmedNic,
            verificationId: verificationId,
            resendToken: resendToken,
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;

          // We will only respond if we're still loading
          if (_isLoading) {
            _cancelAuthTimeout();

            setState(() {
              _isLoading = false;
              _errorText =
                  AppLocalizations.of(context)?.code_timed_out ??
                  'Timed out. Try again';
            });
          }
        },
        timeout: const Duration(
          seconds: 30,
        ), // Set Firebase timeout to 30 seconds
      );
    } catch (e) {
      if (!mounted) return;

      // Cancel timeout since we got an error response
      _cancelAuthTimeout();

      setState(() {
        _isLoading = false;
        // For any exceptions, display generic connection error
        _errorText =
            AppLocalizations.of(context)?.connection_error ??
            'Connection error, Try again';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reuse dimensions
    final size = MediaQuery.of(context).size;
    final horizontalPadding = size.width < 600 ? 40.0 : 50.0;
    final imageHeight = size.width < 600 ? 300.0 : 280.0;

    // Check if keyboard is visible
    final viewInsets = MediaQuery.of(context).viewInsets;
    _isKeyboardVisible = viewInsets.bottom > 0;

    // Reuse colors
    final borderColor = Colors.blue.shade100;
    final buttonStartColor = Colors.blue.shade300;
    final buttonEndColor = Colors.blue.shade500;
    final buttonPressedStartColor = Colors.blue.shade800;
    final buttonPressedEndColor = Colors.blue.shade900;

    // Circle bubble color (same as welcome page)
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
                // Decorative circle bubbles (same as welcome page)
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
                      // Fixed position header - doesn't change regardless of keyboard
                      Padding(
                        padding: EdgeInsets.only(
                          top: 60.0,
                          left: horizontalPadding,
                          right: horizontalPadding,
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.sign_in ?? 'Sign In',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
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

                              SizedBox(height: _isKeyboardVisible ? 120 : 65),

                              // Only show image when keyboard is not visible
                              if (!_isKeyboardVisible) ...[
                                Image.asset(
                                  'assets/images/sign_in/sign_in.png',
                                  height: imageHeight,
                                  fit: BoxFit.fitHeight,
                                ),
                                const SizedBox(height: 24),
                              ],

                              // NIC Field
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: borderColor),
                                ),
                                child: TextFormField(
                                  controller: nicController,
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
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted:
                                      (_) => FocusScope.of(
                                        context,
                                      ).requestFocus(_phoneFocusNode),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Enter NIC';
                                    }
                                    if (!_validateNicFormat(value)) {
                                      return 'NIC in incorrect format';
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
                              const SizedBox(height: 15),

                              // Phone Number Field
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: borderColor),
                                ),
                                child: TextFormField(
                                  controller: phoneController,
                                  focusNode: _phoneFocusNode,
                                  decoration: InputDecoration(
                                    hintText:
                                        AppLocalizations.of(
                                          context,
                                        )?.phone_number ??
                                        'Phone Number',
                                    prefixIcon: const Icon(Icons.phone),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 18,
                                    ),
                                    errorStyle: const TextStyle(
                                      height: 0,
                                      fontSize: 0,
                                    ),
                                  ),
                                  enabled: !_isLoading,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                    if (!_isLoading) _signIn();
                                  },
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(10),
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Enter phone number';
                                    }
                                    if (value.length != 10 ||
                                        !value.startsWith('0')) {
                                      return 'Phone number must be 10 digits and start with 0';
                                    }
                                    return null;
                                  },
                                  onTap:
                                      () => setState(() {
                                        _submitted = false;
                                        _errorText = null;
                                      }),
                                ),
                              ),

                              const SizedBox(height: 30),

                              // Sign In Button
                              GestureDetector(
                                onTapDown:
                                    (_) => setState(() => _isPressed = true),
                                onTapUp:
                                    (_) => setState(() => _isPressed = false),
                                onTapCancel:
                                    () => setState(() => _isPressed = false),
                                onTap: _isLoading ? null : _signIn,
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
                                                      )?.validating ??
                                                      'Validating...',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ],
                                            )
                                            : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  AppLocalizations.of(
                                                        context,
                                                      )?.sign_in ??
                                                      'Sign In',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                              ],
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

                      // Error messages - only show when keyboard is hidden
                      if (_submitted &&
                          !_isAnyFieldFocused &&
                          !_isKeyboardVisible)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 40,
                            left: 20,
                            right: 20,
                          ),
                          child: _getErrorWidget(),
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

  // Error message widget
  Widget? _getErrorWidget() {
    String? errorMessage;

    // Simplified error message resolution with fewer checks
    if (nicController.text.isEmpty && phoneController.text.isEmpty) {
      errorMessage =
          AppLocalizations.of(context)?.enter_valid_nic_and_phone ??
          'Enter valid NIC and phone number';
    } else if (nicController.text.isEmpty) {
      errorMessage =
          AppLocalizations.of(context)?.enter_valid_nic ?? 'Enter valid NIC';
    } else if (!_validateNicFormat(nicController.text)) {
      errorMessage =
          AppLocalizations.of(context)?.nic_incorrect_format ??
          'NIC in incorrect format';
    } else if (phoneController.text.isEmpty) {
      errorMessage =
          AppLocalizations.of(context)?.enter_valid_phone ??
          'Enter valid phone number';
    } else if (phoneController.text.length != 10 ||
        !phoneController.text.startsWith('0')) {
      errorMessage =
          AppLocalizations.of(context)?.phone_must_be_10_digits ??
          'Phone number must be 10 digits';
    } else if (_errorText != null) {
      errorMessage = _errorText;
    }

    return errorMessage != null ? _buildErrorText(errorMessage) : null;
  }

  // Simple error text builder
  Widget _buildErrorText(String message) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.red.shade700, fontSize: 14),
    );
  }
}
