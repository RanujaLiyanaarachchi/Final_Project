import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:upay/screens/dashboard_screen.dart';
import 'package:upay/screens/nic_screen.dart';
import 'package:upay/services/auth_service.dart';
import 'dart:async';

class OtpScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final String nic;
  final int? resendToken;
  final PhoneAuthCredential? credential;

  const OtpScreen({
    super.key,
    this.verificationId = '',
    required this.phoneNumber,
    required this.nic,
    this.resendToken,
    this.credential,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with WidgetsBindingObserver {
  final TextEditingController _otpController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final StreamController<ErrorAnimationType> _errorController =
      StreamController<ErrorAnimationType>();

  bool _isLoading = false;
  bool _isResending = false;
  bool _isVerifyingNic = false;
  bool _isPressed = false;
  bool _isBackPressed = false;
  bool _submitted = false;
  bool _isKeyboardVisible = false;
  String? _errorText;

  Timer? _timer;
  int _remainingTime = 60;

  late final String _displayPhoneNumber = _formatDisplayPhoneNumber(
    widget.phoneNumber,
  );

  static final _redTextColor = Colors.red.shade700;

  String _formatDisplayPhoneNumber(String phone) {
    if (phone.startsWith('+94')) {
      return '0${phone.substring(3)}';
    }
    return phone;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.credential != null) {
      _signInWithCredential(widget.credential!);
    } else {
      _startTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  void _startTimer() {
    _remainingTime = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime <= 0) {
        timer.cancel();
      } else {
        setState(() {
          _remainingTime--;
        });
      }
    });
  }

  Future<void> _verifyOtp() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _submitted = true;
    });

    if (_otpController.text.length != 6) {
      setState(() {
        _errorText =
            AppLocalizations.of(context)?.enter_valid_6digit_code ??
            'Please enter a valid 6-digit code';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: _otpController.text,
      );

      await _signInWithCredential(credential);
    } on FirebaseAuthException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText =
            AppLocalizations.of(context)?.enter_correct_otp ??
            'Enter correct OTP code';

        _errorController.add(ErrorAnimationType.shake);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText =
            AppLocalizations.of(context)?.connection_error ??
            'Check your connection and try again';
      });
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      await _auth.signInWithCredential(credential);

      await AuthService.saveUserLogin(
        nic: widget.nic,
        phone: widget.phoneNumber,
      );

      if (!mounted) return;

      _verifyNicAndNavigate();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;

        if (e.code == 'invalid-verification-code') {
          _errorText =
              AppLocalizations.of(context)?.enter_correct_otp ??
              'Enter correct OTP code';
          _errorController.add(ErrorAnimationType.shake);
        } else {
          _errorText =
              AppLocalizations.of(context)?.connection_error ??
              'Check your connection and try again';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText =
            AppLocalizations.of(context)?.connection_error ??
            'Check your connection and try again';
      });
    }
  }

  Future<void> _verifyNicAndNavigate() async {
    setState(() {
      _isVerifyingNic = true;
    });

    try {
      final QuerySnapshot result =
          await FirebaseFirestore.instance
              .collection('customers')
              .where('nic', isEqualTo: widget.nic)
              .get();

      bool isNicValid = result.docs.isNotEmpty;

      if (!isNicValid && widget.nic.length == 10) {
        String? alternativeNic;
        final lastChar = widget.nic[9];

        if (lastChar == 'v') {
          alternativeNic = '${widget.nic.substring(0, 9)}V';
        } else if (lastChar == 'V') {
          alternativeNic = '${widget.nic.substring(0, 9)}v';
        }

        if (alternativeNic != null) {
          final alternativeResult =
              await FirebaseFirestore.instance
                  .collection('customers')
                  .where('nic', isEqualTo: alternativeNic)
                  .get();

          isNicValid = alternativeResult.docs.isNotEmpty;
        }
      }

      if (!isNicValid) {
        final allDocs =
            await FirebaseFirestore.instance
                .collection('customers')
                .limit(50)
                .get();

        final String nicLower = widget.nic.toLowerCase();
        for (var doc in allDocs.docs) {
          final String? docNic = doc.data()['nic'] as String?;
          if (docNic != null && docNic.toLowerCase() == nicLower) {
            isNicValid = true;
            break;
          }
        }
      }

      if (!mounted) return;

      if (isNicValid) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
          (route) => false,
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => NicScreen(phoneNumber: widget.phoneNumber),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isVerifyingNic = false;
        _errorText =
            AppLocalizations.of(context)?.connection_error ??
            'Check your connection and try again';
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_isResending || _remainingTime > 0) return;

    setState(() {
      _isResending = true;
      _errorText = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        forceResendingToken: widget.resendToken,
        verificationCompleted: (PhoneAuthCredential credential) {
          if (!mounted) return;
          setState(() => _isResending = false);
          _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() {
            _isResending = false;
            _errorText =
                AppLocalizations.of(context)?.connection_error ??
                'Check your connection and try again';
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _isResending = false;
          });
          _startTimer();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)?.verification_code_sent_again ??
                    'Verification code sent again',
              ),
              backgroundColor: Colors.green,
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          setState(() => _isResending = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _errorText =
            AppLocalizations.of(context)?.connection_error ??
            'Check your connection and try again';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _otpController.dispose();
    _timer?.cancel();
    _errorController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final horizontalPadding = size.width < 600 ? 40.0 : 50.0;
    final imageHeight = size.width < 600 ? 265.0 : 280.0;

    final viewInsets = MediaQuery.of(context).viewInsets;
    _isKeyboardVisible = viewInsets.bottom > 0;

    final borderColor = Colors.blue.shade100;
    final buttonStartColor = Colors.blue.shade300;
    final buttonEndColor = Colors.blue.shade500;
    final buttonPressedStartColor = Colors.blue.shade800;
    final buttonPressedEndColor = Colors.blue.shade900;

    const circleColor = Color.fromRGBO(59, 130, 246, 0.07);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFEFEFF),
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

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          top: 60.0,
                          left: horizontalPadding,
                          right: horizontalPadding,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                AppLocalizations.of(
                                      context,
                                    )?.otp_verification ??
                                    'OTP Verification',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
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
                              SizedBox(height: _isKeyboardVisible ? 100 : 60),

                              if (!_isKeyboardVisible)
                                Image.asset(
                                  'assets/images/otp/otp.png',
                                  height: imageHeight,
                                  fit: BoxFit.fitHeight,
                                  errorBuilder: (context, _, __) {
                                    return Container(
                                      height: imageHeight,
                                      color: Colors.grey[200],
                                    );
                                  },
                                ),

                              SizedBox(height: _isKeyboardVisible ? 10 : 20),
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.verification_code ??
                                    'Verification Code',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${AppLocalizations.of(context)?.code_sent_to ?? 'Code sent to'} $_displayPhoneNumber',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: _isKeyboardVisible ? 25 : 0),
                              const SizedBox(height: 30),

                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                child: PinCodeTextField(
                                  appContext: context,
                                  length: 6,
                                  controller: _otpController,
                                  keyboardType: TextInputType.number,
                                  animationType: AnimationType.fade,
                                  errorAnimationController: _errorController,
                                  pinTheme: PinTheme(
                                    shape: PinCodeFieldShape.box,
                                    borderRadius: BorderRadius.circular(12),
                                    fieldHeight: 50,
                                    fieldWidth: 40,
                                    activeFillColor: Colors.white,
                                    activeColor: Colors.blue,
                                    selectedColor: Colors.blue.shade300,
                                    inactiveColor: borderColor,
                                    disabledColor: Colors.grey.shade300,
                                    errorBorderColor: Colors.red,
                                  ),
                                  animationDuration: const Duration(
                                    milliseconds: 300,
                                  ),
                                  enableActiveFill: false,
                                  enabled: !_isLoading && !_isVerifyingNic,
                                  onChanged: (value) {
                                    if (_errorText != null || _submitted) {
                                      setState(() {
                                        _errorText = null;
                                        _submitted = false;
                                      });
                                    }

                                    if (value.length == 6 &&
                                        !_isLoading &&
                                        !_isVerifyingNic) {
                                      _verifyOtp();
                                    }
                                  },
                                  onTap: () {
                                    if (_errorText != null || _submitted) {
                                      setState(() {
                                        _errorText = null;
                                        _submitted = false;
                                      });
                                    }
                                  },
                                  beforeTextPaste: (text) {
                                    return text != null &&
                                        text.length == 6 &&
                                        int.tryParse(text) != null;
                                  },
                                  autoFocus: true,
                                ),
                              ),

                              const SizedBox(height: 30),

                              GestureDetector(
                                onTapDown:
                                    (_) => setState(() => _isPressed = true),
                                onTapUp:
                                    (_) => setState(() => _isPressed = false),
                                onTapCancel:
                                    () => setState(() => _isPressed = false),
                                onTap:
                                    (_isLoading || _isVerifyingNic)
                                        ? null
                                        : _verifyOtp,
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
                                        _isLoading || _isVerifyingNic
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
                                                  _isVerifyingNic
                                                      ? AppLocalizations.of(
                                                            context,
                                                          )?.verifying ??
                                                          'Verifying...'
                                                      : AppLocalizations.of(
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
                                                      )?.verify ??
                                                      'Verify',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    AppLocalizations.of(
                                          context,
                                        )?.didnt_receive_code ??
                                        "Didn't receive code? ",
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 14,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        _remainingTime <= 0 && !_isResending
                                            ? _resendOtp
                                            : null,
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          _remainingTime <= 0 && !_isResending
                                              ? Colors.blue
                                              : Colors.grey,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      _remainingTime > 0
                                          ? '${AppLocalizations.of(context)?.resend ?? "Resend"} (${_remainingTime}s)'
                                          : AppLocalizations.of(
                                                context,
                                              )?.resend ??
                                              "Resend",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: _isKeyboardVisible ? 10 : 20),
                            ],
                          ),
                        ),
                      ),

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
                              color: _redTextColor,
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
