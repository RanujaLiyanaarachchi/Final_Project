import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upay/screens/sign_in_screen.dart';
import 'package:upay/l10n/app_localizations.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  static const circleColor = Color.fromRGBO(59, 130, 246, 0.07);
  static const headingColor = Color(0xFF1E293B);
  static const textColor = Color(0xFF64748B);
  static const backgroundColor = Color(0xFFFEFEFF);
  static const backgroundEndColor = Color(0xFFEFF6FF);

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _precacheImages();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });
  }

  Future<void> _precacheImages() async {
    await precacheImage(
      const AssetImage('assets/images/welcome/welcome_image.png'),
      context,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;

    final imageCacheWidth = (size.width * 0.9 * dpr).toInt();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [backgroundColor, backgroundEndColor],
            ),
          ),
          child: FadeTransition(
            opacity: _fadeAnimation,
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

                  _buildMainContent(context, size, imageCacheWidth),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    Size size,
    int imageCacheWidth,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.05,
          vertical: size.height * 0.02,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: size.height * 0.08),

            Padding(
              padding: EdgeInsets.only(left: size.width * 0.03),
              child: Text(
                l10n.hiThere,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: headingColor,
                  letterSpacing: -0.3,
                ),
              ),
            ),

            SizedBox(height: size.height * 0.04),

            Center(
              child: Image.asset(
                'assets/images/welcome/welcome_image.png',
                width: size.width * 0.9,
                fit: BoxFit.fitWidth,
                cacheWidth: imageCacheWidth,
                filterQuality: FilterQuality.medium,
              ),
            ),

            SizedBox(height: size.height * 0.04),

            Center(
              child: Column(
                children: [
                  Text(
                    l10n.welcome_to_UPay,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: headingColor,
                    ),
                  ),

                  SizedBox(height: size.height * 0.02),

                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.18,
                    ),
                    child: Text(
                      l10n.welcome_message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: textColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: size.height * 0.07),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
              child: const OptimizedWelcomeButton(),
            ),

            SizedBox(height: size.height * 0.03),
          ],
        ),
      ),
    );
  }
}

class OptimizedWelcomeButton extends StatefulWidget {
  const OptimizedWelcomeButton({super.key});

  @override
  State<OptimizedWelcomeButton> createState() => _OptimizedWelcomeButtonState();
}

class _OptimizedWelcomeButtonState extends State<OptimizedWelcomeButton> {
  bool _isPressed = false;
  bool _isNavigating = false;

  static final buttonStartColor = Colors.blue.shade300;
  static final buttonEndColor = Colors.blue.shade500;
  static final buttonPressedStartColor = Colors.blue.shade800;
  static final buttonPressedEndColor = Colors.blue.shade900;

  static final normalShadowColor = buttonStartColor.withAlpha(51); // 0.2 * 255
  static final pressedShadowColor = buttonPressedEndColor.withAlpha(
    102,
  ); // 0.4 * 255

  Future<void> _handleNavigation() async {
    if (_isNavigating) return;

    setState(() {
      _isNavigating = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isWelcomeScreenSeen', true);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder:
              (context, animation, secondaryAnimation) => const SignInScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors =
        _isPressed
            ? [buttonPressedStartColor, buttonPressedEndColor]
            : [buttonStartColor, buttonEndColor];

    final shadowColor = _isPressed ? pressedShadowColor : normalShadowColor;
    final offset = _isPressed ? const Offset(0, 3) : const Offset(0, 5);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: _handleNavigation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 10,
              spreadRadius: 2,
              offset: offset,
            ),
          ],
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context)!.lets_begin,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
